import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, get } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { themePrefix } from "virtual:theme";
import getURL from "discourse/lib/get-url";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/downloads";

/**
 * What each access state offers, and what it is called.
 *
 * The server decides which state a resource is in and this only decides how to
 * draw it, so there is no path on which the button says "Download" and the file
 * endpoint disagrees. A new tier means a line here and strings in the locale
 * file, not a new branch in the template.
 */
const ACTIONS = {
  sign_in: { label: "sign_in", hint: "sign_in_hint" },
  profile: { label: "profile_action", hint: "profile_hint" },
  request: { label: "apply", hint: "apply_hint" },
  pending: { label: "pending", hint: "pending_hint" },
  rejected: { label: "rejected", hint: "rejected_hint" },
  unlock: { label: "unlock", hint: "unlock_hint" },
  points: { label: "points_short", hint: "points_hint" },
  download: { label: "download", hint: null },
};

const ACTION_FOR = {
  anonymous: "sign_in",
  needs_profile: "profile",
  needs_request: "request",
  pending: "pending",
  rejected: "rejected",
  needs_points: "points",
  granted: "download",
};

/**
 * Download centre. Filter values are derived from the resource data returned by
 * the plugin, so a new product or version shows up in the filters as soon as it
 * is added — no theme change required.
 *
 * The developer form and the application form are drawn in place rather than in
 * a modal: both are a step in a sequence the visitor is already reading, and a
 * modal would hide the resource they are asking about.
 */
export default class IngenicDownloads extends Component {
  @tracked downloads = [];
  @tracked filters = { series: [], chips: [], categories: [], versions: [], platforms: [] };
  @tracked selected = {
    family: "",
    series: "",
    product: "",
    category: "",
  };
  @tracked form = { fields: [], values: {}, completed: false };
  @tracked signedIn = false;
  @tracked points = 0;
  @tracked pointsEnabled = false;
  @tracked loading = true;
  @tracked panel = null;
  @tracked busy = false;
  @tracked notice = null;
  @tracked error = null;

  get loginPath() {
    return getURL("/login");
  }

  // A chip belongs to exactly one series, so choosing a series narrows the chip
  // list rather than offering every chip on the site and then rejecting most of
  // them. Without a series chosen, every chip is offered — a visitor who knows
  // the part number should not have to find its family first.
  get chipOptions() {
    if (!this.selected.series) {
      return this.filters.chips;
    }

    return this.filters.chips.filter(
      (chip) => chip.series_slug === this.selected.series
    );
  }

  // Every label and decision the card needs, worked out here so the template
  // stays a description of the layout rather than a set of lookups.
  //
  // A resource that costs points and that this account has not bought yet is
  // drawn as Unlock rather than Download, and the two are the same link: the
  // endpoint does the charging, and the card only says what is about to happen.
  // The label carries the price, which is why it is built here rather than
  // looked up from the table above.
  get cards() {
    return this.downloads.map((download) => {
      let action = ACTION_FOR[download.access_state] ?? "pending";
      const price = download.point_cost ?? 0;

      if (action === "download" && price > 0 && !download.unlocked) {
        action = "unlock";
      }

      const entry = ACTIONS[action] ?? ACTIONS.pending;

      return {
        ...download,
        action,
        // Both of these are the same link to the same endpoint: it is the
        // endpoint that charges, and the card only says what is about to
        // happen. Told apart by the label rather than by the control.
        isLink: action === "download" || action === "unlock",
        actionLabel: this.#label(entry.label, { points: price }),
        actionHint: entry.hint ? this.#label(entry.hint, { points: price }) : null,
        linkTarget: "_blank",
        linkRel: "noopener noreferrer",
        // What the card says about the file, on one line under its name.
        // These were a definition list, which put every label above its
        // value and let a 64-character checksum wrap down the card. A
        // checksum is what somebody verifying a download needs rather
        // than what somebody choosing one needs: the admin screen is
        // where it is shown.
        metaLine: [
          download.category_name,
          download.version,
          download.platform,
          download.file_size,
          download.released_on,
        ]
          .filter(Boolean)
          .join(" · "),
      };
    });
  }

