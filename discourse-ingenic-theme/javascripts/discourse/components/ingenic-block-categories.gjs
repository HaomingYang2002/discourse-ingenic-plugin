import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * The forum's sections, as the home page's way into the forum.
 *
 * Three sources, in this order: the cards an administrator wrote on Site
 * content → Home cards; the category slugs an editor put on this block; and,
 * with neither, three cards that fit this forum out of the box — technical
 * discussions, the documentation reader, and announcements. The documentation
 * card is why a card can carry its own destination: the reader is not a
 * category, and inventing one for it would make the forum claim a section it
 * does not have.
 *
 * A card naming a category borrows that category's name, colour, icon,
 * description and topic count from `site.categories`, so what the front page
 * says about a section is what its page says.
 */
export default class IngenicBlockCategories extends Component {
  @service site;

  get configured() {
    return this.args.block?.categories ?? [];
  }

  get limit() {
    return this.args.block?.limit || 3;
  }

  get topLevel() {
    return this.site.categories.filter(
      (category) => !category.parent_category_id
    );
  }

  get cards() {
    const written = this.site.ingenic_section_cards ?? [];

    if (written.length) {
      return written.map((card) => this.cardFromConfig(card)).filter(Boolean);
    }

    if (this.configured.length) {
      return this.configured
        .map((slug) => this.cardFromCategory(this.topLevel.find((c) => c.slug === slug)))
        .filter(Boolean);
    }

    return this.defaultCards;
  }

  get defaultCards() {
    const wanted = ["technical-discussions", "official-announcements"];
    const found = wanted
      .map((slug) => this.topLevel.find((category) => category.slug === slug))
      .filter(Boolean);

    const docs = {
      key: "docs",
      href: "/ingenic/docs",
      label: i18n(themePrefix("ingenic.nav.docs")),
      description: i18n(themePrefix("ingenic.home.sections.docs_hint")),
      icon: "book",
      count: null,
      style: "--ingenic-category: var(--tertiary)",
    };

    // Documentation sits between the two forum sections, which is where a
    // developer arriving with a chip question looks before asking it.
    return [
      found[0] && this.cardFromCategory(found[0]),
      docs,
      found[1] && this.cardFromCategory(found[1]),
    ].filter(Boolean);
  }

  get showAll() {
    return this.args.block?.show_all !== false;
  }

  cardFromConfig(card) {
    if (card.category) {
      return this.cardFromCategory(
        this.site.categories.find((category) => category.slug === card.category),
        card
      );
    }

    return {
      key: `card-${card.id}`,
      href: card.href,
      label: card.label,
      description: card.description,
      icon: card.icon,
      image_url: card.image_url,
      count: null,
      style: card.color ? `--ingenic-category: #${card.color.replace(/^#/, "")}` : null,
    };
  }

  cardFromCategory(category, overlay = {}) {
    if (!category) {
      return null;
    }

    const color = overlay.color || category.color;

    return {
      key: `category-${category.id}`,
      href: category.url,
      label: overlay.label || category.name,
      description: overlay.description || category.description_text,
      icon: overlay.icon || category.icon,
      image_url: overlay.image_url,
      count: category.topic_count,
      style: color ? `--ingenic-category: #${color.replace(/^#/, "")}` : null,
    };
  }

  <template>
    <section class="ingenic-section ingenic-section--sections">
      {{#if this.cards.length}}
        <div class="ingenic-sections">
          {{#each this.cards as |card|}}
            <a
              class="ingenic-sections__card"
              href={{card.href}}
              style={{card.style}}
            >
              <span class="ingenic-sections__icon" aria-hidden="true">
                {{#if card.image_url}}
                  <img
                    class="ingenic-sections__image"
                    src={{card.image_url}}
                    alt=""
                    loading="lazy"
                  />
                {{else if card.icon}}
                  {{dIcon card.icon}}
                {{/if}}
              </span>

              <span class="ingenic-sections__text">
                <span class="ingenic-sections__name">{{card.label}}</span>

                {{#if card.description}}
                  <span class="ingenic-sections__description">{{card.description}}</span>
                {{/if}}

                {{#if card.count}}
                  <span class="ingenic-sections__count">
                    {{i18n
                      (themePrefix "ingenic.home.sections.topic_count")
                      count=card.count
                    }}
                  </span>
                {{/if}}
              </span>
            </a>
          {{/each}}
        </div>
      {{else}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.sections.empty")}}
        </p>
      {{/if}}

      {{#if this.showAll}}
        <a class="ingenic-sections__all" href="/categories">
          {{i18n (themePrefix "ingenic.home.sections.all")}}
        </a>
      {{/if}}
    </section>
  </template>
}
