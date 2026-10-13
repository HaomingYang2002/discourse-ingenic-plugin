import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { themePrefix } from "virtual:theme";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/points";

/**
 * The member's own points: the number, what it is made of, and what the forum
 * pays for.
 *
 * Read-only. Points are earned by posting and by having a post liked, and spent
 * on a download, so there is nothing to do on this page but understand the
 * total — which is why it is a list rather than a form.
 */
export default class IngenicPoints extends Component {
  @tracked balance = 0;
  @tracked rules = [];
  @tracked entries = [];
  @tracked signedIn = false;
  @tracked enabled = true;
  @tracked loading = true;

  get loginPath() {
    return getURL("/login");
  }

  // The movements worth drawing. An award that was taken back is two rows that
  // cancel out, which says more than one row that silently disappeared — but
  // only when both are in the slice on screen.
  get history() {
    return this.entries.map((entry) => ({
      ...entry,
      awarded: entry.points > 0,
      when: new Date(entry.created_at).toLocaleDateString(),
    }));
  }

  @action
  async load() {
    try {
      const response = await fetch(getURL(ENDPOINT), {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.balance = payload.balance ?? 0;
        this.rules = payload.rules ?? [];
        this.entries = payload.entries ?? [];
        this.signedIn = payload.signed_in ?? false;
        this.enabled = payload.enabled !== false;
      }
    } catch {
      this.entries = [];
    } finally {
      this.loading = false;
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.points.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.points.subtitle")}}
          </p>
        </div>

        {{#if this.signedIn}}
          <div class="ingenic-points__balance">
            <span class="ingenic-points__balance-value">{{this.balance}}</span>
            <span class="ingenic-points__balance-label">
              {{i18n (themePrefix "ingenic.points.balance")}}
            </span>
          </div>
        {{/if}}
      </header>

      {{#unless this.enabled}}
        <p class="ingenic-notice">
          {{i18n (themePrefix "ingenic.points.disabled")}}
        </p>
      {{/unless}}

      {{#unless this.signedIn}}
        <div class="ingenic-downloads__prompt">
          <div>
            <strong>{{i18n (themePrefix "ingenic.points.signed_out_title")}}</strong>
            <p>{{i18n (themePrefix "ingenic.points.signed_out_intro")}}</p>
          </div>
          <a class="btn btn-primary" href={{this.loginPath}}>
            {{i18n (themePrefix "ingenic.points.sign_in")}}
          </a>
        </div>
      {{/unless}}

      <h2>{{i18n (themePrefix "ingenic.points.earn_title")}}</h2>
      <ul class="ingenic-points__rules">
        {{#each this.rules as |rule|}}
          <li>
            <span>{{rule.label}}</span>
            <span class="ingenic-points__rule-points">+{{rule.points}}</span>
          </li>
        {{else}}
          <li>{{i18n (themePrefix "ingenic.points.no_rules")}}</li>
        {{/each}}
      </ul>

      {{#if this.signedIn}}
        <h2>{{i18n (themePrefix "ingenic.points.history_title")}}</h2>
        <ul class="ingenic-points__history">
          {{#each this.history as |entry|}}
            <li>
              <span class="ingenic-points__history-reason">{{entry.reason}}</span>
              <span class="ingenic-points__history-when">{{entry.when}}</span>
              <span class="ingenic-points__history-points {{if entry.awarded 'is-award' 'is-deduction'}}">
                {{#if entry.awarded}}+{{/if}}{{entry.points}}
              </span>
            </li>
          {{else}}
            <li>
              {{#if this.loading}}
                {{i18n (themePrefix "ingenic.points.loading")}}
              {{else}}
                {{i18n (themePrefix "ingenic.points.no_history")}}
              {{/if}}
            </li>
          {{/each}}
        </ul>
      {{/if}}

      <p class="ingenic-points__note">
        {{i18n (themePrefix "ingenic.points.spend_note")}}
      </p>
    </section>
  </template>
}
