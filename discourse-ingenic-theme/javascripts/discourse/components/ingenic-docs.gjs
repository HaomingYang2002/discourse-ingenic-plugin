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
const MAX_SEGMENTS = 3;

/**
 * Documentation browser: version picker on top, page tree on the left and the
 * rendered page body on the right.
 *
 * Chip selection is intentionally absent — each chip gets its own forum section
 * and its own documentation entry point — so this component only deals with
 * version and page navigation for a single product.
 *
 * The URL is the only navigation state. Picking a version or a page transitions
 * the router, `@path` changes, and the refetch happens in one place, which keeps
 * deep links, the browser back button and shared URLs consistent.
 */
export default class IngenicDocs extends Component {
  @service router;
  @tracked product = null;
  @tracked version = null;
  @tracked pages = [];
  @tracked page = null;
  @tracked navigation = { previous: null, next: null };
  @tracked loading = true;
  @tracked notFound = false;
  @tracked treeOpen = true;

  get segments() {
    return (this.args.path ?? "")
      .split("/")
      .filter(Boolean)
      .slice(0, MAX_SEGMENTS);
  }

  get productSlug() {
    return this.segments[0];
  }

  // The product the page is actually showing. On a bare /ingenic/docs the URL
  // has no product yet, so building links from the path would produce
  // "/ingenic/docs/undefined/..." during the first paint — the payload's slug is
  // the authoritative one as soon as it arrives.
  get resolvedProductSlug() {
    return this.product?.slug || this.segments[0];
  }

  get versionSlug() {
    return this.segments[1] || "latest";
  }

  get pageSlug() {
    return this.segments[2];
  }

  get versions() {
    return this.product?.versions ?? [];
  }

  // Flattened with a depth so the template can render nesting without
  // recursive components.
  get tree() {
    return this.#flatten(this.pages, null, 0);
  }

