import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { trustHTML } from "@ember/template";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

const ROUTE_PREFIX = "/ingenic/docs";
const SEARCH_ENDPOINT = "/ingenic/docs-search";

// The URL is /<series>/<chip>/<version>/<page>. Only the series is required:
// the plugin fills in the series' first chip and that chip's default version,
// so a navigation entry can point at /ingenic/docs and still land somewhere
// real.
const SEGMENT = { series: 0, chip: 1, version: 2, page: 3 };

/**
 * Documentation reader.
 *
 * The left column is the control strip — a two-level product picker (series,
 * then a flyout of chips), the version dropdown, search across the
 * documentation, and the collapsible table of contents. The right column is
 * the rendered page.
 *
 * The URL is the only navigation state. Choosing a chip or a version
 * transitions the router, `@path` changes, and the single refetch in `load`
 * follows. Deep links, the back button and shared addresses therefore agree
 * without any state to reconcile.
 *
 * The page tree arrives flattened and depth-ordered from the plugin, because
 * the plugin has to run the version-inheritance walk to produce it anyway.
 * Rebuilding the tree here from `parent_id` would mean reimplementing that walk
 * on the client, where it would drift.
 *
 * Every link is computed in JS rather than composed in the template: the paths
 * depend on several pieces of resolved state, and building them in one place
 * keeps the markup from carrying navigation logic.
 */
export default class IngenicDocs extends Component {
  @service router;

  @tracked series = [];
  @tracked chip = null;
  @tracked chipSlug = null;
  @tracked versions = [];
  @tracked version = null;
  @tracked pages = [];
  @tracked page = null;
  @tracked navigation = { previous: null, next: null };
  @tracked loading = true;
  @tracked notFound = false;

  @tracked pickerOpen = false;
  @tracked openSeriesSlug = null;
  @tracked treeOpen = true;

  @tracked searchQuery = "";
  @tracked searchResults = null;
  @tracked searching = false;

  get segments() {
    return (this.args.path ?? "").split("/").filter(Boolean).slice(0, 4);
  }

  get seriesSlug() {
    return this.segments[SEGMENT.series];
  }

  get versionSlug() {
    return this.segments[SEGMENT.version] || "latest";
  }

  get urlPageSlug() {
    return this.segments[SEGMENT.page];
  }

  get currentPath() {
    return this.segments.length
      ? `${ROUTE_PREFIX}/${this.segments.join("/")}`
      : ROUTE_PREFIX;
  }

  // Annotated rather than compared in the template, so "which series is open"
  // is one tracked value and the markup carries no equality logic.
  get seriesList() {
    return this.series.map((entry) => ({
      slug: entry.slug,
      name: entry.name,
      isOpen: entry.slug === this.openSeriesSlug,
      isCurrent: entry.slug === this.seriesSlug,
      chips: entry.chips.map((chip) => ({
        slug: chip.slug,
        name: chip.name,
        isCurrent: entry.slug === this.seriesSlug && chip.slug === this.chipSlug,
      })),
    }));
  }

  get hasProducts() {
    return this.series.some((entry) => entry.chips.length > 0);
  }

  get showingSearch() {
    return this.searchResults !== null;
  }

  get tree() {
    return this.pages.map((entry) => ({
      slug: entry.slug,
      title: entry.title,
      depth: entry.depth ?? 0,
      isActive: entry.slug === this.urlPageSlug,
      href: this.hrefFor(entry.slug),
    }));
  }

  get searchHits() {
    return (this.searchResults ?? []).map((result) => ({
      slug: result.slug,
      title: result.title,
      excerpt: result.excerpt,
      href: this.hrefFor(result.slug),
    }));
  }

  get previousLink() {
    return this.#stepLink(this.navigation.previous);
  }

  get nextLink() {
    return this.#stepLink(this.navigation.next);
  }

  #stepLink(resolved) {
    if (!resolved) {
      return null;
    }

