import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { fn, get } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/downloads";

// A new resource starts at the lowest tier and unpublished. Both defaults are
// the ones that cannot leak a file by accident.
const BLANK = {
  product_slug: "",
  category_id: "",
  version: "",
  locale: "",
  name: "",
  description: "",
  platform: "",
  architecture: "",
  access_level: "public_login",
  point_cost: 0,
  file_url: "",
  file_size: "",
  sha256: "",
  released_on: "",
  position: 0,
  published: false,
};

/**
 * SDK and firmware resources: the list, and the form that creates and edits
 * them, including the upload.
 *
 * The file input is the reason the form is submitted as FormData rather than as
 * a plain object: a firmware image cannot be sent as a URL-encoded field. The
 * server decides between the upload and the URL, and clears the URL when a file
 * arrives, so the form does not have to arbitrate between them.
 */
export default class IngenicDownloadManager extends Component {
  @service siteSettings;

  @tracked records = this.args.downloads ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  // The classification list is editable, so it arrives with the listing rather
  // than being a fixed set here. An empty list is a normal state: nothing has
  // been filed yet, and the field offers "none" until the list is populated.
  get categories() {
    return this.args.categories ?? [];
  }

  get accessLevels() {
    return this.args.accessLevels ?? [];
  }

  get accessLevelKeys() {
    return {
      public_login: "admin.ingenic.downloads.access.public_login",
      login_form: "admin.ingenic.downloads.access.login_form",
      login_form_request: "admin.ingenic.downloads.access.login_form_request",
    };
  }

  get accessLevelHint() {
    const key = this.accessLevelKeys[this.draft?.access_level];
    return key ? i18n(`${key}_hint`) : null;
  }

  // The languages this Discourse serves, sent with the listing. A list
  // rather than free text because the front end matches this value against
  // the reader's locale: a spelling no reader's locale equals is a resource
  // no reader can find, and the mistake reports nothing.
  get localeOptions() {
    const options = [...(this.args.locales ?? [])];
    const current = this.draft?.locale;

    // A row filed before a language was switched off still has to show
    // what it is filed under, or the field would read blank.
    if (current && !options.some((option) => option.value === current)) {
      options.unshift({ value: current, name: current });
    }

    return options.length ? options : [{ value: this.defaultLocale, name: this.defaultLocale }];
  }

  // New content is filed in the language this site serves rather than in
  // English: the readers are the ones who have to find it.
  get defaultLocale() {
    return this.siteSettings.ingenic_default_locale || "";
  }

  // An uploaded file carries its own digest; the legacy column is what a
  // hand-entered URL used to come with. Showing whichever exists is what
  // keeps this field from reading blank on a file the server hashed.
  get checksum() {
    return this.draft?.file_sha256 || this.draft?.sha256 || "";
  }

  // What the row already holds, said in the form rather than left to the
  // file input: an empty file input says "no file chosen" even when the
  // stored file is intact.
  get storedFileLabel() {
    const name = this.draft?.original_filename;

    if (!name) {
      return null;
    }

    return this.draft?.file_size ? `${name} (${this.draft.file_size})` : name;
  }

  @action
  startNew() {
    this.draft = { ...BLANK, locale: this.defaultLocale };
    this.message = null;
    this.error = null;
  }

  @action
  edit(record) {
    this.draft = {
      ...record,
      file_url: record.file_url ?? "",
      locale: record.locale || this.defaultLocale,
    };
    this.message = null;
    this.error = null;
  }

  @action
  cancel() {
    this.draft = null;
    this.message = null;
    this.error = null;
  }

  // The ui-kit selects drive the draft rather than the form, so the values they
  // own are kept in step here. They are still submitted as form fields: the
  // select carries a name and the browser reads the chosen option back out.
  @action
  pickCategory(value) {
    this.draft = { ...this.draft, category_id: value };
  }

  @action
  pickAccessLevel(value) {
    this.draft = { ...this.draft, access_level: value };
  }

  @action
  pickLocale(value) {
    this.draft = { ...this.draft, locale: value };
  }

  // The text fields are bound one way, and a re-render puts the draft back
  // into them, over whatever was typed: the draft never heard about the
  // typing. Keeping it in step as the form is filled in is what stops a click
  // on a select - or a save the server refuses - from emptying the form.
  @action
  field(event) {
    const { name, type, value, checked } = event.target;

    // The selects keep the draft in step in their own handlers, and a file
    // input's value is a fake path rather than a filename.
    if (!name || type === "file" || type.startsWith("select")) {
      return;
    }

    this.draft[name] = type === "checkbox" ? checked : value;
  }

