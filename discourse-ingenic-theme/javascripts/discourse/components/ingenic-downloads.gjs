import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

/**
 * Download centre. Filter values are derived from the resource data returned by
 * the plugin, so a new product or version shows up in the filters as soon as it
 * is added — no theme change required.
 */
export default class IngenicDownloads extends Component {
  @tracked downloads = [];
  @tracked filters = { products: [], kinds: [], versions: [], platforms: [] };
  @tracked selected = { product: "", kind: "", version: "", platform: "" };
  @tracked loading = true;

  @action
  async load() {
    await this.#fetch();
  }

  @action
  async selectProduct(event) {
    await this.#applyFilter("product", event.target.value);
  }

  @action
  async selectKind(event) {
    await this.#applyFilter("kind", event.target.value);
  }

  @action
  async selectVersion(event) {
    await this.#applyFilter("version", event.target.value);
  }

  @action
  async selectPlatform(event) {
    await this.#applyFilter("platform", event.target.value);
  }

  async #applyFilter(key, value) {
    this.selected = { ...this.selected, [key]: value };
    await this.#fetch();
  }

  async #fetch() {
    this.loading = true;

    const params = new URLSearchParams();
    Object.entries(this.selected).forEach(([key, value]) => {
      if (value) {
        params.set(key, value);
      }
    });

    const query = params.toString();
    const url = getURL("/ingenic/downloads");

    try {
      const response = await fetch(query ? `${url}?${query}` : url, {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.downloads = payload.downloads ?? [];

        // Filter options always come from the unfiltered response so the user
        // can widen the selection again after narrowing it.
        if (!query) {
          this.filters = payload.filters ?? this.filters;
        }
      }
    } catch {
      this.downloads = [];
    } finally {
      this.loading = false;
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <h1>{{i18n (themePrefix "ingenic.downloads.title")}}</h1>
      </header>

      <div class="ingenic-downloads__filters">
        <select {{on "change" this.selectProduct}}>
          <option value="">{{i18n (themePrefix "ingenic.downloads.all_products")}}</option>
          {{#each this.filters.products as |product|}}
            <option value={{product}}>{{product}}</option>
          {{/each}}
        </select>

        <select {{on "change" this.selectKind}}>
          <option value="">{{i18n (themePrefix "ingenic.downloads.all_types")}}</option>
          {{#each this.filters.kinds as |kind|}}
            <option value={{kind}}>{{kind}}</option>
          {{/each}}
        </select>

        <select {{on "change" this.selectVersion}}>
          <option value="">{{i18n (themePrefix "ingenic.downloads.all_versions")}}</option>
          {{#each this.filters.versions as |version|}}
            <option value={{version}}>{{version}}</option>
          {{/each}}
        </select>

        <select {{on "change" this.selectPlatform}}>
          <option value="">{{i18n (themePrefix "ingenic.downloads.all_platforms")}}</option>
          {{#each this.filters.platforms as |platform|}}
            <option value={{platform}}>{{platform}}</option>
          {{/each}}
        </select>
      </div>

      {{#if this.downloads.length}}
        <div class="ingenic-card-grid">
          {{#each this.downloads as |download|}}
            <article class="ingenic-card">
              <div class="ingenic-card__title">{{download.name}}</div>
              <div class="ingenic-card__meta">
                {{download.kind}}
                {{#if download.version}}· {{download.version}}{{/if}}
                {{#if download.platform}}· {{download.platform}}{{/if}}
              </div>

              {{#if download.description}}
                <p>{{download.description}}</p>
              {{/if}}

              <dl class="ingenic-card__meta">
                {{#if download.file_size}}
                  <dt>{{i18n (themePrefix "ingenic.downloads.size")}}</dt>
                  <dd>{{download.file_size}}</dd>
                {{/if}}
                {{#if download.released_on}}
                  <dt>{{i18n (themePrefix "ingenic.downloads.released")}}</dt>
                  <dd>{{download.released_on}}</dd>
                {{/if}}
                {{#if download.sha256}}
                  <dt>{{i18n (themePrefix "ingenic.downloads.checksum")}}</dt>
                  <dd><code>{{download.sha256}}</code></dd>
                {{/if}}
              </dl>

              <div class="ingenic-card__actions">
                <a
                  class="btn btn-primary"
                  href={{download.file_url}}
                  target={{if download.external "_blank" "_self"}}
                  rel={{if download.external "noopener noreferrer" ""}}
                >
                  {{i18n (themePrefix "ingenic.downloads.download")}}
                </a>
              </div>
            </article>
          {{/each}}
        </div>
      {{else if this.loading}}
        <p class="ingenic-card__meta">…</p>
      {{else}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.downloads.empty")}}</p>
      {{/if}}
    </section>
  </template>
}
