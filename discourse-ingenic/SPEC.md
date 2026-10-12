# Ingenic Discourse — spec and verification checklist

## Delivered

Two installable pieces:

```
discourse-ingenic/          plugin — data, models, JSON endpoints, admin settings
discourse-ingenic-theme/    theme  — layout, navigation, homepage, docs UI
```

Authentication is untouched: Google, GitHub and email stay as configured in
Discourse core. No other login method is added.

## Behaviour

### Navigation and layout

Navigation items are stored in the `ingenic_nav_items` site setting as JSON, so
the Ingenic team can reorder, relabel, hide or repoint entries from the admin UI.
Entries may target a category slug, an internal path or an external URL.

The navigation is registered with `api.addSidebarSection`, so it *is* Discourse's
sidebar rather than a look-alike drawn next to it. That is what gives it the
mobile drawer, the section filter, the collapse state and the active-link
handling without reimplementing any of them, and it leaves no private API for
this project to keep up with.

Theme settings control the sidebar's width and which side it renders on, whether
the Ingenic section sits above or below Discourse's own sections, and an
optional heading above it. The position flip re-points the container grid's
areas and is scoped to the `md` breakpoint and up, because below that core takes
the sidebar out of the grid entirely and shows it as a drawer — there is no
column to move.

Discourse's own show/hide and collapse controls are used as they are; the theme
does not add a second pair that would fight with them. The accent colour is the
theme's **Ingenic Light** colour scheme, edited with the standard admin colour
pickers.

### Homepage

The homepage is assembled from blocks listed in `ingenic_homepage_blocks`.
Supported types: `search`, `announcements`, `discussions`, `downloads`,
`boards`, `html`. Order and visibility are admin-controlled; unknown types are
ignored rather than rendered broken.

### Documentation

Chip families are separated by forum section, so the documentation browser has
no chip selector. It has:

- a version picker, defaulting to the version flagged `latest`
- a nested page tree built from `parent_id`
- the rendered page body
- previous / next navigation in reading order
- an optional "Discuss in forum" link per page

URLs:

```
/ingenic/docs                            first published product, latest version
/ingenic/docs/<product>                  product, latest version
/ingenic/docs/<product>/<version>        a specific version
/ingenic/docs/<product>/<version>/<page> a single page
/ingenic/docs/<product>/latest/<page>    latest alias
```

The bare URL exists so navigation can point at one stable address: the plugin
answers with the first published product, and the client replaces the address
with that product's canonical path, so what a visitor copies and shares is the
canonical URL rather than the redirect stub.

Every URL answers as JSON to a fetch and as the application shell to a browser
navigation, which is what makes a documentation link shareable and refreshable
instead of only reachable by clicking through the app.

Version selection uses the plugin's own product/version/page tables rather than
tags, so version identifiers stay consistent. Tags remain available for search
and editorial grouping.

### Downloads

Resource metadata only — files stay on object storage or a CDN. Filters:
product, type, version, platform. Each record carries size, SHA-256 and release
date. Types: `sdk`, `firmware`, `manual`, `datasheet`, `toolchain`, `example`,
`release_notes`, `other`.

### Development boards

Board records carry name, chip, image, description, an optional documentation
link and a required outbound `application_url`. Outbound links render with
`target="_blank"` and `rel="noopener noreferrer"`.

## Multi-language readiness

Every content table has a `locale` column, so a second language needs no schema
change. Codes are Discourse's own (`zh_CN`, `pt_BR`) because they are compared
against `I18n.locale`; the fallback setting offers exactly the languages the
site can serve, so it cannot drift into naming a language no visitor can ask
for. A hyphenated code such as `zh-CN` would match nothing and is documented as
wrong in `docs/seeding.md`.

A request resolves the reader's language first and falls back to
`ingenic_default_locale` per page, so a half-translated version still renders,
each page appears once in the tree rather than once per locale, and a product
with no translated row at all still opens in the default language.

Theme strings live in `locales/en.yml` and are looked up through `themePrefix`,
because Discourse registers theme translations under a theme-specific namespace.
Adding a language means adding a file with the same keys.