  @action
  async save(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    this.error = null;

    const form = new FormData(event.target);
    // Checkboxes are absent from FormData when unchecked, which the server reads
    // as "leave it alone" — the opposite of what unchecking means here.
    form.set("published", String(event.target.elements.published.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        // Both are required for a multipart body: jQuery would otherwise
        // url-encode the FormData and drop the browser's boundary header.
        processData: false,
        contentType: false,
      });

      const saved = response.download;
      this.records = id
        ? this.records.map((record) => (record.id === saved.id ? saved : record))
        : [...this.records, saved];
      this.draft = null;
      this.message = i18n("admin.ingenic.saved");
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  async withdraw(record, event) {
    event.preventDefault();
    this.error = null;

    try {
      await ajax(`${ENDPOINT}/${record.id}`, { type: "DELETE" });
      this.records = this.records.map((item) =>
        item.id === record.id ? { ...item, published: false } : item
      );
    } catch (failure) {
      this.error = this.#errorMessage(failure);
    }
  }

  #errorMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(", ") || i18n("admin.ingenic.save_failed");
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if @storageWritable}}
        <p class="ingenic-admin-note">{{i18n "admin.ingenic.downloads.storage_ok"}}</p>
      {{else}}
        <p class="ingenic-admin-note ingenic-admin-note--error">
          {{i18n "admin.ingenic.downloads.storage_unavailable"}}
        </p>
      {{/if}}

      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "admin.ingenic.downloads.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "admin.ingenic.downloads.edit_title"}}
            {{else}}
              {{i18n "admin.ingenic.downloads.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.name"}}</span>
            <input name="name" value={{this.draft.name}} required />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.product_slug"}}</span>
            <input name="product_slug" value={{this.draft.product_slug}} required />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.kind"}}</span>
            {{! The ui-kit select rather than a bare <select>: a Glimmer-rendered
                `selected` attribute does not survive re-rendering, which is the
                bug DNativeSelect exists to work around. }}
            <DNativeSelect
              name="category_id"
              @includeNone={{true}}
              @nonePlaceholder={{i18n "admin.ingenic.downloads.fields.no_category"}}
              @value={{this.draft.category_id}}
              @onChange={{this.pickCategory}}
              as |select|
            >
              {{#each this.categories as |category|}}
                <select.Option @value={{category.id}}>{{category.name}}</select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.version"}}</span>
            <input name="version" value={{this.draft.version}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.platform"}}</span>
            <input name="platform" value={{this.draft.platform}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.architecture"}}</span>
            <input name="architecture" value={{this.draft.architecture}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.locale"}}</span>
            {{! The ui-kit select rather than free text: the value is
                matched against the reader's locale, so a spelling nobody
                else uses hides the resource from everyone. }}
            <DNativeSelect
              name="locale"
              @includeNone={{false}}
              @value={{this.draft.locale}}
              @onChange={{this.pickLocale}}
              as |select|
            >
              {{#each this.localeOptions as |option|}}
                <select.Option @value={{option.value}}>{{option.name}}</select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.access_level"}}</span>
            <DNativeSelect
              name="access_level"
              @includeNone={{false}}
              @value={{this.draft.access_level}}
              @onChange={{this.pickAccessLevel}}
              as |select|
            >
              {{#each this.accessLevels as |level|}}
                <select.Option @value={{level}}>
                  {{i18n (get this.accessLevelKeys level)}}
                </select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          {{#if this.accessLevelHint}}
            <p class="ingenic-admin-form__hint">{{this.accessLevelHint}}</p>
          {{/if}}

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.point_cost"}}</span>
            <input type="number" name="point_cost" min="0" value={{this.draft.point_cost}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.downloads.fields.point_cost_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.file"}}</span>
            <input type="file" name="file" />
          </label>

          {{#if this.storedFileLabel}}
            <p class="ingenic-admin-form__hint">
              {{i18n "admin.ingenic.downloads.fields.stored_file" file=this.storedFileLabel}}
            </p>
          {{/if}}

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.downloads.fields.file_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.file_url"}}</span>
            <input name="file_url" value={{this.draft.file_url}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.file_size"}}</span>
            <input name="file_size" value={{this.draft.file_size}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.sha256"}}</span>
            <input name="sha256" value={{this.checksum}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.downloads.fields.sha256_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.released_on"}}</span>
            <input type="date" name="released_on" value={{this.draft.released_on}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.downloads.fields.description"}}</span>
            <textarea name="description">{{this.draft.description}}</textarea>
          </label>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "admin.ingenic.downloads.fields.published"}}</span>
          </label>

          <div class="ingenic-admin__toolbar">
            <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
              {{i18n "admin.ingenic.save"}}
            </button>
            <button class="btn" type="button" {{on "click" this.cancel}}>
              {{i18n "admin.ingenic.cancel"}}
            </button>
          </div>
        </form>
      {{/if}}

      <div class="ingenic-admin-list">
        {{#each this.records as |record|}}
          <section class="ingenic-admin-list__row">
            <div>
              <strong>{{record.name}}</strong>
              <div class="ingenic-admin-list__meta">
                {{record.product_slug}}
                {{#if record.category_name}}· {{record.category_name}}{{/if}}
                {{#if record.version}}· {{record.version}}{{/if}}
                · {{i18n (get this.accessLevelKeys record.access_level)}}
                {{#if record.point_cost}}
                  · {{i18n "admin.ingenic.downloads.costs_points" points=record.point_cost}}
                {{/if}}
                {{#if record.stored}}
                  · {{i18n "admin.ingenic.downloads.stored"}}
                {{/if}}
                {{#unless record.published}}
                  · {{i18n "admin.ingenic.downloads.withdrawn"}}
                {{/unless}}
              </div>
              <div class="ingenic-admin-list__meta">
                {{i18n "admin.ingenic.downloads.pending_count" count=record.pending_requests}}
                ·
                {{i18n "admin.ingenic.downloads.grant_count" count=record.active_grants}}
              </div>
            </div>
            <div class="ingenic-admin__toolbar">
              <button class="btn" type="button" {{on "click" (fn this.edit record)}}>
                {{i18n "admin.ingenic.edit"}}
              </button>
              {{#if record.published}}
                <button
                  class="btn btn-danger"
                  type="button"
                  {{on "click" (fn this.withdraw record)}}
                >
                  {{i18n "admin.ingenic.downloads.withdraw"}}
                </button>
              {{/if}}
            </div>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.downloads.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
