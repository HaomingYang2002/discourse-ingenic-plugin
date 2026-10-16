import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { themePrefix } from "virtual:theme";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/bounties";
const STANDING = "open";
const PAID = "accepted";

/**
 * The 高分悬赏 on the topic being read, and the control that opens one.
 *
 * Drawn from the topic page's own payload rather than fetched, because the topic
 * page already knows: the serializer carries the bounty and whether this member
 * may open one, so a topic with a bounty in it costs no extra request and a
 * topic without one costs nothing at all.
 *
 * Three things can be on screen, and never together:
 *
 *   a standing offer   the amount, who put it up, when it closes, and — for the
 *                      asker or a member of staff — the way to withdraw it
 *   a paid offer       what was paid and to whom, which is the part worth reading
 *                      afterwards: it is what says an answer here had a price
 *   the offer control   shown to the author of a topic that has no offer on it
 *
 * A withdrawn or expired offer draws nothing. It is still the row the server
 * sends — it is the newest one for the moment before the next is opened — and
 * "this was withdrawn" is not something a question should carry for the rest of
 * its life.
 *
 * Whether the control is shown is the server's answer (`can_open_ingenic_bounty`)
 * and not the browser's guess; whether the offer *succeeds* is the server's too,
 * and its refusal is a sentence to display rather than an error page. The floor,
 * the ceiling and the member's balance are not on the topic page, so they are
 * asked for when somebody is actually about to offer points — which is also the
 * moment the form can say whether they have enough.
 */
export default class IngenicBounty extends Component {
  // What this page has done to the topic's bounty, if anything. Absent, the
  // topic's own copy is the truth; after a write, the row the server answered
  // with is — a write does not re-fetch the topic to be told what it just did.
  @tracked outcome = null;

  @tracked asking = false;
  @tracked confirming = false;
  @tracked limits = null;
  @tracked amount = null;
  @tracked busy = false;
  @tracked error = null;
  @tracked notice = null;

  get topic() {
    return this.args.outletArgs?.model;
  }

  get bounty() {
    return this.outcome ? this.outcome.bounty : this.topic?.ingenic_bounty ?? null;
  }

  get standing() {
    return this.bounty?.state === STANDING ? this.bounty : null;
  }

  get paid() {
    return this.bounty?.state === PAID ? this.bounty : null;
  }

  get canOffer() {
    return !this.standing && this.topic?.can_open_ingenic_bounty === true;
  }

  // Read through a getter rather than down the path in the template: a deleted
  // account leaves the field empty, and a template that walked into it would
  // take the whole banner down with it.
  get askerName() {
    return this.standing?.user?.username;
  }

  get payerName() {
    return this.paid?.answerer?.username;
  }

  // Whole days, rounded up, so six hours left reads as "in 1 day" rather than
  // "in 0 days" — a rounding-down that would read as already over. Zero is what
  // is left for an offer whose deadline has passed and which the hourly job has
  // not closed yet: it is closing, not closed, and the banner says so.
  get closesIn() {
    const left = (new Date(this.standing.expires_at) - Date.now()) / 86_400_000;
    return Math.max(0, Math.ceil(left));
  }

  get floor() {
    return this.limits?.min_points ?? 1;
  }

  // What the member could actually offer: the forum's ceiling, or everything
  // they have, whichever is smaller. The server is still the one that refuses;
  // this is only so the form does not invite a number it knows will be turned
  // down.
  get ceiling() {
    return Math.min(this.limits?.max_points ?? this.floor, this.limits?.balance ?? 0);
  }

  get affordable() {
    return this.ceiling >= this.floor;
  }

  get blocked() {
    return this.busy || !this.affordable;
  }

  get amountHint() {
    return this.affordable
      ? i18n(themePrefix("ingenic.bounties.amount_range"), {
          min: this.floor,
          max: this.ceiling,
        })
      : i18n(themePrefix("ingenic.bounties.below_floor"), { min: this.floor });
  }

  @action
  async ask(event) {
    event?.preventDefault();
    this.error = null;
    this.notice = null;

    if (!this.limits) {
      await this.#loadLimits();
    }

    this.amount ??= String(this.floor);
    this.asking = true;
  }

  @action
  setAmount(event) {
    this.amount = event.target.value;
  }

  @action
  closeForm() {
    this.asking = false;
    this.error = null;
  }

  @action
  async submit(event) {
    event.preventDefault();
    const points = Number.parseInt(this.amount, 10);

    // Caught here as well as on the server, so that an empty box is answered
    // instantly rather than with a round trip that says the same thing.
    if (!points) {
      this.error = i18n(themePrefix("ingenic.bounties.amount_blank"));
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const response = await ajax(ENDPOINT, {
        type: "POST",
        data: { topic_id: this.topic.id, points },
      });

      this.outcome = { bounty: response.bounty };
      this.asking = false;
      this.limits = { ...this.limits, balance: response.balance ?? 0 };
      this.notice = i18n(themePrefix("ingenic.bounties.opened"));
    } catch (failure) {
      this.error = this.#failure(failure);
    } finally {
      this.busy = false;
    }
  }

  // Withdrawing is a second press rather than a dialog: the button turns into
  // the question it is asking, which is one tap fewer than a modal and keeps the
  // decision where the offer is written.
  @action
  confirmWithdrawal() {
    this.confirming = true;
    this.error = null;
  }

  @action
  keepBounty() {
    this.confirming = false;
  }

