import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import IngenicDocPageForm from "./ingenic-doc-page-form";
import IngenicDocPageTree from "./ingenic-doc-page-tree";

const BASE = "/admin/plugins/discourse-ingenic";

/**
 * Authoring surface for the documentation tree.
 *
 * The shape is series -> chip -> version -> pages. Picking a version loads the
 * pages it resolves to, which includes everything inherited from earlier
 * versions; those rows are marked and can only be edited after being
 * materialised into the current version.
 */
export default class IngenicDocManager extends Component {
  @tracked series = this.args.series;
  @tracked selectedChipId = null;
  @tracked selectedVersionId = null;
  @tracked pages = [];
  @tracked selectedPageSlug = null;
  @tracked busy = false;
  @tracked error = null;
  @tracked importMessage = null;
  // Which row is open for editing, by id. Only one at a time: the forms are
  // drawn inside the list, and two open forms on a narrow screen push the rest
  // of the tree out of view.
  @tracked editingProductId = null;
  @tracked editingVersionId = null;

  get chips() {
    return this.series.flatMap((entry) => entry.chips ?? []);
  }

  get versions() {
    return this.chips.find((chip) => chip.id === this.selectedChipId)?.versions ?? [];
  }

  get selectedChip() {
    return this.chips.find((chip) => chip.id === this.selectedChipId) ?? null;
  }

  get selectedVersion() {
    return this.versions.find((version) => version.id === this.selectedVersionId) ?? null;
  }

  get selectedPage() {
    return this.pages.find((page) => page.slug === this.selectedPageSlug) ?? null;
  }

  // The site's served languages, plus the row's own value when it is not one
  // of them: a row filed under "en" on a Chinese site has to show "en" in the
  // picker, or saving any other field would silently move it to the first
  // option and take it off the reader's screen.
  localeOptions(current) {
    const options = this.args.locales ?? [];

    if (current && !options.some((option) => option.value === current)) {
      return [{ value: current, name: current }, ...options];
    }

    return options;
  }

  @action
  async reload() {
    const payload = await ajax(`${BASE}/documentation`);
    this.series = payload.series;
  }

  @action
  async selectChip(chip) {
    this.selectedChipId = chip.id;
    this.selectedPageSlug = null;
    this.pages = [];
    this.importMessage = null;

    const version = (chip.versions ?? []).find((entry) => entry.latest) ?? (chip.versions ?? [])[0];

    if (version) {
      await this.selectVersion(version);
    } else {
      this.selectedVersionId = null;
    }
  }

  @action
  async selectVersion(version) {
    this.selectedVersionId = version.id;
    this.selectedPageSlug = null;
    this.importMessage = null;
    await this.loadTree();
  }

  @action
  async loadTree() {
    if (!this.selectedVersionId) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const payload = await ajax(`${BASE}/documentation/versions/${this.selectedVersionId}/tree`);
      this.pages = payload.pages;
    } catch {
      this.error = i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  @action
  selectPage(page) {
    this.selectedPageSlug = page.slug;
  }

  @action
  async createSeries(event) {
    await this.#create(event, "documentation/products", { kind: "series" });
  }

  @action
  async createChip(event) {
    // The series is carried by the form itself: a new series has no chip to
    // select, so deriving the parent from the selection left an empty series
    // impossible to fill.
    await this.#create(event, "documentation/products", { kind: "chip" });
  }

  @action
  async createVersion(event) {
    await this.#create(event, "documentation/versions", { product_id: this.selectedChipId });
  }

  // A version is created in one field and corrected in another; without these
  // controls a typo in the label, a slug that was guessed wrong, or a version
  // filed under the wrong language could only be fixed in the database.
  @action
  toggleVersionEdit(version) {
    this.editingVersionId = this.editingVersionId === version.id ? null : version.id;
    this.editingProductId = null;
  }

  @action
  cancelVersionEdit() {
    this.editingVersionId = null;
  }

  @action
  async saveVersion(event, version) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, {
        type: "PUT",
        data: {
          label: values.label?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          // An empty date input is "no date", not the epoch.
          released_on: values.released_on || null,
          deprecated: form.elements.deprecated.checked,
        },
      });
      this.editingVersionId = null;
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Version order is not cosmetic: a version inherits from the ones before it,
  // so swapping two rows changes what a reader sees at each version.
  @action
  async moveVersion(version, direction) {
    const index = this.versions.findIndex((entry) => entry.id === version.id);
    const target = index + direction;

    if (index < 0 || target < 0 || target >= this.versions.length) {
      return;
    }

    const reordered = [...this.versions];
    reordered.splice(index, 1);
    reordered.splice(target, 0, version);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/versions/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async destroyVersion(version) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_version_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, { type: "DELETE" });

