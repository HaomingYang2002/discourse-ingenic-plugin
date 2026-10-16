import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/bounties";
// The controller caps this at fifty. Asking for the cap is the point of a board:
// the page is where someone comes to see everything on offer, so it does not
// pretend there is a shorter list than there is.
const LIMIT = 50;

/**
 * The bounty board: every standing 高分悬赏, richest first.
 *
 * The order is the whole of the page's design. A board sorted by time would be a
 * second "latest" list next to the forum's own; sorted by what is on offer, it
 * answers the question a reader actually arrives with — where is the work worth
 * answering — and it is the one ordering that the amount on each row explains.
 *
 * The rows are the topics, read through the guardian on the server, so a bounty
 * in a category this visitor cannot see is not on the page and not in the count.
 */
export default class IngenicBounties extends Component {
  @service site;

  @tracked bounties = [];
  @tracked available = true;
  @tracked expiryDays = 0;
  @tracked loading = true;

  get rows() {
    return this.bounties.map((bounty) => {
      const category = this.site.categories?.find(
        (c) => c.id === bounty.topic.category_id
      );

      return {
        ...bounty,
        url: bounty.topic.url,
        title: bounty.topic.title,
        asker: bounty.user?.username,
        category,
        closesIn: this.#closesIn(bounty.expires_at),
      };
    });
  }

  get pointsPath() {
    return getURL("/ingenic/points");
  }

  @action
  async load() {
    try {
      const response = await fetch(`${getURL(ENDPOINT)}?limit=${LIMIT}`, {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.bounties = payload.bounties ?? [];
        this.available = payload.available !== false;
        this.expiryDays = payload.expiry_days ?? 0;
      }
    } catch {
      this.bounties = [];
    } finally {
      this.loading = false;
    }
  }

  // Whole days, rounded up, so six hours left reads as "in 1 day" rather than
  // "in 0 days" — a rounding-down that would read as already over. Zero is what
  // is left for an offer the hourly job has not closed yet, which the row says
  // is closing rather than closed.
  #closesIn(expiresAt) {
    const left = (new Date(expiresAt) - Date.now()) / 86_400_000;
    return Math.max(0, Math.ceil(left));
  }

  <template>
    <section class="ingenic-section ingenic-bounties" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.bounties.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.bounties.subtitle")}}
          </p>
        </div>

        <a class="ingenic-section__more" href={{this.pointsPath}}>
          {{i18n (themePrefix "ingenic.bounties.my_points")}}
        </a>
      </header>

      {{#unless this.available}}
        <p class="ingenic-notice">
          {{i18n (themePrefix "ingenic.bounties.unavailable")}}
        </p>
      {{/unless}}

      <ul class="ingenic-bounty-list">
        {{#each this.rows as |row|}}
          <li class="ingenic-bounty-list__item">
            <span class="ingenic-bounty-list__points">
              {{dIcon "gift"}}
              {{row.points}}
            </span>

            <div class="ingenic-bounty-list__body">
              <a class="ingenic-bounty-list__title" href={{row.url}}>{{row.title}}</a>

              <p class="ingenic-bounty-list__meta">
                {{#if row.category}}
                  <span
                    class="ingenic-bounty-list__category"
                    style="border-color: #{{row.category.color}}"
                  >
                    {{row.category.name}}
                  </span>
                {{/if}}

                {{#if row.asker}}
                  {{i18n
                    (themePrefix "ingenic.bounties.offered_by")
                    username=row.asker
                  }}
                  &middot;
                {{/if}}

                {{#if row.closesIn}}
                  {{i18n (themePrefix "ingenic.bounties.closes_in") count=row.closesIn}}
                {{else}}
                  {{i18n (themePrefix "ingenic.bounties.closing")}}
                {{/if}}
              </p>
            </div>
          </li>
        {{else}}
          <li class="ingenic-bounty-list__empty">
            {{#if this.loading}}
              {{i18n (themePrefix "ingenic.bounties.loading")}}
            {{else}}
              {{i18n (themePrefix "ingenic.bounties.empty")}}
            {{/if}}
          </li>
        {{/each}}
      </ul>

      <p class="ingenic-bounty__hint">
        {{i18n (themePrefix "ingenic.bounties.board_hint") days=this.expiryDays}}
      </p>
    </section>
  </template>
}
