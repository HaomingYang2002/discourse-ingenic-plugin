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
  download: { label: "download", hint: null },
};

const ACTION_FOR = {
  anonymous: "sign_in",
  needs_profile: "profile",
  needs_request: "request",
  pending: "pending",
  rejected: "rejected",
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
  @tracked filters = { products: [], categories: [], versions: [], platforms: [] };
  @tracked selected = { product: "", category: "", version: "", platform: "" };
  @tracked form = { fields: [], values: {}, completed: false };
  @tracked signedIn = false;
  @tracked loading = true;
  @tracked panel = null;
  @tracked busy = false;
  @tracked notice = null;
  @tracked error = null;

  get loginPath() {
    return getURL("/login");
  }

  // Every label and decision the card needs, worked out here so the template
  // stays a description of the layout rather than a set of lookups.
  get cards() {
    return this.downloads.map((download) => {
      const action = ACTIONS[ACTION_FOR[download.access_state]] ?? ACTIONS.pending;

      return {
        ...download,
        action: ACTION_FOR[download.access_state] ?? "pending",
        actionLabel: this.#label(action.label),
        actionHint: action.hint ? this.#label(action.hint) : null,
        linkTarget: download.external ? "_blank" : "_self",
        linkRel: download.external ? "noopener noreferrer" : null,
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

  @action
  async load() {
    await this.#fetch();
  }

  @action
  async selectProduct(event) {
    await this.#applyFilter("product", event.target.value);
  }

  @action
  async selectCategory(event) {
    await this.#applyFilter("category", event.target.value);
  }

  @action
  async selectVersion(event) {
    await this.#applyFilter("version", event.target.value);
  }

  @action
  async selectPlatform(event) {
    await this.#applyFilter("platform", event.target.value);
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

  #label(key) {
    return i18n(themePrefix(`ingenic.downloads.${key}`));
  }

  #failureMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(" ") || this.#label("failed");
  }

  async #applyFilter(key, value) {
    this.selected = { ...this.selected, [key]: value };
    await this.#fetch();
  }

  async #fetch() {
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

      if (response.ok) {
        const payload = await response.json();
        this.downloads = payload.downloads ?? [];
        this.form = payload.form ?? this.form;
        this.signedIn = payload.signed_in ?? false;

        // Filter options always come from the unfiltered response so the user
        // can widen the selection again after narrowing it.
        if (!query) {
          this.filters = payload.filters ?? this.filters;
        }
      }
    } catch {
      this.downloads = [];
    } finally {
      this.loading = false;
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

      <div class="ingenic-downloads__filters">
        <label class="ingenic-docs__field">
          <span>{{i18n (themePrefix "ingenic.downloads.all_products")}}</span>
          <select {{on "change" this.selectProduct}}>
            <option value="">{{i18n (themePrefix "ingenic.downloads.all_products")}}</option>
            {{#each this.filters.products as |product|}}
              <option value={{product}}>{{product}}</option>
            {{/each}}
          </select>
        </label>

        <label class="ingenic-docs__field">
          <span>{{i18n (themePrefix "ingenic.downloads.all_types")}}</span>
          <select {{on "change" this.selectCategory}}>
            <option value="">{{i18n (themePrefix "ingenic.downloads.all_types")}}</option>
            {{#each this.filters.categories as |category|}}
              <option value={{category.id}}>{{category.name}}</option>
            {{/each}}
          </select>
        </label>

        <label class="ingenic-docs__field">
          <span>{{i18n (themePrefix "ingenic.downloads.all_versions")}}</span>
          <select {{on "change" this.selectVersion}}>
            <option value="">{{i18n (themePrefix "ingenic.downloads.all_versions")}}</option>
            {{#each this.filters.versions as |version|}}
              <option value={{version}}>{{version}}</option>
            {{/each}}
          </select>
        </label>

        <label class="ingenic-docs__field">
          <span>{{i18n (themePrefix "ingenic.downloads.all_platforms")}}</span>
          <select {{on "change" this.selectPlatform}}>
            <option value="">{{i18n (themePrefix "ingenic.downloads.all_platforms")}}</option>
            {{#each this.filters.platforms as |platform|}}
              <option value={{platform}}>{{platform}}</option>
            {{/each}}
          </select>
        </label>
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
              <div class="ingenic-card__meta">
                {{#if card.category_name}}{{card.category_name}}{{/if}}
                {{#if card.version}}· {{card.version}}{{/if}}
                {{#if card.platform}}· {{card.platform}}{{/if}}
              </div>

              {{#if card.description}}
                <p>{{card.description}}</p>
              {{/if}}

              <dl class="ingenic-card__meta">
                {{#if card.file_size}}
                  <dt>{{i18n (themePrefix "ingenic.downloads.size")}}</dt>
                  <dd>{{card.file_size}}</dd>
                {{/if}}
                {{#if card.released_on}}
                  <dt>{{i18n (themePrefix "ingenic.downloads.released")}}</dt>
                  <dd>{{card.released_on}}</dd>
                {{/if}}
                {{#if card.sha256}}
                  <dt>{{i18n (themePrefix "ingenic.downloads.checksum")}}</dt>
                  <dd><code>{{card.sha256}}</code></dd>
                {{/if}}
              </dl>

              <div class="ingenic-card__actions">
                {{#if (eq card.action "download")}}
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
