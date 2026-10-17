import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";

/**
 * A column of topics for the front page.
 *
 * The latest block and the hot block are the same list with a different feed:
 * "what was said last" and "what people kept reading" differ in the filter and
 * in nothing a reader sees, so they share one component rather than two that
 * drift. A category block is a different shape — it is pinned to an editor's
 * choice of section — and stays in its own component.
 *
 * The counts and the last-post time are what meta.discourse.org puts beside a
 * title, and they are the reason a list of titles is worth more than a list:
 * a reader can tell a thread with forty replies from one nobody answered.
 */
const FEEDS = {
  latest: "latest",
  // Discourse's own "hot" feed. `top/weekly` is a 301 a fetch does not follow,
  // and a weekly window is empty on a forum whose topics have no views yet —
  // which is every new install on the day it opens.
  hot: "hot",
};

export default class IngenicBlockFeed extends Component {
  @service site;
  @service store;

  @tracked topics = [];
  @tracked loaded = false;

  get type() {
    return this.args.block?.type;
  }

  get isHot() {
    return this.type === "hot";
  }

  get limit() {
    return this.args.block?.limit || (this.isHot ? 5 : 8);
  }

  get title() {
    return (
      this.args.block?.title ||
      i18n(
        themePrefix(
          this.isHot ? "ingenic.home.topics.hot" : "ingenic.home.topics.latest",
        ),
      )
    );
  }

  // Topic keeps the payload's own names — `category_id`, `posts_count`,
  // `last_posted_at` — rather than camel-casing them. Reading the camelCase
  // spelling here is what left the reply count undefined and the date blank.
  get categoryFor() {
    return (topic) =>
      this.site.categories?.find(
        (category) => category.id === topic.category_id,
      );
  }

  get rows() {
    const categoryFor = this.categoryFor;

    return this.topics.slice(0, this.limit).map((topic, index) => ({
      id: topic.id,
      rank: index + 1,
      title: topic.title,
      url: topic.url,
      postsCount: topic.posts_count,
      views: topic.views,
      lastPostedAt: topic.last_posted_at,
      category: categoryFor(topic),
    }));
  }

  @action
  async load() {
    if (this.loaded) {
      return;
    }

    this.loaded = true;

    try {
      const result = await this.store.findFiltered("topicList", {
        filter: FEEDS[this.type] || FEEDS.latest,
      });

      this.topics = result.topics ?? [];
    } catch {
      this.topics = [];
    }
  }

  <template>
    <section
      class="ingenic-section ingenic-feed {{if this.isHot 'ingenic-feed--hot'}}"
      {{didInsert this.load}}
    >
      <header class="ingenic-section__header">
        <h2>{{this.title}}</h2>
      </header>

      {{#if this.rows.length}}
        <ol class="ingenic-feed__list">
          {{#each this.rows as |row|}}
            <li class="ingenic-feed__item">
              <div class="ingenic-feed__headline">
                {{#if this.isHot}}
                  <span class="ingenic-feed__rank" aria-hidden="true">{{row.rank}}</span>
                {{/if}}
                <a class="ingenic-feed__title" href={{row.url}}>{{row.title}}</a>
              </div>

              <div class="ingenic-feed__meta">
                {{#if row.category}}
                  <span class="ingenic-feed__category">
                    <span
                      class="ingenic-feed__dot"
                      style="background-color: #{{row.category.color}}"
                      aria-hidden="true"
                    ></span>
                    {{row.category.name}}
                  </span>
                {{/if}}
                <span class="ingenic-feed__count">
                  {{i18n (themePrefix "ingenic.home.topics.replies") count=row.postsCount}}
                </span>
                <span class="ingenic-feed__count">
                  {{i18n (themePrefix "ingenic.home.topics.views") count=row.views}}
                </span>
                <span class="ingenic-feed__time">
                  {{dFormatDate row.lastPostedAt leaveAgo="true"}}
                </span>
              </div>
            </li>
          {{/each}}
        </ol>
      {{else}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.empty")}}
        </p>
      {{/if}}
    </section>
  </template>
}
