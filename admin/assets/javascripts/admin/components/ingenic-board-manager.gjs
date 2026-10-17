import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { fn } from "@ember/helper";
import { ajax } from "discourse/lib/ajax";
import DNativeSelect from "discourse/ui-kit/d-native-select";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/admin/plugins/discourse-ingenic/boards";

// A new board starts unpublished. The application link is what a card is for,
// so a half-filled row is not something to put on the site by default.
const BLANK = {
  slug: "",
  name: "",
  locale: "",
  kind: "board",
  product_id: "",
  chip: "",
  description: "",
  details: "",
  specs: "",
  image_url: "",
  documentation_url: "",
  application_url: "",
  purchase_url: "",
  published: false,
  position: 0,
};

/**
 * The development board catalogue.
 *
 * A board is filed against a chip in the product tree, which is what gives the
 * public page its series and chip filters. The chip can also be left unset: a
 * board is often listed before its chip has been written up in the docs, and
 * the form then falls back to a chip name typed by hand.
 */
export default class IngenicBoardManager extends Component {
  @service siteSettings;

  // A new row is filed in the language this site serves rather than in
  // English: a row under a locale no reader's interface uses is a row nobody
  // finds, and nothing reports the mistake.
  get defaultLocale() {
    return this.siteSettings.ingenic_default_locale || "";
  }

  @tracked records = this.args.boards ?? [];
  @tracked draft = null;
  @tracked busy = false;
  @tracked message = null;
  @tracked error = null;

  get chips() {
    return this.args.chips ?? [];
  }

  get chipLabel() {
    return (chip) =>
      chip.series_name ? `${chip.series_name} › ${chip.name}` : chip.name;
  }

  // Kept in one place so the list and the select cannot disagree about what a
  // stored value means.
  get kindLabel() {
    return (record) =>
      i18n(
        record.kind === "sample"
          ? "admin.ingenic.boards.fields.kind_sample"
          : "admin.ingenic.boards.fields.kind_board"
      );
  }

  @action
  startNew() {
    this.draft = { ...BLANK, locale: this.defaultLocale };
    this.message = null;
    this.error = null;
  }

  @action
  edit(record) {
    this.draft = { ...record, product_id: record.product_id ?? "" };
    this.message = null;
    this.error = null;
  }

  @action
  cancel() {
    this.draft = null;
    this.message = null;
    this.error = null;
  }

  // The ui-kit select drives the draft, and the draft is what the form was
  // built from, so the two are kept in step. The value still travels as a form
  // field: the select carries a name and the browser reads the choice back out
  // of it when the form is submitted.
  @action
  pickKind(value) {
    this.draft = { ...this.draft, kind: value || "board" };
  }

  @action
  pickChip(value) {
    this.draft = { ...this.draft, product_id: value ?? "" };
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
    // An unchecked box is absent from FormData, which the server reads as
    // "leave it alone" — the opposite of what unchecking means here.
    form.set("published", String(event.target.elements.published.checked));

    const id = this.draft.id;

    try {
      const response = await ajax(id ? `${ENDPOINT}/${id}` : ENDPOINT, {
        type: id ? "PUT" : "POST",
        data: form,
        // A file is not uploaded here, but the payload is sent as multipart so
        // the picker's null choice survives as an empty field rather than being
        // dropped, which would read as "unchanged".
        processData: false,
        contentType: false,
      });

      const saved = response.board;
      this.records = id
        ? this.records.map((record) => (record.id === saved.id ? saved : record))
        : [...this.records, saved];
      this.draft = null;
      this.message = i18n("admin.ingenic.saved");
    } catch (failure) {
      this.error =
        failure?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("admin.ingenic.save_failed");
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
      this.error =
        failure?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("admin.ingenic.save_failed");
    }
  }

  <template>
    <div class="ingenic-admin-panel">
      {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin__toolbar">
        <button class="btn btn-primary" type="button" {{on "click" this.startNew}}>
          {{i18n "admin.ingenic.boards.add"}}
        </button>
      </div>

      {{#if this.draft}}
        <form class="ingenic-admin-form" {{on "submit" this.save}} {{on "input" this.field}}>
          <h3>
            {{#if this.draft.id}}
              {{i18n "admin.ingenic.boards.edit_title"}}
            {{else}}
              {{i18n "admin.ingenic.boards.new_title"}}
            {{/if}}
          </h3>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.name"}}</span>
            <input name="name" value={{this.draft.name}} required />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.slug"}}</span>
            <input name="slug" value={{this.draft.slug}} required />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.locale"}}</span>
            <input name="locale" value={{this.draft.locale}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.kind"}}</span>
            <DNativeSelect
              name="kind"
              @value={{this.draft.kind}}
              @onChange={{this.pickKind}}
              as |select|
            >
              <select.Option @value="board">
                {{i18n "admin.ingenic.boards.fields.kind_board"}}
              </select.Option>
              <select.Option @value="sample">
                {{i18n "admin.ingenic.boards.fields.kind_sample"}}
              </select.Option>
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.chip_from_tree"}}</span>
            {{! A Glimmer-rendered `selected` attribute does not survive
                re-rendering, which is the bug DNativeSelect exists to work
                around. The blank option it adds is how a board is left
                unfiled. }}
            <DNativeSelect
              name="product_id"
              @value={{this.draft.product_id}}
              @onChange={{this.pickChip}}
              as |select|
            >
              {{#each this.chips as |chip|}}
                <select.Option @value={{chip.id}}>
                  {{this.chipLabel chip}}
                </select.Option>
              {{/each}}
            </DNativeSelect>
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.chip_name"}}</span>
            <input name="chip" value={{this.draft.chip}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.boards.fields.chip_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.application_url"}}</span>
            <input name="application_url" value={{this.draft.application_url}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.boards.fields.application_url_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.documentation_url"}}</span>
            <input name="documentation_url" value={{this.draft.documentation_url}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.purchase_url"}}</span>
            <input name="purchase_url" value={{this.draft.purchase_url}} />
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.boards.fields.purchase_url_hint"}}
          </p>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.image_url"}}</span>
            <input name="image_url" value={{this.draft.image_url}} />
          </label>

          <label>
            <span>{{i18n "admin.ingenic.boards.fields.position"}}</span>
            <input type="number" name="position" value={{this.draft.position}} />
          </label>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "admin.ingenic.boards.fields.description"}}</span>
            <textarea name="description">{{this.draft.description}}</textarea>
          </label>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "admin.ingenic.boards.fields.details"}}</span>
            <textarea name="details" rows="5">{{this.draft.details}}</textarea>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.boards.fields.details_hint"}}
          </p>

          <label class="ingenic-admin-form__wide">
            <span>{{i18n "admin.ingenic.boards.fields.specs"}}</span>
            <textarea name="specs">{{this.draft.specs}}</textarea>
          </label>

          <p class="ingenic-admin-form__hint">
            {{i18n "admin.ingenic.boards.fields.specs_hint"}}
          </p>

          <label class="checkbox-label">
            <input type="checkbox" name="published" checked={{this.draft.published}} />
            <span>{{i18n "admin.ingenic.boards.fields.published"}}</span>
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
                {{record.slug}}
                · {{this.kindLabel record}}
                {{#if record.chip_name}}· {{record.chip_name}}{{/if}}
                {{#if record.series_name}}· {{record.series_name}}{{/if}}
                · {{record.locale}}
                {{#unless record.published}}
                  · {{i18n "admin.ingenic.boards.withdrawn"}}
                {{/unless}}
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
                  {{i18n "admin.ingenic.boards.withdraw"}}
                </button>
              {{/if}}
            </div>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.boards.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
