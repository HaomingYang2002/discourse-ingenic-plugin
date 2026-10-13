import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { i18n } from "discourse-i18n";
import { loadSiteContent } from "../ingenic/site-content";

/**
 * The promotion slots on the homepage.
 *
 * The slots are a list the Ingenic team edits, each with an optional window, so
 * a campaign can be written once and taken down by its own dates. Nothing here
 * knows what a campaign is: a slot whose window has passed simply does not come
 * back from the endpoint.
 *
 * Drawn as a row of panels rather than a carousel: a carousel hides two thirds
 * of the team's work behind a control most visitors never touch, and three slots
 * that fit on the page say more than three that take turns.
 *
 * The picture is an element behind the text rather than a CSS background, so
 * nothing an editor types is ever parsed as style.
 */
export default class IngenicPromotions extends Component {
  @tracked promotions = [];

  // Loaded from here rather than from a `did-insert` on the section, because the
  // section is what the load decides to draw: a modifier inside the conditional
  // would be waiting for the element that is waiting for the modifier.
  //
  // The component can be built more than once per page — a route change rebuilds
  // the homepage — and the request itself is shared, so a second build costs
  // nothing and shows the slots immediately.
  constructor(owner, args) {
    super(owner, args);
    this.#load();
  }

  get title() {
    return this.args.block?.title || i18n(themePrefix("ingenic.promotions.title"));
  }

  get slots() {
    return this.promotions.map((promotion) => ({
      ...promotion,
      target: promotion.external ? "_blank" : "_self",
      rel: promotion.external ? "noopener noreferrer" : null,
    }));
  }

  async #load() {
    const payload = await loadSiteContent();
    this.promotions = payload.promotions ?? [];
  }

  <template>
    {{#if this.promotions.length}}
      <section class="ingenic-section ingenic-promotions">
        <header class="ingenic-section__header">
          <h2>{{this.title}}</h2>
        </header>

        <div class="ingenic-promotions__grid">
          {{#each this.slots as |slot|}}
            <article class="ingenic-promotion">
              {{#if slot.image_url}}
                <img
                  class="ingenic-promotion__image"
                  src={{slot.image_url}}
                  alt=""
                  loading="lazy"
                />
              {{/if}}

              <div class="ingenic-promotion__content">
                {{#if slot.corner_label}}
                  <span class="ingenic-promotion__corner">{{slot.corner_label}}</span>
                {{/if}}

                <h3 class="ingenic-promotion__title">{{slot.title}}</h3>

                {{#if slot.description}}
                  <p class="ingenic-promotion__body">{{slot.description}}</p>
                {{/if}}

                {{#if slot.button_label}}
                  {{#if slot.button_href}}
                    <a
                      class="btn btn-primary"
                      href={{slot.button_href}}
                      target={{slot.target}}
                      rel={{slot.rel}}
                    >
                      {{slot.button_label}}
                    </a>
                  {{else}}
                    <span class="ingenic-promotion__label">{{slot.button_label}}</span>
                  {{/if}}
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      </section>
    {{/if}}
  </template>
}
