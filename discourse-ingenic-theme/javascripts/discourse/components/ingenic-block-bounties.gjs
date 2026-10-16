import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/bounties";

/**
 * Homepage block: the richest standing 高分悬赏, with a way through to the board.
 *
 * It draws nothing at all when nothing is on offer. That is what lets it be one
 * of the default blocks: a front page that says "no bounties yet" in a panel of
 * its own is worse than a front page that does not mention them until there are
 * some — and the day the first one is opened, the panel appears on its own.
 *
 * Because it draws nothing until it knows whether there is anything to draw, it
 * cannot wait for `didInsert` to be told to look: an element that is not
 * rendered never gets the chance. So it asks in the constructor, which is the
 * one hook that runs either way.
 */
export default class IngenicBlockBounties extends Component {
  @service site;

  @tracked bounties = [];
  @tracked loaded = false;

  constructor() {
    super(...arguments);
    this.load();
  }

  get limit() {
    return this.args.block?.limit || 5;
  }

  get title() {
    return this.args.block?.title || i18n(themePrefix("ingenic.bounties.title"));
  }

  get rows() {
    return this.bounties.slice(0, this.limit).map((bounty) => {
      const category = this.site.categories?.find(
        (c) => c.id === bounty.topic.category_id
      );

      return {
        ...bounty,
        url: bounty.topic.url,
        title: bounty.topic.title,
        category,
      };
    });
  }

  get boardPath() {
    return getURL("/ingenic/bounties");
  }

  @action
  async load() {
    if (this.loaded) {
      return;
    }

    this.loaded = true;

    try {
      const response = await fetch(`${getURL(ENDPOINT)}?limit=${this.limit}`, {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.bounties = payload.bounties ?? [];
      }
    } catch {
      this.bounties = [];
    }
  }

  <template>
    {{#if this.rows.length}}
      <section class="ingenic-section ingenic-bounties">
        <header class="ingenic-section__header">
          <h2><a href={{this.boardPath}}>{{this.title}}</a></h2>
          <a class="ingenic-section__more" href={{this.boardPath}}>
            {{i18n (themePrefix "ingenic.bounties.all")}}
          </a>
        </header>

        <ul class="ingenic-bounty-list">
          {{#each this.rows as |row|}}
            <li class="ingenic-bounty-list__item">
              <span class="ingenic-bounty-list__points">
                {{dIcon "gift"}}
                {{row.points}}
              </span>

              <div class="ingenic-bounty-list__body">
                <a class="ingenic-bounty-list__title" href={{row.url}}>{{row.title}}</a>

                {{#if row.category}}
                  <span
                    class="ingenic-bounty-list__category"
                    style="border-color: #{{row.category.color}}"
                  >
                    {{row.category.name}}
                  </span>
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ul>
      </section>
    {{/if}}
  </template>
}
