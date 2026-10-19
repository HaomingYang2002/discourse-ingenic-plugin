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
  // two controls a typo in the label, or a version created against the wrong
  // chip, could only be fixed in the database.
  @action
  async renameVersion(version) {
    const label = window.prompt(
      i18n("admin.ingenic.documentation.rename_prompt"),
      version.label
    );

    if (!label || label.trim() === version.label) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, {
        type: "PUT",
        data: { label: label.trim() },
      });
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async destroyVersion(version) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_confirm"))) {
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
    const values = Object.fromEntries(new FormData(event.target));
    await this.#create(event, "documentation/pages", {
      version_id: this.selectedVersionId,
      parent_id: values.parent_slug ? this.#idForSlug(values.parent_slug) : null,
    });
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

  // Series and chips are the download centre's first two filter rows, so the
  // words a visitor picks from are edited here rather than in code. Renaming
  // uses the browser's own prompt: it is one field, and a modal with one field
  // is a form to learn for no gain.
  @action
  async renameProduct(record) {
    const name = window.prompt(
      i18n("admin.ingenic.documentation.rename_prompt"),
      record.name
    );

    if (!name || name.trim() === record.name) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "PUT",
        data: { name: name.trim() },
      });
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

  #idForSlug(slug) {
    return this.pages.find((page) => page.slug === slug)?.id ?? null;
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
          <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.create"}}</button>
        </form>

        {{#each this.series as |entry|}}
          <section class="ingenic-doc-manager__series">
            <h4>
              <span>{{entry.name}}</span>
              <span class="ingenic-doc-manager__tools">
                <button type="button" title={{i18n "admin.ingenic.documentation.move_up"}} {{on "click" (fn this.moveProduct entry -1)}}>↑</button>
                <button type="button" title={{i18n "admin.ingenic.documentation.move_down"}} {{on "click" (fn this.moveProduct entry 1)}}>↓</button>
                <button type="button" title={{i18n "admin.ingenic.documentation.rename"}} {{on "click" (fn this.renameProduct entry)}}>✎</button>
                <button type="button" title={{i18n "admin.ingenic.documentation.delete"}} {{on "click" (fn this.destroyProduct entry)}}>×</button>
              </span>
            </h4>
            <ul>
              {{#each entry.chips as |chip|}}
                <li>
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
                    <button type="button" title={{i18n "admin.ingenic.documentation.rename"}} {{on "click" (fn this.renameProduct chip)}}>✎</button>
                    <button type="button" title={{i18n "admin.ingenic.documentation.delete"}} {{on "click" (fn this.destroyProduct chip)}}>×</button>
                  </span>
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
              <span class="ingenic-doc-manager__version-row">
                <button
                  type="button"
                  class="ingenic-doc-manager__version {{if (eq version.id this.selectedVersionId) 'is-selected'}}"
                  {{on "click" (fn this.selectVersion version)}}
                >
                  {{version.label}}
                </button>
                <span class="ingenic-doc-manager__tools">
                  <button type="button" title={{i18n "admin.ingenic.documentation.rename"}} {{on "click" (fn this.renameVersion version)}}>✎</button>
                  <button type="button" title={{i18n "admin.ingenic.documentation.delete"}} {{on "click" (fn this.destroyVersion version)}}>×</button>
                </span>
              </span>
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
              />

              <div class="ingenic-doc-manager__editor">
                {{#if this.selectedPage}}
                  <IngenicDocPageForm
                    @page={{this.selectedPage}}
                    @pages={{this.pages}}
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
                      <span>{{i18n "admin.ingenic.documentation.page_slug"}}</span>
                      <input name="slug" required />
                    </label>
                    <label>
                      <span>{{i18n "admin.ingenic.documentation.parent_slug"}}</span>
                      <input name="parent_slug" />
                    </label>
                    <button type="submit" disabled={{this.busy}}>
                      {{i18n "admin.ingenic.documentation.add_page"}}
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