  get needsDeveloperForm() {
    return this.signedIn && !this.form.completed;
  }

  get panelFields() {
    return this.form.fields ?? [];
  }

  get panelValues() {
    return this.form.values ?? {};
  }

  // Shown to a signed-in visitor on a forum where points are on, and to nobody
  // else: an anonymous visitor has no balance to read, and a forum with points
  // switched off has nothing to say about them.
  get showsPoints() {
    return this.signedIn && this.pointsEnabled;
  }

  get pointsPath() {
    return getURL("/ingenic/points");
  }

  @action
  async load() {
    await this.#fetch();
  }

  // The catalogue's first row: every chip series in the product tree, plus the
  // algorithm line when algorithms have been published. Both come from data —
  // a series is added, renamed and ordered on the documentation screen, and the
  // algorithm line disappears when its last resource does — so this row is not
  // a fixed list in the theme.
  get seriesButtons() {
    const selected = {
      family: this.selected.family,
      series: this.selected.series,
    };
    const all = { id: "all", label: i18n(themePrefix("ingenic.downloads.all_series")) };

    const series = (this.filters.series ?? []).filter(
      (entry) => !this.hasAlgorithm || entry.slug !== "algorithm"
    );

    const buttons = series.map((entry) => ({
      id: entry.slug,
      label: entry.name,
      kind: "series",
    }));

    if (this.hasAlgorithm) {
      // If the site keeps a series row for algorithms, its name is the label:
      // renaming that one row renames this option too. The option still exists
      // without it, because the resources are what make it real.
      const named = (this.filters.series ?? []).find(
        (entry) => entry.slug === "algorithm"
      );

      buttons.push({
        id: "algorithm",
        label: named?.name || i18n(themePrefix("ingenic.downloads.family.algorithm")),
        kind: "algorithm",
      });
    }

    return [
      { ...all, kind: "all", current: !selected.family && !selected.series },
      ...buttons.map((button) => ({
        ...button,
        current:
          button.kind === "algorithm"
            ? selected.family === "algorithm"
            : selected.family !== "algorithm" && selected.series === button.id,
      })),
    ];
  }

  get hasAlgorithm() {
    return (this.filters.families ?? []).includes("algorithm");
  }

  get isAlgorithmFamily() {
    return this.selected.family === "algorithm";
  }

  // Choosing a series drops the chip and type below it: a filter that keeps a
  // value which is no longer in its own list returns an empty page for a
  // reason the visitor cannot see.
  @action
  async pickSeries(item) {
    if (item.kind === "algorithm") {
      this.selected = {
        ...this.selected,
        family: "algorithm",
        series: "",
        product: "",
        category: "",
      };
    } else if (item.kind === "all") {
      this.selected = {
        ...this.selected,
        family: "",
        series: "",
        product: "",
        category: "",
      };
    } else {
      this.selected = {
        ...this.selected,
        family: "",
        series: item.id,
        product: "",
        category: "",
      };
    }

    await this.#fetch();
  }

  // The model row. A chip belongs to one series, so choosing a series narrows
  // this list; with no series chosen every chip in the catalogue is offered,
  // because a visitor who knows the part number should not have to find its
  // family first.
  get productButtons() {
    const selected = this.selected.product ?? "";

    return [
      {
        id: "",
        label: i18n(themePrefix("ingenic.downloads.all_products")),
        current: selected === "",
      },
      ...this.chipOptions.map((chip) => ({
        id: chip.slug,
        label: chip.name,
        current: selected === chip.slug,
      })),
    ];
  }

  // An algorithm runs across chips, so there is no model to choose and the row
  // would be a control with one answer. It is left out rather than shown
  // disabled: a row that cannot do anything is furniture.
  get showsModels() {
    return !this.isAlgorithmFamily && this.chipOptions.length > 0;
  }

  @action
  async pickProduct(value) {
    this.selected = { ...this.selected, product: value ?? "", category: "" };
    await this.#fetch();
  }