    return { slug: resolved.slug, title: resolved.title, href: this.hrefFor(resolved.slug) };
  }

  // A router path, deliberately without the deployment prefix: the router
  // applies rootURL itself, so a prefixed path would break on a subfolder
  // install. `getURL` adds it back wherever the path becomes an href or a
  // fetch target.
  urlFor({ series, chip, version, page }) {
    const parts = [ROUTE_PREFIX, series, chip];

    if (version) {
      parts.push(version);
    }

    if (version && page) {
      parts.push(page);
    }

    return parts.filter(Boolean).join("/");
  }

  hrefFor(pageSlug) {
    return getURL(
      this.urlFor({
        series: this.seriesSlug,
        chip: this.chipSlug,
        version: this.version?.slug ?? this.versionSlug,
        page: pageSlug,
      }),
    );
  }

  @action
  async load() {
    this.loading = true;
    this.notFound = false;
    this.pickerOpen = false;
    this.openSeriesSlug = null;

    try {
      const response = await fetch(getURL(this.currentPath), {
        headers: { Accept: "application/json" },
      });

      if (!response.ok) {
        this.notFound = true;
        return;
      }

      const payload = await response.json();

      this.series = payload.series ?? [];
      this.chip = payload.product ?? null;
      this.chipSlug = payload.chip_slug ?? null;
      this.versions = payload.versions ?? [];
      this.version = payload.version ?? null;
      this.pages = payload.pages ?? [];
      this.page = payload.page ?? null;
      this.navigation = payload.navigation ?? { previous: null, next: null };

      this.#canonicalize(payload);
    } catch {
      this.notFound = true;
    } finally {
      this.loading = false;
    }
  }

  // The plugin resolves a partial path to a concrete chip and version.
  // Rewriting the address to what was actually resolved keeps the version
  // dropdown, the tree links and the URL in agreement, and makes the address a
  // visitor copies the one that reproduces the page.
  //
  // Guarded on inequality: an unconditional replace would transition on every
  // load, and that transition re-enters `load`.
  #canonicalize(payload) {
    if (!payload.series_slug || !payload.chip_slug || !payload.version) {
      return;
    }

    const canonical = this.urlFor({
      series: payload.series_slug,
      chip: payload.chip_slug,
      version: payload.version.slug,
      page: payload.page?.slug,
    });

    if (canonical !== this.currentPath) {
      this.router.replaceWith(canonical);
    }
  }

  @action
  togglePicker() {
    this.pickerOpen = !this.pickerOpen;
  }

  // Hovering a series opens its flyout, which is what the reference layout
  // does. Touch devices never fire mouseenter, so a tap opens it too — and a
  // tap then goes on to select that series' first chip, which is the only
  // outcome a tap can be aiming for.
  @action
  openSeries(series, event) {
    event?.preventDefault();
    this.openSeriesSlug = series.slug;

    if (event?.type === "click") {
      this.selectChip(series, series.chips[0]);
    }
  }

  @action
  closeSeries() {
    this.openSeriesSlug = null;
  }

  @action
  selectChip(series, chip, event) {
    event?.preventDefault();

    if (!chip) {
      return;
    }

    this.pickerOpen = false;
    this.openSeriesSlug = null;
    this.searchResults = null;

    // No version and no page: the plugin supplies this chip's default version
    // and `#canonicalize` rewrites the address once it has.
    this.router.transitionTo(this.urlFor({ series: series.slug, chip: chip.slug }));
  }

  @action
  selectVersion(event) {
    this.router.transitionTo(
      this.urlFor({
        series: this.seriesSlug,
        chip: this.chipSlug || this.segments[SEGMENT.chip],
        version: event.target.value,
        page: this.urlPageSlug,
      }),
    );
  }

  @action
  openPage(page, event) {
    if (!page) {
      return;
    }

    event.preventDefault();
    this.router.transitionTo(
      this.urlFor({
        series: this.seriesSlug,
        chip: this.chipSlug,
        version: this.version?.slug ?? this.versionSlug,
        page: page.slug,
      }),
    );
  }

  @action
  toggleTree() {
    this.treeOpen = !this.treeOpen;
  }

  @action
  updateQuery(event) {
    this.searchQuery = event.target.value;
  }

  @action
  async search(event) {
    event.preventDefault();

    const query = this.searchQuery.trim();

    if (query.length < 2) {
      this.searchResults = null;
      return;
    }

    this.searching = true;

    const params = new URLSearchParams({
      q: query,
      series: this.seriesSlug ?? "",
      chip: this.chipSlug ?? "",
      version: this.version?.slug ?? "",
    });

    try {
      const response = await fetch(getURL(`${SEARCH_ENDPOINT}?${params}`), {
        headers: { Accept: "application/json" },
      });

      this.searchResults = response.ok ? (await response.json()).results : [];
    } catch {
      this.searchResults = [];
    } finally {
      this.searching = false;
    }
  }

  @action
  clearSearch() {
    this.searchQuery = "";
    this.searchResults = null;
  }

  <template>
    <div class="ingenic-docs" {{didInsert this.load}} {{didUpdate this.load @path}}>
      {{#if this.loading}}
        <p class="ingenic-docs__notice">{{i18n (themePrefix "ingenic.docs.loading")}}</p>
      {{else if this.notFound}}
        <p class="ingenic-docs__notice">{{i18n (themePrefix "ingenic.docs.not_found")}}</p>
      {{else if this.hasProducts}}
        <div class="ingenic-docs__panes">
          <aside class="ingenic-docs__controls">
            <div class="ingenic-picker" {{on "mouseleave" this.closeSeries}}>
              <button
                type="button"
                class="ingenic-picker__trigger"
                aria-expanded={{if this.pickerOpen "true" "false"}}
                {{on "click" this.togglePicker}}
              >
                <span class="ingenic-picker__value">
                  {{#if this.chip}}
                    {{this.chip.name}}
                  {{else}}
                    {{i18n (themePrefix "ingenic.docs.pick_product")}}
                  {{/if}}
                </span>
                <span class="ingenic-picker__caret" aria-hidden="true">▾</span>
              </button>

              {{#if this.pickerOpen}}
                <div class="ingenic-picker__panel">
                  <p class="ingenic-picker__heading">
                    {{i18n (themePrefix "ingenic.docs.series")}}
                  </p>
                  <ul class="ingenic-picker__series">
                    {{#each this.seriesList as |series|}}
                      <li
                        class="ingenic-picker__series-item {{if series.isOpen 'is-open'}}"
                        {{on "mouseenter" (fn this.openSeries series)}}
                      >
                        <button
                          type="button"
                          class="ingenic-picker__series-button {{if series.isCurrent 'is-current'}}"
                          {{on "click" (fn this.openSeries series)}}
                        >
                          <span>{{series.name}}</span>
                          <span class="ingenic-picker__arrow" aria-hidden="true">›</span>
                        </button>

                        {{#if series.isOpen}}
                          <ul class="ingenic-picker__chips">
                            {{#each series.chips as |chip|}}
                              <li>
                                <button
                                  type="button"
                                  class="ingenic-picker__chip {{if chip.isCurrent 'is-current'}}"
                                  {{on "click" (fn this.selectChip series chip)}}
                                >
                                  {{chip.name}}
                                </button>
                              </li>
                            {{else}}
                              <li class="ingenic-picker__empty">
                                {{i18n (themePrefix "ingenic.docs.no_chips")}}
                              </li>
                            {{/each}}
                          </ul>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                </div>
              {{/if}}
            </div>

            {{#if this.versions.length}}
              <label class="ingenic-docs__field" for="ingenic-version">
                <span>{{i18n (themePrefix "ingenic.docs.version")}}</span>
                <select
                  id="ingenic-version"
                  class="ingenic-docs__select"
                  value={{this.versionSlug}}
                  {{on "change" this.selectVersion}}
                >
                  {{#each this.versions as |version|}}
                    <option value={{version.slug}}>
                      {{version.label}}{{#if version.latest}} · {{i18n (themePrefix "ingenic.docs.latest")}}{{/if}}
                    </option>
                  {{/each}}
                </select>
              </label>
            {{/if}}

            <form class="ingenic-search ingenic-docs__search" {{on "submit" this.search}}>
              <input
                type="search"
                name="query"
                class="ingenic-search__input"
                value={{this.searchQuery}}
                placeholder={{i18n (themePrefix "ingenic.docs.search_placeholder")}}
                {{on "input" this.updateQuery}}
              />
            </form>

            {{#if this.version.deprecated}}
              <p class="ingenic-docs__notice ingenic-docs__notice--inline">
                {{i18n (themePrefix "ingenic.docs.deprecated")}}
              </p>
            {{/if}}

            <nav class="ingenic-docs__nav">
              <button
                type="button"
                class="ingenic-docs__tree-toggle"
                aria-expanded={{if this.treeOpen "true" "false"}}
                {{on "click" this.toggleTree}}
              >
                {{#if this.showingSearch}}
                  {{i18n (themePrefix "ingenic.docs.search_results")}}
                {{else}}
                  {{i18n (themePrefix "ingenic.docs.contents")}}
                {{/if}}
              </button>

              {{#if this.treeOpen}}
                {{#if this.showingSearch}}
                  <p class="ingenic-docs__search-summary">
                    <span>
                      {{i18n (themePrefix "ingenic.docs.result_count")}}
                      {{this.searchHits.length}}
                    </span>
                    <button type="button" class="ingenic-docs__link" {{on "click" this.clearSearch}}>
                      {{i18n (themePrefix "ingenic.docs.clear_search")}}
                    </button>
                  </p>
                  <ul class="ingenic-nav">
                    {{#each this.searchHits as |hit|}}
                      <li class="ingenic-nav__item">
                        <a class="ingenic-nav__link" href={{hit.href}} {{on "click" (fn this.openPage hit)}}>
                          {{hit.title}}
                          <span class="ingenic-nav__excerpt">{{hit.excerpt}}</span>
                        </a>
                      </li>
                    {{else}}
                      <li class="ingenic-nav__empty">
                        {{i18n (themePrefix "ingenic.docs.no_results")}}
                      </li>
                    {{/each}}
                  </ul>
                {{else}}
                  <ul class="ingenic-nav">
                    {{#each this.tree as |entry|}}
                      <li class="ingenic-nav__item">
                        <a
                          class="ingenic-nav__link ingenic-nav__link--depth-{{entry.depth}} {{if entry.isActive 'is-active'}}"
                          href={{entry.href}}
                          {{on "click" (fn this.openPage entry)}}
                        >
                          {{entry.title}}
                        </a>
                      </li>
                    {{else}}
                      <li class="ingenic-nav__empty">
                        {{i18n (themePrefix "ingenic.docs.empty")}}
                      </li>
                    {{/each}}
                  </ul>
                {{/if}}
              {{/if}}
            </nav>
          </aside>

          <article class="ingenic-docs__body">
            {{#if this.page}}
              <h1 class="ingenic-docs__title">{{this.page.title}}</h1>
              <div class="ingenic-docs__content">{{trustHTML this.page.body}}</div>

              <footer class="ingenic-docs__footer">
                {{#if this.previousLink}}
                  <a class="ingenic-docs__step" href={{this.previousLink.href}} {{on "click" (fn this.openPage this.previousLink)}}>
                    <span class="ingenic-docs__step-label">
                      {{i18n (themePrefix "ingenic.docs.previous")}}
                    </span>
                    {{this.previousLink.title}}
                  </a>
                {{else}}
                  <span></span>
                {{/if}}

                {{#if this.nextLink}}
                  <a class="ingenic-docs__step ingenic-docs__step--next" href={{this.nextLink.href}} {{on "click" (fn this.openPage this.nextLink)}}>
                    <span class="ingenic-docs__step-label">
                      {{i18n (themePrefix "ingenic.docs.next")}}
                    </span>
                    {{this.nextLink.title}}
                  </a>
                {{/if}}
              </footer>

              {{#if this.page.discussion_url}}
                <p class="ingenic-docs__discuss">
                  <a href={{getURL this.page.discussion_url}}>
                    {{i18n (themePrefix "ingenic.docs.discuss")}}
                  </a>
                </p>
              {{/if}}
            {{else}}
              <p class="ingenic-docs__notice">
                {{i18n (themePrefix "ingenic.docs.pick_page")}}
              </p>
            {{/if}}
          </article>
        </div>
      {{else}}
        <p class="ingenic-docs__notice">{{i18n (themePrefix "ingenic.docs.no_products")}}</p>
      {{/if}}
    </div>
  </template>
}
