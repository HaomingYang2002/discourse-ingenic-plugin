import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/leaderboard";

/**
 * Homepage block: the members who earned the most this week.
 *
 * The endpoint sums the points ledger from the start of the week, so the board
 * is a reading of contributions rather than a second score kept somewhere else:
 * opening a topic, answering, being liked and having an answer accepted are the
 * rows it counts, and unlocking a download is not.
 *
 * The panel is drawn even when nobody has earned anything yet, for the same
 * reason as the bounty card: a block that appears only once the week has gone
 * well reads as broken to everyone who looked before that.
 */
export default class IngenicBlockLeaderboard extends Component {
  @tracked entries = [];
  @tracked loaded = false;

  // A plain field, not tracked: the load starts in the constructor, which runs
  // inside a render computation, and writing tracked state there is refused.
  requested = false;

  constructor() {
    super(...arguments);
    this.load();
  }

  get limit() {
    return this.args.block?.limit || 5;
  }

  get title() {
    return (
      this.args.block?.title ||
      i18n(themePrefix("ingenic.leaderboard.title"))
    );
  }

  get rows() {
    return this.entries.slice(0, this.limit).map((entry) => ({
      ...entry,
      // The server sends the template, not a URL: the size is the panel's
      // decision, and substituting it here keeps the request to one image per
      // row instead of a full-size avatar shrunk by CSS.
      avatar: entry.avatar_template?.replace("{size}", "48"),
      path: getURL(`/u/${entry.username}`),
      isTop: entry.rank <= 3,
    }));
  }

  async load() {
    if (this.requested) {
      return;
    }

    this.requested = true;

    try {
      const response = await fetch(`${getURL(ENDPOINT)}?limit=${this.limit}`, {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.entries = payload.entries ?? [];
      }
    } catch {
      this.entries = [];
    } finally {
      this.loaded = true;
    }
  }

  <template>
    <section class="ingenic-section ingenic-leaderboard">
      <header class="ingenic-section__header">
        <h2>{{this.title}}</h2>
      </header>

      {{#if this.rows.length}}
        <ol class="ingenic-leaderboard__list">
          {{#each this.rows as |row|}}
            <li class="ingenic-leaderboard__row">
              <span class="ingenic-leaderboard__rank {{if row.isTop 'is-top'}}">
                {{row.rank}}
              </span>

              {{#if row.avatar}}
                <img
                  class="ingenic-leaderboard__avatar"
                  src={{row.avatar}}
                  alt=""
                  loading="lazy"
                />
              {{else}}
                <span class="ingenic-leaderboard__avatar"></span>
              {{/if}}

              <a class="ingenic-leaderboard__user" href={{row.path}}>
                {{row.name}}
              </a>

              <span class="ingenic-leaderboard__points">
                {{row.points}}
                <span class="ingenic-leaderboard__unit">
                  {{i18n (themePrefix "ingenic.leaderboard.points")}}
                </span>
              </span>
            </li>
          {{/each}}
        </ol>
      {{else if this.loaded}}
        <p class="ingenic-card__meta">
          {{i18n (themePrefix "ingenic.leaderboard.empty")}}
        </p>
      {{else}}
        <p class="ingenic-card__meta">
          {{i18n (themePrefix "ingenic.leaderboard.loading")}}
        </p>
      {{/if}}
    </section>
  </template>
}
