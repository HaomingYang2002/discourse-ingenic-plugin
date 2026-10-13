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
    await this.#create(event, "documentation/products", {
      kind: "chip",
      parent_id: this.#seriesIdForSelectedChip(),
    });
  }

  @action
  async createVersion(event) {
    await this.#create(event, "documentation/versions", { product_id: this.selectedChipId });
  }

  @action
  async createPage(event) {
    const values = Object.fromEntries(new FormData(event.target));
    await this.#create(event, "documentation/pages", {
      version_id: this.selectedVersionId,
      parent_id: values.parent_slug ? this.#idForSlug(values.parent_slug) : null,
    });
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

  #seriesIdForSelectedChip() {
    return this.series.find((entry) => (entry.chips ?? []).some((chip) => chip.id === this.selectedChipId))?.id;
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
            <h4>{{entry.name}}</h4>
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
                </li>
              {{/each}}
            </ul>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.documentation.empty"}}</p>
        {{/each}}

        {{#if this.selectedChip}}
          <form class="ingenic-admin-form ingenic-admin-form--inline" {{on "submit" this.createChip}}>
            <input name="name" placeholder={{i18n "admin.ingenic.documentation.chip_name"}} required />
            <input name="slug" placeholder={{i18n "admin.ingenic.documentation.chip_slug"}} required />
            <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.documentation.add_chip"}}</button>
          </form>
        {{/if}}
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
              <button
                type="button"
                class="ingenic-doc-manager__version {{if (eq version.id this.selectedVersionId) 'is-selected'}}"
                {{on "click" (fn this.selectVersion version)}}
              >
                {{version.label}}
              </button>
            {{/each}}
          </div>

          {{#if this.selectedVersion}}
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
