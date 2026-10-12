import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

/**
 * Development board catalogue.
 *
 * Board application is an outbound link owned by the Ingenic team, so this page
 * never posts to the forum itself — it only routes visitors to the right place.
 */
export default class IngenicBoards extends Component {
  @tracked boards = [];
  @tracked loading = true;

  @action
  async load() {
    this.loading = true;

    try {
      const response = await fetch(getURL("/ingenic/boards"), {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.boards = payload.boards ?? [];
      }
    } catch {
      this.boards = [];
    } finally {
      this.loading = false;
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <h1>{{i18n (themePrefix "ingenic.boards.title")}}</h1>
      </header>

      {{#if this.boards.length}}
        <div class="ingenic-card-grid">
          {{#each this.boards as |board|}}
            <article class="ingenic-card">
              {{#if board.image_url}}
                <img
                  class="ingenic-card__image"
                  src={{board.image_url}}
                  alt={{board.name}}
                  loading="lazy"
                />
              {{/if}}
              <div class="ingenic-card__title">{{board.name}}</div>
              {{#if board.chip}}
                <div class="ingenic-card__meta">{{board.chip}}</div>
              {{/if}}
              {{#if board.description}}
                <p>{{board.description}}</p>
              {{/if}}
              <div class="ingenic-card__actions">
                {{#if board.application_url}}
                  <a
                    class="btn btn-primary"
                    href={{board.application_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{i18n (themePrefix "ingenic.boards.apply")}}
                  </a>
                {{/if}}
                {{#if board.documentation_url}}
                  <a
                    class="btn"
                    href={{board.documentation_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{i18n (themePrefix "ingenic.boards.documentation")}}
                  </a>
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      {{else if this.loading}}
        <p class="ingenic-card__meta">…</p>
      {{else}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.boards.empty")}}</p>
      {{/if}}
    </section>
  </template>
}