  // The type filter is drawn as a row of buttons rather than a select: there
  // are only a handful of types, they are the first thing a visitor narrows by,
  // and a select hid all of them behind one click. The id arrives as a number
  // from the row and as a string from the URL, so both are normalised here.
  @action
  async pickCategory(id) {
    await this.#applyFilter("category", id == null ? "" : String(id));
  }

  // Only the types this chip actually has. The server sends where each type is
  // used, so a visitor who picked a chip sees its own list rather than every
  // type on the site — most of which would return nothing and read as a bug.
  #categoriesForSelection() {
    const all = this.filters.categories ?? [];
    const { family, product, series } = this.selected;

    if (product) {
      return all.filter((category) =>
        (category.product_slugs ?? []).includes(product)
      );
    }

    if (series) {
      const slugs = this.filters.chips
        .filter((chip) => chip.series_slug === series)
        .map((chip) => chip.slug);

      return all.filter((category) =>
        (category.product_slugs ?? []).some((slug) => slugs.includes(slug))
      );
    }

    if (family) {
      return all.filter((category) =>
        (category.families ?? []).includes(family)
      );
    }

    return all;
  }

  // Built here rather than compared in the template: a template call with an
  // argument is what broke the first version of this row, and a list of plain
  // values cannot fail to resolve while the page is drawing.
  get categoryButtons() {
    const selected = String(this.selected.category ?? "");

    return [
      {
        id: null,
        label: i18n(themePrefix("ingenic.downloads.all_resources")),
        current: selected === "",
      },
      ...this.#categoriesForSelection().map((category) => ({
        id: category.id,
        label: category.name,
        current: selected === String(category.id),
      })),
    ];
  }

  // The form opens on the resource that asked for it, so the visitor can see
  // which file they are answering about while they answer.
  @action
  openPanel(kind, download, event) {
    event?.preventDefault();
    this.notice = null;
    this.error = null;
    this.panel = { kind, download };
  }

  @action
  closePanel() {
    this.panel = null;
    this.error = null;
  }

  @action
  async saveProfile(event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;

    const answers = Object.fromEntries(new FormData(event.target));

    try {
      const response = await ajax(`${ENDPOINT}/profile`, {
        type: "POST",
        data: { profile: answers },
      });
      this.form = response.form ?? this.form;
      this.notice = this.#label("profile_saved");
      this.panel = null;
      await this.#fetch();
    } catch (failure) {
      this.error = this.#failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  async sendRequest(event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;

    const { message } = Object.fromEntries(new FormData(event.target));

    try {
      const response = await ajax(
        `${ENDPOINT}/${this.panel.download.id}/request`,
        { type: "POST", data: { message } }
      );
      this.notice = response.notice || this.#label("request_sent");
      this.panel = null;
      await this.#fetch();
    } catch (failure) {
      this.error = this.#failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  dismissNotice() {
    this.notice = null;
  }

  #label(key, params) {
    return i18n(themePrefix(`ingenic.downloads.${key}`), params);
  }

  #failureMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(" ") || this.#label("failed");
  }

  async #applyFilter(key, value) {
    this.selected = { ...this.selected, [key]: value };
    await this.#fetch();
  }

  // Only the newest request may write. A click on a second chip does not wait
  // for the first response, and without this token the slower request could
  // land last and paint the list for the filter the visitor already left.
  #requestSeq = 0;

  async #fetch() {
    const seq = ++this.#requestSeq;
    this.loading = true;

    const params = new URLSearchParams();
    Object.entries(this.selected).forEach(([key, value]) => {
      if (value) {
        params.set(key, value);
      }
    });

    const query = params.toString();
    const url = getURL(ENDPOINT);

    try {
      const response = await fetch(query ? `${url}?${query}` : url, {
        headers: { Accept: "application/json" },
      });

      if (seq !== this.#requestSeq) {
        return;
      }

      if (response.ok) {
        const payload = await response.json();
        this.downloads = payload.downloads ?? [];
        this.form = payload.form ?? this.form;
        this.signedIn = payload.signed_in ?? false;
        this.points = payload.points ?? 0;
        this.pointsEnabled = payload.points_enabled ?? false;

        // Filter options always come from the unfiltered response so the user
        // can widen the selection again after narrowing it.
        if (!query) {
          this.filters = payload.filters ?? this.filters;
        }
      }
    } catch {
      if (seq === this.#requestSeq) {
        this.downloads = [];
      }
    } finally {
      if (seq === this.#requestSeq) {
        this.loading = false;
      }
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.downloads.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.downloads.subtitle")}}
          </p>
        </div>

        {{#if this.showsPoints}}
          <a class="ingenic-points__balance" href={{this.pointsPath}}>
            <span class="ingenic-points__balance-value">{{this.points}}</span>
            <span class="ingenic-points__balance-label">
              {{i18n (themePrefix "ingenic.downloads.points_balance")}}
            </span>
          </a>
        {{/if}}
      </header>

      {{#if this.notice}}
        <p class="ingenic-notice ingenic-notice--ok">
          {{this.notice}}
          <button
            class="ingenic-notice__close"
            type="button"
            {{on "click" this.dismissNotice}}
          >×</button>
        </p>
      {{/if}}

      {{#if this.error}}
        <p class="ingenic-notice ingenic-notice--error">{{this.error}}</p>
      {{/if}}

      <div
        class="ingenic-downloads__filter"
        role="group"
        aria-label={{i18n (themePrefix "ingenic.downloads.series_label")}}
      >
        <span class="ingenic-downloads__filter-label">
          {{i18n (themePrefix "ingenic.downloads.series_label")}}
        </span>
        <div class="ingenic-downloads__options">
          {{#each this.seriesButtons as |item|}}
            <button
              type="button"
              class="ingenic-downloads__option {{if item.current 'is-current'}}"
              aria-pressed={{item.current}}
              disabled={{this.loading}}
              {{on "click" (fn this.pickSeries item)}}
            >
              {{item.label}}
            </button>
          {{/each}}
        </div>
      </div>

      {{#if this.showsModels}}
        <div
          class="ingenic-downloads__filter"
          role="group"
          aria-label={{i18n (themePrefix "ingenic.downloads.product_label")}}
        >
          <span class="ingenic-downloads__filter-label">
            {{i18n (themePrefix "ingenic.downloads.product_label")}}
          </span>
          <div class="ingenic-downloads__options">
            {{#each this.productButtons as |item|}}
              <button
                type="button"
                class="ingenic-downloads__option {{if item.current 'is-current'}}"
                aria-pressed={{item.current}}
                disabled={{this.loading}}
                {{on "click" (fn this.pickProduct item.id)}}
              >
                {{item.label}}
              </button>
            {{/each}}
          </div>
        </div>
      {{/if}}

      <div
        class="ingenic-downloads__filter"
        role="group"
        aria-label={{i18n (themePrefix "ingenic.downloads.category_label")}}
      >
        <span class="ingenic-downloads__filter-label">
          {{i18n (themePrefix "ingenic.downloads.category_label")}}
        </span>
        <div class="ingenic-downloads__options ingenic-downloads__options--wrap">
          {{#each this.categoryButtons as |item|}}
            <button
              type="button"
              class="ingenic-downloads__option {{if item.current 'is-current'}}"
              aria-pressed={{item.current}}
              disabled={{this.loading}}
              {{on "click" (fn this.pickCategory item.id)}}
            >
              {{item.label}}
            </button>
          {{/each}}
        </div>
      </div>

      {{#if this.needsDeveloperForm}}
        <div class="ingenic-downloads__prompt">
          <div>
            <strong>{{i18n (themePrefix "ingenic.downloads.developer_form")}}</strong>
            <p>{{i18n (themePrefix "ingenic.downloads.developer_form_intro")}}</p>
          </div>
          <button class="btn" type="button" {{on "click" (fn this.openPanel "profile" null)}}>
            {{i18n (themePrefix "ingenic.downloads.profile_action")}}
          </button>
        </div>
      {{/if}}

      {{#if this.panel}}
        {{#if (eq this.panel.kind "profile")}}
          <form class="ingenic-downloads__panel" {{on "submit" this.saveProfile}}>
            <h2>{{i18n (themePrefix "ingenic.downloads.developer_form")}}</h2>

            <div class="ingenic-downloads__fields">
              {{#each this.panelFields as |field|}}
                <label class="ingenic-docs__field">
                  <span>
                    {{field.label}}
                    {{#if field.required}}<em>*</em>{{/if}}
                  </span>
                  {{#if (eq field.type "textarea")}}
                    <textarea name={{field.key}} rows="3">{{get this.panelValues field.key}}</textarea>
                  {{else}}
                    <input name={{field.key}} value={{get this.panelValues field.key}} />
                  {{/if}}
                </label>
              {{/each}}
            </div>

            <div class="ingenic-downloads__panel-actions">
              <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
                {{i18n (themePrefix "ingenic.downloads.submit_profile")}}
              </button>
              <button class="btn" type="button" {{on "click" this.closePanel}}>
                {{i18n (themePrefix "ingenic.downloads.cancel")}}
              </button>
            </div>
          </form>
        {{else}}
          <form class="ingenic-downloads__panel" {{on "submit" this.sendRequest}}>
            <h2>
              {{i18n (themePrefix "ingenic.downloads.apply")}}
              {{#if this.panel.download}}· {{this.panel.download.name}}{{/if}}
            </h2>

            <label class="ingenic-docs__field">
              <span>{{i18n (themePrefix "ingenic.downloads.message")}}</span>
              <textarea name="message" rows="4"></textarea>
            </label>

            <div class="ingenic-downloads__panel-actions">
              <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
                {{i18n (themePrefix "ingenic.downloads.submit_request")}}
              </button>
              <button class="btn" type="button" {{on "click" this.closePanel}}>
                {{i18n (themePrefix "ingenic.downloads.cancel")}}
              </button>
            </div>
          </form>
        {{/if}}
      {{/if}}

      {{#if this.cards.length}}
        <div class="ingenic-card-grid">
          {{#each this.cards as |card|}}
            <article class="ingenic-card ingenic-card--download">
              <div class="ingenic-card__title">{{card.name}}</div>
              {{#if card.metaLine}}
                <div class="ingenic-card__meta">{{card.metaLine}}</div>
              {{/if}}

              {{#if card.description}}
                <p>{{card.description}}</p>
              {{/if}}

              <div class="ingenic-card__actions">
                {{#if card.isLink}}
                  <a
                    class="btn btn-primary"
                    href={{card.file_path}}
                    target={{card.linkTarget}}
                    rel={{card.linkRel}}
                  >
                    {{card.actionLabel}}
                  </a>
                {{else if (eq card.action "sign_in")}}
                  <a class="btn btn-primary" href={{this.loginPath}}>
                    {{card.actionLabel}}
                  </a>
                {{else if (eq card.action "profile")}}
                  <button
                    class="btn btn-primary"
                    type="button"
                    {{on "click" (fn this.openPanel "profile" card)}}
                  >
                    {{card.actionLabel}}
                  </button>
                {{else if (eq card.action "request")}}
                  <button
                    class="btn btn-primary"
                    type="button"
                    {{on "click" (fn this.openPanel "request" card)}}
                  >
                    {{card.actionLabel}}
                  </button>
                {{else}}
                  <span class="ingenic-card__state">{{card.actionLabel}}</span>
                {{/if}}
              </div>

              {{#if card.actionHint}}
                <p class="ingenic-card__hint">{{card.actionHint}}</p>
              {{/if}}
            </article>
          {{/each}}
        </div>
      {{else if this.loading}}
        <p class="ingenic-card__meta">…</p>
      {{else}}
        <p class="ingenic-card__meta">
          {{i18n (themePrefix "ingenic.downloads.empty")}}
        </p>
      {{/if}}
    </section>
  </template>
}
