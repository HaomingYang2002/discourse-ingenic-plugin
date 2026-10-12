import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { i18n } from "discourse-i18n";

/**
 * Renders a list of topics for a category-driven homepage block.
 *
 * The block is skipped entirely when no category is configured, which keeps the
 * homepage usable before categories are finalised.
 */
export default class IngenicBlockTopics extends Component {
  @service router;
  @service store;
  @tracked topics = [];
  @tracked loaded = false;

  get categorySlug() {
    return this.args.block?.category;
  }

  get limit() {
    return this.args.block?.limit || 5;
  }

  get title() {
    return this.args.block?.title;
  }

  @action
  async load() {
    if (this.loaded || !this.categorySlug) {
      return;
    }

    this.loaded = true;

    try {
      const result = await this.store.findFiltered("topicList", {
        filter: `category/${this.categorySlug}/l/latest`,
      });

      this.topics = (result.topics ?? []).slice(0, this.limit);
    } catch {
      this.topics = [];
    }
  }

  @action
  open(topic, event) {
    event.preventDefault();
    this.router.transitionTo(topic.url);
  }

  <template>
    {{#if this.categorySlug}}
      <section class="ingenic-section" {{didInsert this.load}}>
        <header class="ingenic-section__header">
          <h2>{{this.title}}</h2>
        </header>

        {{#if this.topics.length}}
          <ul class="ingenic-topic-list">
            {{#each this.topics as |topic|}}
              <li class="ingenic-topic-list__item">
                <a
                  href={{topic.url}}
                  class="ingenic-topic-list__link"
                  {{on "click" (fn this.open topic)}}
                >
                  {{topic.title}}
                </a>
                <span class="ingenic-card__meta">{{topic.postsCount}}</span>
              </li>
            {{/each}}
          </ul>
        {{else}}
          <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.home.empty")}}</p>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
