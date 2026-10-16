import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * The forum's sections, as the home page's way into the forum.
 *
 * A front page is a table of contents rather than a feed, so this draws a
 * handful of sections — the ones an editor named, or the busiest ones — and one
 * entry to all of them. A reader whose section is not on the front page needs to
 * see that there are more, or they will conclude the forum has nothing for them.
 *
 * The categories come from `site.categories`, which holds exactly what this
 * viewer is allowed to see and carries the counts the category page shows, so
 * nothing here can reveal a section to somebody who cannot open it.
 */
export default class IngenicBlockCategories extends Component {
  @service site;

  get configured() {
    return this.args.block?.categories ?? [];
  }

  get limit() {
    return this.args.block?.limit || 8;
  }

  get topLevel() {
    return this.site.categories.filter(
      (category) => !category.parent_category_id
    );
  }

  // A named list keeps the order it was written in, which is how an editor
  // decides what the front page leads with. Without one, the busiest sections
  // come first — the closest thing to "hot" that needs no maintenance.
  get sections() {
    if (this.configured.length) {
      return this.configured
        .map((slug) => this.topLevel.find((category) => category.slug === slug))
        .filter(Boolean);
    }

    return this.site.categoriesByCount
      .filter((category) => !category.parent_category_id)
      .slice(0, this.limit);
  }

  get title() {
    return (
      this.args.block?.title || i18n(themePrefix("ingenic.home.sections.title"))
    );
  }

  get showAll() {
    return this.args.block?.show_all !== false;
  }

  <template>
    <section class="ingenic-section">
      <header class="ingenic-section__header">
        <h2>{{this.title}}</h2>

        {{#if this.showAll}}
          <a class="ingenic-section__more" href="/categories">
            {{i18n (themePrefix "ingenic.home.sections.all")}}
          </a>
        {{/if}}
      </header>

      {{#if this.sections.length}}
        <div class="ingenic-sections">
          {{#each this.sections as |section|}}
            <a
              class="ingenic-sections__card"
              href={{section.url}}
              style="border-top-color: #{{section.color}}"
            >
              <span class="ingenic-sections__name">
                {{#if section.icon}}
                  {{dIcon section.icon}}
                {{/if}}
                {{section.name}}
              </span>

              {{#if section.description_text}}
                <span class="ingenic-sections__description">{{section.description_text}}</span>
              {{/if}}

              <span class="ingenic-sections__count">
                {{i18n
                  (themePrefix "ingenic.home.sections.topic_count")
                  count=section.topic_count
                }}
              </span>
            </a>
          {{/each}}
        </div>
      {{else}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.sections.empty")}}
        </p>
      {{/if}}
    </section>
  </template>
}