      if (version.id === this.selectedVersionId) {
        this.selectedVersionId = null;
        this.selectedPageSlug = null;
        this.pages = [];
      }

      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Which version a reader lands on when the URL names none. The imported and
  // hand-written rows both start with no flag, so without this control a chip
  // with two versions would land on whichever the database happened to return
  // first. Flagging one clears the flag on its siblings: two "latest" versions
  // is not a state the reader can interpret.
  @action
  async toggleLatest(event) {
    const latest = event.target.checked;

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        this.versions
          .filter((version) => version.id !== this.selectedVersionId && version.latest)
          .map((version) =>
            ajax(`${BASE}/documentation/versions/${version.id}`, {
              type: "PUT",
              data: { latest: false },
            })
          )
      );

      await ajax(`${BASE}/documentation/versions/${this.selectedVersionId}`, {
        type: "PUT",
        data: { latest },
      });
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async createPage(event) {
    // The parent is an id picked from the tree, not a slug typed from memory:
    // a slug that matched nothing used to create the page at the top level
    // without saying so, which is why "the folder would not take".
    const values = Object.fromEntries(new FormData(event.target));
    await this.#create(event, "documentation/pages", {
      version_id: this.selectedVersionId,
      kind: values.kind || "page",
    });
  }

  // Sibling order, rewritten for the whole list. Rows created before this
  // control all carry position 0, so swapping two neighbours would move
  // nothing. Inherited rows are left alone: their position belongs to the
  // version that owns them.
  @action
  async movePage(page, direction) {
    const siblings = this.pages.filter(
      (entry) =>
        (entry.parent_slug ?? null) === (page.parent_slug ?? null) &&
        !entry.inherited
    );
    const index = siblings.findIndex((entry) => entry.id === page.id);
    const target = index + direction;

    if (index < 0 || target < 0 || target >= siblings.length) {
      return;
    }

    const reordered = [...siblings];
    reordered.splice(index, 1);
    reordered.splice(target, 0, page);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/pages/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // A file is a whole page, not a field: a team that already has its manual as
  // Markdown or Word should not have to copy each file's text in by hand. The
  // server reports each failure separately, so one unsupported file does not
  // hide the pages that imported.
  @action
  async importPages(event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;
    this.importMessage = null;

    try {
      const response = await ajax(`${BASE}/documentation/versions/${this.selectedVersionId}/import`, {
        type: "POST",
        data: new FormData(event.target),
        processData: false,
        contentType: false,
      });

      this.importMessage = i18n("admin.ingenic.documentation.imported", {
        count: response.imported?.length ?? 0,
      });

      if (response.errors?.length) {
        this.error = response.errors
          .map((entry) => `${entry.file}: ${entry.error}`)
          .join("; ");
      }

      event.target.reset();
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async savePage(page, values) {
    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, { type: "PUT", data: values });
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Copies an inherited page into the selected version so it can diverge here.
  @action
  async overridePage(page) {
    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${this.selectedVersionId}/pages/${page.slug}/override`, {
        type: "POST",
      });
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Drops the version's own copy, sending the page back to inheritance.
  @action
  async revertPage(page) {
    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${this.selectedVersionId}/pages/${page.slug}`, {
        type: "DELETE",
      });
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Series and chips are the front end's first two filter rows, so the words a
  // visitor picks from — and the slug the address spells, the language a reader
  // must be using to see it, and whether it is on the site at all — are edited
  // here rather than in code. A chip created before the locale fix is filed
  // under "en"; without this form the only way to make it visible was to
  // delete it and write its content again.
  @action
  toggleProductEdit(record) {
    this.editingProductId = this.editingProductId === record.id ? null : record.id;
    this.editingVersionId = null;
  }

  @action
  cancelProductEdit() {
    this.editingProductId = null;
  }

  @action
  async saveProduct(event, record) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "PUT",
        data: {
          name: values.name?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          published: form.elements.published.checked,
        },
      });
      this.editingProductId = null;
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Positions are rewritten for the whole sibling list rather than swapped
  // with the neighbour: rows created before this control existed all have
  // position 0, and swapping two zeroes moves nothing.
  @action
  async moveProduct(record, direction) {
    const siblings =
      record.kind === "series"
        ? this.series
        : this.series.find((entry) => entry.id === record.parent_id)?.chips ?? [];
    const index = siblings.findIndex((entry) => entry.id === record.id);
    const target = index + direction;

    if (index < 0 || target < 0 || target >= siblings.length) {
      return;
    }

    const reordered = [...siblings];
    reordered.splice(index, 1);
    reordered.splice(target, 0, record);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/products/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async destroyProduct(record) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "DELETE",
      });
      if (record.id === this.selectedChipId) {
        this.selectedChipId = null;
        this.selectedVersionId = null;
        this.pages = [];
      }
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async destroyPage(page) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_page_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, { type: "DELETE" });
      this.selectedPageSlug = null;
      await this.loadTree();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  async #create(event, endpoint, extra) {
    // Without this the browser also performs the form's own GET, throwing away
    // the admin screen and its selection just after the record is saved.
    event.preventDefault();
    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/${endpoint}`, {
        type: "POST",
        data: { ...Object.fromEntries(new FormData(event.target)), ...extra },
      });
      event.target.reset();
      await this.reload();

      if (endpoint !== "documentation/products" && this.selectedVersionId) {
        await this.loadTree();
      }
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  #errorMessage(error) {
    return error.jqXHR?.responseJSON?.errors?.join(", ") || i18n("admin.ingenic.save_failed");
  }

  <template>
    {{#if this.error}}<p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>{{/if}}

    <div class="ingenic-doc-manager">
      <aside class="ingenic-doc-manager__products">
        <form class="ingenic-admin-form ingenic-admin-form--inline" {{on "submit" this.createSeries}}>
          <input name="name" placeholder={{i18n "admin.ingenic.documentation.series_name"}} required />
          <input name="slug" placeholder={{i18n "admin.ingenic.documentation.series_slug"}} required />
          <select name="locale" required>
            {{#each @locales as |locale|}}
              <option value={{locale.value}} selected={{eq locale.value @defaultLocale}}>
                {{locale.name}}
              </option>
            {{/each}}
          </select>
          <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.create"}}</button>
        </form>

        {{#each this.series as |entry|}}
          <section class="ingenic-doc-manager__series">
            <h4>
              <span>{{entry.name}}</span>
              <span class="ingenic-doc-manager__tools">
                <button type="button" title={{i18n "admin.ingenic.documentation.move_up"}} {{on "click" (fn this.moveProduct entry -1)}}>↑</button>
                <button type="button" title={{i18n "admin.ingenic.documentation.move_down"}} {{on "click" (fn this.moveProduct entry 1)}}>↓</button>
                <button type="button" title={{i18n "admin.ingenic.documentation.edit"}} {{on "click" (fn this.toggleProductEdit entry)}}>✎</button>
                <button type="button" title={{i18n "admin.ingenic.documentation.delete"}} {{on "click" (fn this.destroyProduct entry)}}>×</button>
              </span>
            </h4>

            {{#if (eq entry.id this.editingProductId)}}
              <form class="ingenic-admin-form ingenic-admin-form--inline ingenic-doc-manager__edit-form" {{on "submit" (fn this.saveProduct entry)}}>
                <input name="name" value={{entry.name}} placeholder={{i18n "admin.ingenic.documentation.series_name"}} required />
                <input name="slug" value={{entry.slug}} placeholder={{i18n "admin.ingenic.documentation.series_slug"}} required />
                <select name="locale" required>
                  {{#each (this.localeOptions entry.locale) as |locale|}}
                    <option value={{locale.value}} selected={{eq locale.value entry.locale}}>
                      {{locale.name}}
                    </option>
                  {{/each}}
                </select>
                <label class="checkbox-label">
                  <input type="checkbox" name="published" checked={{entry.published}} />
                  <span>{{i18n "admin.ingenic.documentation.published"}}</span>
                </label>
                <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.save"}}</button>
                <button type="button" class="btn" disabled={{this.busy}} {{on "click" this.cancelProductEdit}}>{{i18n "admin.ingenic.documentation.cancel"}}</button>
              </form>
            {{/if}}

            <ul>
              {{#each entry.chips as |chip|}}
                <li class="ingenic-doc-manager__chip-item">
                  <div class="ingenic-doc-manager__chip-row">
                    <button
                      type="button"
                      class="ingenic-doc-manager__chip {{if (eq chip.id this.selectedChipId) 'is-selected'}}"
                      {{on "click" (fn this.selectChip chip)}}
                    >
                      {{chip.name}}
                    </button>
                    <span class="ingenic-doc-manager__tools">
                      <button type="button" title={{i18n "admin.ingenic.documentation.move_up"}} {{on "click" (fn this.moveProduct chip -1)}}>↑</button>
                      <button type="button" title={{i18n "admin.ingenic.documentation.move_down"}} {{on "click" (fn this.moveProduct chip 1)}}>↓</button>
                      <button type="button" title={{i18n "admin.ingenic.documentation.edit"}} {{on "click" (fn this.toggleProductEdit chip)}}>✎</button>
                      <button type="button" title={{i18n "admin.ingenic.documentation.delete"}} {{on "click" (fn this.destroyProduct chip)}}>×</button>
                    </span>
                  </div>

                  {{#if (eq chip.id this.editingProductId)}}
                    <form class="ingenic-admin-form ingenic-admin-form--inline ingenic-doc-manager__edit-form" {{on "submit" (fn this.saveProduct chip)}}>
                      <input name="name" value={{chip.name}} placeholder={{i18n "admin.ingenic.documentation.chip_name"}} required />
                      <input name="slug" value={{chip.slug}} placeholder={{i18n "admin.ingenic.documentation.chip_slug"}} required />
                      <select name="locale" required>
                        {{#each (this.localeOptions chip.locale) as |locale|}}
                          <option value={{locale.value}} selected={{eq locale.value chip.locale}}>
                            {{locale.name}}
                          </option>
                        {{/each}}
                      </select>
                      <label class="checkbox-label">
                        <input type="checkbox" name="published" checked={{chip.published}} />
                        <span>{{i18n "admin.ingenic.documentation.published"}}</span>
                      </label>
                      <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.save"}}</button>
                      <button type="button" class="btn" disabled={{this.busy}} {{on "click" this.cancelProductEdit}}>{{i18n "admin.ingenic.documentation.cancel"}}</button>
                    </form>
                  {{/if}}
                </li>
              {{/each}}
            </ul>

            <form class="ingenic-admin-form ingenic-admin-form--inline" {{on "submit" this.createChip}}>
              <input type="hidden" name="parent_id" value={{entry.id}} />
              <input name="name" placeholder={{i18n "admin.ingenic.documentation.chip_name"}} required />
              <input name="slug" placeholder={{i18n "admin.ingenic.documentation.chip_slug"}} required />
              <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.documentation.add_chip"}}</button>
            </form>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.documentation.empty"}}</p>
        {{/each}}
      </aside>

      <section class="ingenic-doc-manager__workspace">
        {{#if this.selectedChip}}
          <form class="ingenic-admin-form ingenic-admin-form--inline" {{on "submit" this.createVersion}}>
            <input name="label" placeholder={{i18n "admin.ingenic.documentation.version_label"}} required />
            <input name="slug" placeholder={{i18n "admin.ingenic.documentation.version_slug"}} required />
            <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.documentation.add_version"}}</button>
          </form>

          <div class="ingenic-doc-manager__versions">
            {{#each this.versions as |version|}}
              <div class="ingenic-doc-manager__version-item">
                <span class="ingenic-doc-manager__version-row">
                  <button
                    type="button"
                    class="ingenic-doc-manager__version {{if (eq version.id this.selectedVersionId) 'is-selected'}}"
                    {{on "click" (fn this.selectVersion version)}}
                  >
                    {{version.label}}
                    {{#if version.deprecated}}<span class="ingenic-doc-manager__badge">{{i18n "admin.ingenic.documentation.deprecated"}}</span>{{/if}}
                  </button>
                  <span class="ingenic-doc-manager__tools">
                    <button type="button" title={{i18n "admin.ingenic.documentation.move_up"}} {{on "click" (fn this.moveVersion version -1)}}>↑</button>
                    <button type="button" title={{i18n "admin.ingenic.documentation.move_down"}} {{on "click" (fn this.moveVersion version 1)}}>↓</button>
                    <button type="button" title={{i18n "admin.ingenic.documentation.edit"}} {{on "click" (fn this.toggleVersionEdit version)}}>✎</button>
                    <button type="button" title={{i18n "admin.ingenic.documentation.delete"}} {{on "click" (fn this.destroyVersion version)}}>×</button>
                  </span>
                </span>

                {{#if (eq version.id this.editingVersionId)}}
                  <form class="ingenic-admin-form ingenic-admin-form--inline ingenic-doc-manager__edit-form" {{on "submit" (fn this.saveVersion version)}}>
                    <input name="label" value={{version.label}} placeholder={{i18n "admin.ingenic.documentation.version_label"}} required />
                    <input name="slug" value={{version.slug}} placeholder={{i18n "admin.ingenic.documentation.version_slug"}} required />
                    <select name="locale" required>
                      {{#each (this.localeOptions version.locale) as |locale|}}
                        <option value={{locale.value}} selected={{eq locale.value version.locale}}>
                          {{locale.name}}
                        </option>
                      {{/each}}
                    </select>
                    <label>
                      <span>{{i18n "admin.ingenic.documentation.released_on"}}</span>
                      <input type="date" name="released_on" value={{version.released_on}} />
                    </label>
                    <label class="checkbox-label">
                      <input type="checkbox" name="deprecated" checked={{version.deprecated}} />
                      <span>{{i18n "admin.ingenic.documentation.deprecated"}}</span>
                    </label>
                    <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.save"}}</button>
                    <button type="button" class="btn" disabled={{this.busy}} {{on "click" this.cancelVersionEdit}}>{{i18n "admin.ingenic.documentation.cancel"}}</button>
                  </form>
                {{/if}}
              </div>
            {{/each}}
          </div>

          {{#if this.selectedVersion}}
            <label class="ingenic-doc-manager__latest">
              <input
                type="checkbox"
                checked={{this.selectedVersion.latest}}
                disabled={{this.busy}}
                {{on "change" this.toggleLatest}}
              />
              <span>{{i18n "admin.ingenic.documentation.latest"}}</span>
            </label>

            <form class="ingenic-admin-form ingenic-admin-form--inline" {{on "submit" this.importPages}}>
              <input type="file" name="files[]" accept=".md,.markdown,.txt,.docx" multiple required />
              <button type="submit" disabled={{this.busy}}>
                {{i18n "admin.ingenic.documentation.import_action"}}
              </button>
            </form>
            <p class="ingenic-admin-note">
              {{i18n "admin.ingenic.documentation.import_hint"}}
            </p>
            {{#if this.importMessage}}
              <p class="ingenic-admin-note">{{this.importMessage}}</p>
            {{/if}}

            <div class="ingenic-doc-manager__columns">
              <IngenicDocPageTree
                @pages={{this.pages}}
                @selectedSlug={{this.selectedPageSlug}}
                @onSelect={{this.selectPage}}
                @onMove={{this.movePage}}
              />

              <div class="ingenic-doc-manager__editor">
                {{#if this.selectedPage}}
                  <IngenicDocPageForm
                    @page={{this.selectedPage}}
                    @pages={{this.pages}}
                    @locales={{@locales}}
                    @busy={{this.busy}}
                    @onSave={{this.savePage}}
                    @onOverride={{this.overridePage}}
                    @onRevert={{this.revertPage}}
                    @onDestroy={{this.destroyPage}}
                  />
                {{else}}
                  <form class="ingenic-admin-form" {{on "submit" this.createPage}}>
                    <label>
                      <span>{{i18n "admin.ingenic.documentation.page_title"}}</span>
                      <input name="title" required />
                    </label>
                    <label>
                      <span>{{i18n "admin.ingenic.documentation.page_kind"}}</span>
                      <select name="kind">
                        <option value="page">{{i18n "admin.ingenic.documentation.kind_page"}}</option>
                        <option value="folder">{{i18n "admin.ingenic.documentation.kind_folder"}}</option>
                      </select>
                    </label>
                    <label>
                      <span>{{i18n "admin.ingenic.documentation.page_slug"}}</span>
                      <input name="slug" required />
                    </label>
                    <label>
                      <span>{{i18n "admin.ingenic.documentation.parent_page"}}</span>
                      <select name="parent_id">
                        <option value="">{{i18n "admin.ingenic.documentation.parent_none"}}</option>
                        {{#each this.pages as |page|}}
                          <option value={{page.id}}>
                            {{#if (eq page.kind "folder")}}📁 {{/if}}{{page.title}}
                          </option>
                        {{/each}}
                      </select>
                    </label>
                    <p class="ingenic-admin-note">
                      {{i18n "admin.ingenic.documentation.folder_hint"}}
                    </p>
                    <button type="submit" disabled={{this.busy}}>
                      {{i18n "admin.ingenic.documentation.add_entry"}}
                    </button>
                  </form>
                {{/if}}
              </div>
            </div>
          {{/if}}
        {{else}}
          <p>{{i18n "admin.ingenic.documentation.pick_chip"}}</p>
        {{/if}}
      </section>
    </div>
  </template>
}