  #flatten(pages, parentId, depth) {
    return pages
      .filter((item) => (item.parent_id ?? null) === parentId)
      .sort((a, b) => a.position - b.position)
      .flatMap((item) => [
        { page: item, depth, active: item.slug === this.pageSlug },
        ...this.#flatten(pages, item.id, depth + 1),
      ]);
  }

  // Matches against the version the plugin resolved, not the raw path segment:
  // `/ingenic/docs/<product>` has no version in the URL but does show one, and
  // the picker should say so.
  isCurrentVersion(version) {
    return version.slug === (this.version?.slug || this.versionSlug);
  }

  // Returns a router path, deliberately without the deployment prefix: the
  // router applies rootURL itself, so a prefixed path would break on a
  // subfolder install. Wrap it in `getURL` wherever it becomes an href.
  urlFor(versionSlug, pageSlug, productSlug = this.resolvedProductSlug) {
    const parts = [ROUTE_PREFIX, productSlug, versionSlug];

    if (pageSlug) {
      parts.push(pageSlug);
    }

    return parts.join("/");
  }

  @action
  async load() {
    this.loading = true;
    this.notFound = false;

    // The plugin answers the same URL with JSON when asked for it and with the
    // app shell otherwise, so a page refresh lands here without a second route.
    // With no path at all we still ask: the plugin resolves the product, which
    // is what lets a navigation entry point at /ingenic/docs alone.
    const url = this.segments.length
      ? `${ROUTE_PREFIX}/${this.segments.join("/")}`
      : ROUTE_PREFIX;

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } });

      if (!response.ok) {
        this.notFound = true;
        return;
      }

      const payload = await response.json();

      this.product = payload.product;
      this.version = payload.version;
      this.pages = payload.pages ?? [];
      this.page = payload.page ?? null;
      this.navigation = payload.navigation ?? { previous: null, next: null };

      // A bare /ingenic/docs means "wherever the documentation starts". Now
      // that the plugin has said which product that is, replace the address so
      // the URL a visitor copies and shares is the canonical one.
      if (!this.segments.length) {
        this.router.replaceWith(
          this.urlFor(payload.version.slug, null, payload.product.slug),
        );
      }
    } catch {
      this.notFound = true;
    } finally {
      this.loading = false;
    }
  }

  @action
  toggleTree() {
    this.treeOpen = !this.treeOpen;
  }

  @action
  selectVersion(event) {
    this.router.transitionTo(this.urlFor(event.target.value, this.pageSlug));
  }

  @action
  openPage(page, event) {
    if (!page) {
      return;
    }

    event.preventDefault();
    this.router.transitionTo(this.urlFor(this.versionSlug, page.slug));
  }

  @action
  search(event) {
    event.preventDefault();

    const query = event.target.elements.query.value.trim();

    if (query) {
      this.router.transitionTo(`/search?q=${encodeURIComponent(query)}`);
    }
  }

  <template>
    <div class="ingenic-docs" {{didInsert this.load}} {{didUpdate this.load @path}}>
      <header class="ingenic-docs__header">
        <div class="ingenic-docs__identity">
          {{#if this.product}}
            <span class="ingenic-docs__product">{{this.product.name}}</span>
          {{/if}}
          {{#if this.version}}
            <span class="ingenic-docs__version">{{this.version.label}}</span>
          {{/if}}
        </div>

        <form class="ingenic-search ingenic-docs__search" {{on "submit" this.search}}>
          <input
            type="search"
            name="query"
            class="ingenic-search__input"
            placeholder={{i18n (themePrefix "ingenic.docs.search_placeholder")}}
          />
        </form>
      </header>

      {{#if this.loading}}
        <p class="ingenic-card__meta">…</p>
      {{else if this.notFound}}
        <p class="ingenic-docs__notice">{{i18n (themePrefix "ingenic.docs.not_found")}}</p>
      {{else}}
        <div class="ingenic-docs__panes">
          <aside class="ingenic-docs__tree {{if this.treeOpen "is-open"}}">
            <button class="btn btn-flat ingenic-docs__tree-toggle" type="button" {{on "click" this.toggleTree}}>
              {{i18n (themePrefix "ingenic.docs.contents")}}
            </button>
            {{#if this.versions.length}}
              <label class="ingenic-docs__version-label" for="ingenic-version">
                {{i18n (themePrefix "ingenic.docs.version")}}
              </label>
              <select
                id="ingenic-version"
                class="ingenic-docs__version-select"
                {{on "change" this.selectVersion}}
              >
                {{#each this.versions as |version|}}
                  <option
                    value={{version.slug}}
                    selected={{if (this.isCurrentVersion version) "selected"}}
                  >
                    {{version.label}}{{#if version.latest}} ({{i18n (themePrefix "ingenic.docs.latest")}}){{/if}}
                  </option>
                {{/each}}
              </select>
            {{/if}}

            {{#if this.version.deprecated}}
              <p class="ingenic-docs__notice ingenic-card__meta">
                {{i18n (themePrefix "ingenic.docs.deprecated")}}
              </p>
            {{/if}}

            <nav class="ingenic-docs__nav">
              <p class="ingenic-docs__nav-title">{{i18n (themePrefix "ingenic.docs.contents")}}</p>
              <ul class="ingenic-nav">
                {{#each this.tree as |entry|}}
                  <li class="ingenic-nav__item">
                    <a
                      class="ingenic-nav__link ingenic-nav__link--depth-{{entry.depth}} {{if entry.active 'is-active'}}"
                      href={{getURL (this.urlFor this.versionSlug entry.page.slug)}}
                      {{on "click" (fn this.openPage entry.page)}}
                    >
                      {{entry.page.title}}
                    </a>
                  </li>
                {{/each}}
              </ul>
            </nav>
          </aside>

          <article class="ingenic-docs__body">
            {{#if this.page}}
              <h1>{{this.page.title}}</h1>
              <div class="ingenic-docs__content">{{trustHTML this.page.body}}</div>

              <footer class="ingenic-docs__footer">
                {{#if this.navigation.previous}}
                  <a
                    class="ingenic-docs__step"
                    href={{getURL (this.urlFor this.versionSlug this.navigation.previous.slug)}}
                    {{on "click" (fn this.openPage this.navigation.previous)}}
                  >
                    ← {{this.navigation.previous.title}}
                  </a>
                {{else}}
                  <span></span>
                {{/if}}

                {{#if this.navigation.next}}
                  <a
                    class="ingenic-docs__step ingenic-docs__step--next"
                    href={{getURL (this.urlFor this.versionSlug this.navigation.next.slug)}}
                    {{on "click" (fn this.openPage this.navigation.next)}}
                  >
                    {{this.navigation.next.title}} →
                  </a>
                {{/if}}
              </footer>

              {{#if this.page.discussion_url}}
                <p class="ingenic-docs__discuss">
                  <a href={{getURL this.page.discussion_url}}>{{i18n (themePrefix "ingenic.docs.discuss")}}</a>
                </p>
              {{/if}}
            {{else}}
              <p class="ingenic-docs__notice">{{i18n (themePrefix "ingenic.docs.pick_page")}}</p>
            {{/if}}
          </article>
        </div>
      {{/if}}
    </div>
  </template>
}
