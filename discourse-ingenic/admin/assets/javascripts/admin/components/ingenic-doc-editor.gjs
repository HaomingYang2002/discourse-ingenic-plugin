import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

/**
 * Version and page authoring for one documentation product.
 *
 * Versions are created against the product; pages are created against the
 * selected version. Both go through the plugin's own admin endpoints, which
 * re-check the caller's scope server-side, so this component only decides what
 * to show — never what is allowed.
 */
export default class IngenicDocEditor extends Component {
  @tracked versions = this.args.product.versions;
  @tracked selectedVersionId = this.args.product.versions[0]?.id ?? null;
  @tracked busy = false;
  @tracked error = null;

  get selectedVersion() {
    return this.versions.find((version) => version.id === this.selectedVersionId);
  }

  get pages() {
    return this.selectedVersion?.pages ?? [];
  }

  @action
  selectVersion(event) {
    this.selectedVersionId = Number(event.target.value);
  }

  @action
  async createVersion(event) {
    event.preventDefault();
    await this.#submit(event, "documentation/versions", { product_id: this.args.product.id }, (payload) => {
      this.versions = [...this.versions, { ...payload.version, pages: [] }];
      this.selectedVersionId = payload.version.id;
    });
  }

  @action
  async createPage(event) {
    event.preventDefault();
    await this.#submit(event, "documentation/pages", { version_id: this.selectedVersionId }, (payload) => {
      const version = this.selectedVersion;
      version.pages = [...(version.pages ?? []), payload.page];
      this.versions = [...this.versions];
    });
  }

  @action
  async removePage(page, event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;

    try {
      await ajax(`/admin/plugins/discourse-ingenic/documentation/pages/${page.id}`, { type: "DELETE" });
      const version = this.selectedVersion;
      version.pages = version.pages.filter((item) => item.id !== page.id);
      this.versions = [...this.versions];
    } catch {
      this.error = i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  async #submit(event, endpoint, extra, onSuccess) {
    this.busy = true;
    this.error = null;

    try {
      const payload = await ajax(`/admin/plugins/discourse-ingenic/${endpoint}`, {
        type: "POST",
        data: { ...Object.fromEntries(new FormData(event.target)), ...extra },
      });
      event.target.reset();
      onSuccess(payload);
    } catch (requestError) {
      this.error =
        requestError.jqXHR?.responseJSON?.errors?.join(", ") || i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{#if this.error}}<p class="admin-config-area__message">{{this.error}}</p>{{/if}}

    <form class="ingenic-admin-form" {{on "submit" this.createVersion}}>
      <label>
        <span>{{i18n "admin.ingenic.documentation.version_slug"}}</span>
        <input name="slug" required />
      </label>
      <label>
        <span>{{i18n "admin.ingenic.documentation.version_label"}}</span>
        <input name="label" required />
      </label>
      <label>
        <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
        <input name="locale" value="en" required />
      </label>
      <label class="checkbox-label">
        <input type="checkbox" name="latest" />
        <span>{{i18n "admin.ingenic.documentation.latest"}}</span>
      </label>
      <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.documentation.add_version"}}</button>
    </form>

    {{#if this.versions.length}}
      <label class="ingenic-admin-form__select">
        <span>{{i18n "admin.ingenic.documentation.versions"}}</span>
        <select {{on "change" this.selectVersion}}>
          {{#each this.versions as |version|}}
            <option value={{version.id}} selected={{eq version.id this.selectedVersionId}}>
              {{version.label}} ({{version.locale}})
            </option>
          {{/each}}
        </select>
      </label>

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
          <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
          <input name="locale" value="en" required />
        </label>
        <label class="ingenic-admin-form__wide">
          <span>{{i18n "admin.ingenic.documentation.page_body"}}</span>
          <textarea name="body" rows="6"></textarea>
        </label>
        <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.documentation.add_page"}}</button>
      </form>

      <div class="admin-config-list">
        {{#each this.pages as |page|}}
          <section class="admin-config-list__row">
            <div>
              <strong>{{page.title}}</strong>
              <div class="admin-config-list__meta">{{page.slug}} · {{page.locale}}</div>
            </div>
            <button class="btn btn-danger" type="button" {{on "click" (fn this.removePage page)}}>
              {{i18n "admin.ingenic.revoke"}}
            </button>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.documentation.no_pages"}}</p>
        {{/each}}
      </div>
    {{/if}}
  </template>
}