  @action
  async withdraw() {
    this.busy = true;
    this.error = null;

    try {
      const response = await ajax(`${ENDPOINT}/${this.standing.id}/cancel`, {
        type: "POST",
      });

      this.outcome = { bounty: response.bounty };
      this.confirming = false;
      this.limits = this.limits && { ...this.limits, balance: response.balance ?? 0 };
      this.notice = response.notice || i18n(themePrefix("ingenic.bounties.withdrawn"));
    } catch (failure) {
      this.error = this.#failure(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  dismiss() {
    this.notice = null;
    this.error = null;
  }

  async #loadLimits() {
    try {
      const response = await fetch(ENDPOINT, {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.limits = {
          min_points: payload.min_points ?? 1,
          max_points: payload.max_points ?? 0,
          balance: payload.balance ?? 0,
        };
      }
    } catch {
      // Left unset: the form then falls back to a floor of one and a ceiling of
      // nothing, so it says the member has nothing to offer rather than inviting
      // a number. The server still has the last word on what it accepts.
    }
  }

  #failure(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(" ") || i18n(themePrefix("ingenic.bounties.failed"));
  }

  <template>
    {{#if this.standing}}
      <div class="ingenic-bounty is-standing">
        <div class="ingenic-bounty__amount">
          {{dIcon "gift"}}
          <span class="ingenic-bounty__points">{{this.standing.points}}</span>
          <span class="ingenic-bounty__unit">
            {{i18n (themePrefix "ingenic.bounties.points")}}
          </span>
        </div>

        <div class="ingenic-bounty__body">
          <p class="ingenic-bounty__title">
            {{i18n (themePrefix "ingenic.bounties.standing")}}
          </p>
          <p class="ingenic-bounty__meta">
            {{#if this.askerName}}
              {{i18n
                (themePrefix "ingenic.bounties.offered_by")
                username=this.askerName
              }}
              &middot;
            {{/if}}
            {{#if this.closesIn}}
              {{i18n (themePrefix "ingenic.bounties.closes_in") count=this.closesIn}}
            {{else}}
              {{i18n (themePrefix "ingenic.bounties.closing")}}
            {{/if}}
          </p>
        </div>

        {{#if this.standing.can_cancel}}
          <div class="ingenic-bounty__actions">
            {{#if this.confirming}}
              <span class="ingenic-bounty__question">
                {{i18n (themePrefix "ingenic.bounties.withdraw_confirm")}}
              </span>
              <button
                type="button"
                class="btn btn-danger"
                disabled={{this.busy}}
                {{on "click" this.withdraw}}
              >
                {{i18n (themePrefix "ingenic.bounties.withdraw_yes")}}
              </button>
              <button type="button" class="btn btn-flat" {{on "click" this.keepBounty}}>
                {{i18n (themePrefix "ingenic.bounties.withdraw_no")}}
              </button>
            {{else}}
              <button type="button" class="btn" {{on "click" this.confirmWithdrawal}}>
                {{i18n (themePrefix "ingenic.bounties.withdraw")}}
              </button>
            {{/if}}
          </div>
        {{/if}}
      </div>
    {{else if this.paid}}
      <div class="ingenic-bounty is-paid">
        <div class="ingenic-bounty__amount">
          {{dIcon "gift"}}
          <span class="ingenic-bounty__points">{{this.paid.points}}</span>
          <span class="ingenic-bounty__unit">
            {{i18n (themePrefix "ingenic.bounties.points")}}
          </span>
        </div>

        <div class="ingenic-bounty__body">
          <p class="ingenic-bounty__title">
            {{#if this.payerName}}
              {{i18n (themePrefix "ingenic.bounties.paid") username=this.payerName}}
            {{else}}
              {{i18n (themePrefix "ingenic.bounties.paid_anonymously")}}
            {{/if}}
          </p>
        </div>
      </div>
    {{/if}}

    {{#if this.notice}}
      <p class="ingenic-bounty__notice">
        {{this.notice}}
        <button type="button" class="btn-flat" {{on "click" this.dismiss}}>
          {{i18n (themePrefix "ingenic.bounties.dismiss")}}
        </button>
      </p>
    {{/if}}

    {{#if this.error}}
      <p class="ingenic-bounty__error">{{this.error}}</p>
    {{/if}}

    {{#if this.canOffer}}
      {{#if this.asking}}
        <form class="ingenic-bounty is-form" {{on "submit" this.submit}}>
          <label class="ingenic-bounty__field">
            <span>{{i18n (themePrefix "ingenic.bounties.amount")}}</span>
            <input
              type="number"
              name="points"
              min={{this.floor}}
              max={{this.ceiling}}
              value={{this.amount}}
              disabled={{this.busy}}
              {{on "input" this.setAmount}}
            />
          </label>

          <p class="ingenic-bounty__hint">
            {{this.amountHint}}
            {{#if this.limits}}
              {{i18n (themePrefix "ingenic.bounties.balance") points=this.limits.balance}}
            {{/if}}
          </p>

          <div class="ingenic-bounty__actions">
            <button type="submit" class="btn btn-primary" disabled={{this.blocked}}>
              {{i18n (themePrefix "ingenic.bounties.submit")}}
            </button>
            <button type="button" class="btn btn-flat" {{on "click" this.closeForm}}>
              {{i18n (themePrefix "ingenic.bounties.cancel")}}
            </button>
          </div>
        </form>
      {{else}}
        <button type="button" class="ingenic-bounty is-offer" {{on "click" this.ask}}>
          <span class="ingenic-bounty__offer-label">
            {{i18n (themePrefix "ingenic.bounties.offer")}}
          </span>
          <span class="ingenic-bounty__hint">
            {{i18n (themePrefix "ingenic.bounties.offer_hint")}}
          </span>
        </button>
      {{/if}}
    {{/if}}
  </template>
}