## Not included in this version

- post/reply translation between Chinese and English (separate project)
- migrating content out of the existing Chinese forum
- a chip selector inside the documentation browser (by request)
- file hosting — downloads reference external URLs

## Verification checklist

Must be run on the target instance. Everything below was checked statically
against a Discourse `2026.10.0-latest` checkout; nothing has been executed
inside a running Discourse, because this environment has no Ruby, no bundler and
no database.

### Plugin

- [ ] `./launcher rebuild app` completes and migrations create the five tables
- [ ] `/ingenic/docs.json` resolves the first published product and its latest version
- [ ] `/ingenic/docs.json` returns 404 when no product is published
- [ ] `/ingenic/docs/<product>.json` returns the latest version and page tree
- [ ] `/ingenic/docs/<product>/<version>.json` resolves an explicit version
- [ ] `/ingenic/docs/<product>/latest/<page>.json` resolves through the alias
- [ ] unknown product or version returns 404
- [ ] unpublished pages are absent from the tree and 404 when requested directly
- [ ] `/ingenic/downloads` filters correctly and returns filter options
- [ ] `/ingenic/boards` returns only published boards
- [ ] malformed `ingenic_nav_items` / `ingenic_homepage_blocks` degrade to an
      empty list instead of raising
- [ ] `bundle exec rspec plugins/discourse-ingenic/spec` passes

### Theme

- [ ] theme installs from git and compiles without JS or SCSS errors
- [ ] the Ingenic navigation appears in the sidebar and in the mobile drawer
- [ ] `ingenic_sidebar_position=right` moves the sidebar, above `md` only
- [ ] `ingenic_sidebar_width` changes the column width
- [ ] `ingenic_nav_order=first` puts the Ingenic section above Discourse's sections
- [ ] reordering `ingenic_nav_items` reorders the sidebar after a reload
- [ ] an external nav entry is never highlighted; a docs entry stays highlighted
      on nested documentation pages
- [ ] homepage blocks render in the configured order
- [ ] disabling a block removes it without leaving a gap
- [ ] docs page shows the version picker, tree, body and previous/next
- [ ] switching version keeps the reader on the equivalent page when it exists
- [ ] opening `/ingenic/docs` lands on the first product with the canonical URL
- [ ] download centre filters combine correctly
- [ ] board application button opens the external link in a new tab
- [ ] mobile layout drops to a single column at Discourse's own breakpoint

### Integration

- [ ] Google, GitHub and email login still work
- [ ] no additional login providers appear
- [ ] content in a second locale renders for a reader whose interface language
      matches, and falls back per page where it does not

## Known risks

- **Nothing has been run.** The theme and plugin were verified by parsing
  (Babel and Glimmer for the theme's JS, tree-sitter for Ruby), by YAML parsing,
  and by reading the core source for every API used — `addSidebarSection`,
  `BaseCustomSidebarSection`, the theme route map merge order, the theme
  settings-to-SCSS path and the `virtual:theme` shim. RSpec cannot run here, so
  the plugin specs are written but unexecuted. The first rebuild is the real
  test.
- **Two routes must stay in step.** Rails serves `/ingenic/docs*` and the theme
  registers the matching client routes. If the plugin is disabled while the
  theme stays installed, the client route exists but its fetch 404s and the page
  shows its not-found state instead of failing loudly.
- **SCSS depends on a core variable.** `common.scss` uses
  `$d-sidebar-narrow-width` to reset the sidebar width below the large
  breakpoint. If a future Discourse renames it, the theme fails to compile with
  an "Undefined variable" error in the admin theme editor rather than degrading
  silently — visible, but it does block the theme until fixed.
- **The homepage renders through the `before-topic-list` outlet** and hides
  itself on every route except `/`. Giving it a dedicated route (so `/` shows
  only the Ingenic homepage) needs a client route and a server route, and is the
  natural next step once this is running.
- **`discourse.haom.fun` runs `2026.10.0-latest`, which tracks upstream.** Pin a
  known-good version before deploying to production.
