import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

/**
 * Homepage block listing the most recent downloads.
 *
 * Shares the `/ingenic/downloads` endpoint with the full download centre so
 * both stay in sync with the plugin's resource data.
 */
export default class IngenicBlockDownloads extends Component {
  @tracked downloads = [];
  @tracked loaded = false;

  get limit() {
    return this.args.block?.limit || 6;
  }

  get title() {
    return this.args.block?.title || i18n(themePrefix("ingenic.downloads.title"));
  }

  @action
  async load() {
    if (this.loaded) {
      return;
    }

    this.loaded = true;

    try {
      const response = await fetch(getURL("/ingenic/downloads"), {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.downloads = (payload.downloads ?? []).slice(0, this.limit);
      }
    } catch {
      this.downloads = [];
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <h2><a href="/ingenic/downloads">{{this.title}}</a></h2>
      </header>

      {{#if this.downloads.length}}
        <div class="ingenic-card-grid">
          {{#each this.downloads as |download|}}
            <article class="ingenic-card">
              <div class="ingenic-card__title">{{download.name}}</div>
              <div class="ingenic-card__meta">
                {{#if download.category_name}}{{download.category_name}}{{/if}}
                {{#if download.version}}· {{download.version}}{{/if}}
              </div>
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
      {{else}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.home.empty")}}</p>
      {{/if}}
    </section>
  </template>
}
