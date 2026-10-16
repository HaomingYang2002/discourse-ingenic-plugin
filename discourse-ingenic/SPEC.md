# Ingenic Discourse — spec and verification checklist

## Delivered

Two installable pieces:

```
discourse-ingenic/          plugin — data, models, JSON endpoints, admin screens
discourse-ingenic-theme/    theme  — layout, sidebar, homepage, docs/downloads/boards UI
```

Authentication is untouched: Google, GitHub and email stay as configured in
Discourse core. No other login method is added.

## Behaviour

### Navigation and layout

Discourse's own sidebar is kept whole — the community section, All categories
and Tags are core's, and so are the show/hide, collapse and filter controls
around them. The developer area is added *below* them as a first-class sidebar
section, so the mobile drawer, the section filter, the collapse state and
active-link handling all come from core rather than being reimplemented.

It is registered with `api.addSidebarSection`, which appends to the same panel
core's own sections render into. Its three entries — Online Documentation, SDK &
Firmware Downloads, Development Boards — point at `/ingenic/docs`,
`/ingenic/downloads` and `/ingenic/boards`.

A link stays highlighted for the whole subtree it points at, so a reader on
`/ingenic/docs/t-series/t33/2.1.0/overview` still sees Documentation
highlighted. Core's own comparison is exact, and these links are plain URLs
rather than routes, so the section decides this itself from the current URL.
An external entry is never highlighted.

Navigation items live in the `ingenic_nav_items` site setting as JSON, so the
Ingenic team can reorder, relabel, hide or repoint entries from the admin UI.
Entries may target a category slug, an internal path or an external URL.

Theme settings control the sidebar's width and which side it renders on, whether
the Ingenic section sits above or below Discourse's own sections, and an
optional heading above it. The position flip re-points the container grid's
areas and is scoped to the `md` breakpoint and up, because below that core takes
the sidebar out of the grid entirely and shows it as a drawer — there is no
column to move.

### Homepage

The homepage is assembled from blocks listed in `ingenic_homepage_blocks`.
Supported types: `announcements`, `discussions`, `downloads`,
`boards`, `docs`, `html`. Order and visibility are admin-controlled; unknown
types are ignored rather than rendered broken. The blocks render above the topic
list through the `before-topic-list` outlet, so the forum's own list is not
replaced.

### Documentation

Chip families are forum sections; the documentation browser itself has a
**two-level product picker** — series, then a flyout of that series' chips —
plus a version selector, full-text search and a collapsible contents tree. The
right-hand column renders the page body as Markdown, and previous/next follow
reading order.

URLs:

```
/ingenic/docs                                     first published series → its first chip → latest version
/ingenic/docs/<series>                            first chip of that series
/ingenic/docs/<series>/<chip>                     that chip's latest version
/ingenic/docs/<series>/<chip>/<version>           a specific version
/ingenic/docs/<series>/<chip>/<version>/<page>    a single page
```

Each level is filled in from the one before when omitted, so a link shared at
any depth still lands somewhere real. The bare URL answers with the first
published series; the client then replaces the address with the canonical path,
so what a visitor copies is the canonical URL rather than the redirect stub.

Every URL answers as JSON to a fetch and as the application shell to a browser
navigation, which is what makes a documentation link shareable and refreshable
instead of only reachable by clicking through the app.

#### Version inheritance

A version stores only the pages it changed. `ingenic_doc_pages` therefore has
one row per page **per version it was edited in**, and a version with no row for
a slug resolves to the nearest earlier version that has one. The resolution
lives in `Ingenic::DocumentationResolver`, not in a controller, and each
resolved page carries where it came from so the reader can label it and the
management screen can offer "override here" and "go back to inheriting".

Without this, a documentation set would multiply by its version count, and every
typographical fix would have to be repeated in every version or silently
diverge.

The chain order comes from `ingenic_doc_versions.position`, which already
existed — no extra dependency.

### Downloads

Three tiers, stored as `ingenic_downloads.access_level`:

| Level | Visitor | Server |
| --- | --- | --- |
| `public_login` | Signs in, then downloads | Signed in |
| `login_form` | Signs in, submits the developer information form once | Signed in with a stored profile |
| `login_form_request` | Signs in, submits the form, applies for that resource | Signed in, with a profile **and** a live grant for that resource |

The developer information form is one record per account, shared by every gated
resource, and its fields are configured by `ingenic_developer_form_fields` — so
the form, its validation and the admin's view of an answer are generated from
one description and cannot disagree. Left empty, a built-in developer field set
is used.

An application is recorded in `ingenic_download_requests` and emailed to
`ingenic_download_admin_email`. Approving writes an `ingenic_download_grants`
row; grants are per account and per resource, and can be revoked, so an approval
for one SDK does not open the rest and a revocation is auditable.

Files are stored under `ingenic_download_storage_path`, which defaults to a
directory beside the application rather than under `public/`: a file the web
server would hand to anyone who guesses its URL cannot be gated by anything the
plugin does. Delivery goes through the controller, which checks access first and
then streams the file with an explicit `Content-Type`, `Content-Length` and
`Content-Disposition`.

Metadata is recorded per record: kind, version, platform, architecture, size,
SHA-256 and release date. Kinds: `sdk`, `firmware`, `manual`, `datasheet`,
`toolchain`, `example`, `release_notes`, `other`.

A resource may also carry `point_cost`, 0 by default. The price is asked after
the access level rather than instead of it, so a `login_form_request` resource
that costs points still sends a new visitor through sign-in, developer details
and approval first. Charging happens in the branch of the file endpoint that
releases the file, never in the one that reports a resource unavailable, so a
download missing from storage costs nothing.

### Points

Three tables. `ingenic_point_rules` is the price list — what each action is
worth, its label, its order and whether it is still paid. `ingenic_point_entries`
is the ledger: one append-only row per movement, never edited.
`ingenic_point_balances` is a running total per account, derived from the entries
and rebuildable from them.

Four events, seeded by the migration at 5 / 2 / 1 / 15: `topic_created`,
`post_created`, `like_received`, `solution_accepted`. Each is an event Discourse
core (or `discourse-solved`, for the last) actually fires. Retiring an action is
`published: false` rather than a delete, because the ledger keeps referring to
it; `IngenicPointRule.amount_for` reads a retired rule as 0, which is what makes
that safe.

`Ingenic::Points` is the only door into the ledger — `award`, `reverse`,
`reverse_subject`, `spend`, `adjust`, `total_for`, `unlocked_download_ids`,
`rebuild!`. Every movement writes the entry and moves the balance in the same
transaction, so the two cannot come apart.

Reversal is a second, opposite entry rather than an edit, so the ledger says
what happened. `spend` answers `:spent`, `:already` or `:insufficient` rather
than raising, because the caller is a download and "you have not got enough" is
a state to show. An award is once per subject, enforced by a unique index rather
than by a check — including manual adjustments, which have no subject, so
Postgres's treatment of NULLs as distinct is what lets an administrator adjust
the same account twice.

The hooks that subscribe to posting events rescue everything and report to the
log: a point is not worth failing the post that earned it.

A member sees their own balance, the price list and their own history at
`/ingenic/points`, read-only from the front end. The admin screen at
**Ingenic → Points** is administrator-only for reading as well as writing,
because the ledger names accounts and an adjustment moves a member's standing.

### Development boards

A board is filed against a **chip in the product tree** and reads its name from
there, so the catalogue and the documentation cannot disagree about what a chip
is called. A board not yet filed keeps the name typed into it, so nothing
already entered is lost; deleting a chip retires it from the documentation
without taking the board off the site.

The catalogue filters by series — through the chips filed under it — and by
chip. Both filter option lists come from the tree rather than from the boards on
the page, so choosing a series does not remove the control that undoes the
choice.

Cards carry an image, name, chip, description, a specification list, an optional
documentation link and a required outbound `application_url`. Outbound links
render with `target="_blank"` and `rel="noopener noreferrer"`.

### Scoped permissions

A permission grants a user or group access to a product, a page, or a board. A
product permission is inherited by its versions and pages; a page permission is
inherited only by that page's children. Granting `T Series` lets a manager edit
its descendants; granting `T33` does not grant access to its siblings or its
parent.

Enforcement is server-side in `Ingenic::PermissionResolver` plus a Guardian
extension. Hiding a button in the admin UI is presentation, not the boundary.

## Multi-language readiness

Every content table has a `locale` column, so a second language needs no schema
change. Codes are Discourse's own (`zh_CN`, `pt_BR`) because they are compared
against `I18n.locale`; the fallback setting offers exactly the languages the
site can serve, so it cannot drift into naming a language no visitor can ask
for. A hyphenated code such as `zh-CN` would match nothing and is documented as
wrong in `docs/seeding.md`.

A request resolves the reader's language first and falls back to
`ingenic_default_locale` per record, so a half-translated version still renders,
each page appears once in the tree rather than once per locale, a board with
both locales renders one card rather than two, and a product with no translated
row at all still opens in the default language.

Theme strings live in `locales/en.yml` and are looked up through `themePrefix`,
because Discourse registers theme translations under a theme-specific namespace.
Adding a language means adding a file with the same keys.

## Compatibility

The target is Discourse `2026.10.0-latest`, and the extension surface was chosen
so an upgrade is a check rather than a rewrite:

- No core JavaScript is overridden and no core template is replaced. The
  integration points are `api.addSidebarSection`, `api.renderInOutlet`, a
  plugin-side route map and standard Rails routes.
- Styles are namespaced: the plugin and the theme each style only their own
  `ingenic-*` classes, using Discourse's CSS custom properties for colour rather
  than hard-coding a palette. No core class is redefined.
- Admin screens are ordinary plugin routes under
  `/admin/plugins/discourse-ingenic`, guarded by a constraint that asks the
  Guardian, rather than monkey-patching the admin router.
- `spec/plugin_requires_spec.rb` and `.tools/check/requirecheck.mjs` fail if an
  `app/` or `lib/` file is added without being required in `plugin.rb`, which is
  the failure mode that would otherwise appear only at runtime.

Known couplings, each of which fails loudly rather than silently:

- `common.scss` uses `$d-sidebar-narrow-width` to reset the sidebar width below
  the large breakpoint. A rename upstream is an "Undefined variable" error in
  the theme editor — visible, but it does block the theme until fixed.
- Two routes must stay in step: Rails serves `/ingenic/docs*` and the theme
  registers the matching client routes. If the plugin is disabled while the
  theme stays installed, the client route exists but its fetch 404s and the page
  shows its not-found state rather than failing loudly.
- `2026.10.0-latest` tracks upstream. Pin a known-good version before deploying
  to production.

## Not included in this version

- post/reply translation between Chinese and English (separate project)
- migrating content out of the existing Chinese forum
- a chip selector in the documentation *header* — the picker is in the control
  column, per the approved design

## Verification checklist

Everything below was checked statically against a Discourse `2026.10.0-latest`
checkout: Babel and Glimmer parsing for the JavaScript, tree-sitter for Ruby,
YAML parsing for the locales and settings, a scan for classes the markup names
that no rule defines, and a scan for `i18n`/`themePrefix` lookups with no
translation — plus reading the core source for every API used. The items below
are what still has to be run on a real instance.

### Plugin

- [ ] `./launcher rebuild app` completes and the migrations create the tables
- [ ] `/ingenic/docs.json` resolves the first published series and its first chip
- [ ] `/ingenic/docs.json` returns 404 when no product is published
- [ ] `/ingenic/docs/<series>/<chip>.json` returns the latest version and page tree
- [ ] `/ingenic/docs/<series>/<chip>/<version>.json` resolves an explicit version
- [ ] a page not edited in a version resolves to the version that last changed it
- [ ] unknown series, chip, version or page returns 404
- [ ] unpublished pages are absent from the tree and 404 when requested directly
- [ ] `/ingenic/docs-search` finds a phrase in a page body
- [ ] `/ingenic/downloads` filters correctly and returns filter options
- [ ] a `login_form` resource refuses the file until a profile is stored
- [ ] a `login_form_request` resource refuses the file until a grant exists
- [ ] approving a request creates a grant and emails the team address
- [ ] revoking a grant closes that resource and leaves the others open
- [ ] `/ingenic/downloads/:id/file` streams the file and never exposes its path
- [ ] `/ingenic/boards` returns only published boards, and filters by series and chip
- [ ] a board reads its chip name from the tree and survives that chip's deletion
- [ ] a post moves its author's balance, and deleting it leaves both the award and
      the reversal in the ledger
- [ ] a priced resource refuses the file when the balance is short, and charges once
- [ ] a priced resource is never charged when the file turns out to be missing
- [ ] `/ingenic/points` shows the reader their own history and nobody else's
- [ ] `Ingenic::Points.rebuild!` corrects a balance that has been edited by hand
- [ ] malformed `ingenic_nav_items` / `ingenic_homepage_blocks` /
      `ingenic_developer_form_fields` degrade to an empty list instead of raising
- [ ] `bundle exec rspec plugins/discourse-ingenic/spec` passes

### Theme

- [ ] theme installs from git and compiles without JS or SCSS errors
- [ ] the Developer Center section appears below All categories, and in the mobile drawer
- [ ] `ingenic_sidebar_position=right` moves the sidebar, above `md` only
- [ ] `ingenic_sidebar_width` changes the column width
- [ ] `ingenic_nav_order=first` puts the Ingenic section above Discourse's sections
- [ ] reordering `ingenic_nav_items` reorders the sidebar after a reload
- [ ] an external nav entry is never highlighted; a docs entry stays highlighted
      on nested documentation pages
- [ ] homepage blocks render in the configured order
- [ ] disabling a block removes it without leaving a gap
- [ ] the docs picker opens on hover for the series flyout and by keyboard
- [ ] switching version keeps the reader on the equivalent page when it exists
- [ ] a page inherited from an earlier version says which version it came from
- [ ] opening `/ingenic/docs` lands on the first series with the canonical URL
- [ ] download centre filters combine correctly
- [ ] each access tier shows the right prompt and the right button
- [ ] a priced resource shows **Unlock for N points** when affordable and
      **Needs N points** when not, and the button never links where the endpoint refuses
- [ ] `/ingenic/points` renders the balance, the price list and the reader's history
- [ ] a points URL can be pasted into a fresh tab and opens directly
- [ ] board cards lay out on the grid, with the photo framed rather than oversized
- [ ] the board filters narrow the catalogue and can be cleared
- [ ] a board application button opens the external link in a new tab
- [ ] mobile layout drops to a single column at Discourse's own breakpoint

### Admin

- [ ] the documentation screen edits products, versions, the contents tree and page bodies
- [ ] overriding a page in a version, and reverting to inheritance, both persist
- [ ] the download screen uploads a file and sets one of the three access levels
- [ ] the queue approves and rejects an application
- [ ] the grant list revokes a grant
- [ ] the board screen creates, edits and withdraws a board, and files it against a chip
- [ ] the points screen reprices a rule, adjusts an account and rebuilds the balances
- [ ] a manager granted only `T33` cannot write to `T Series` or to `T32`, and
      cannot reach the points screen at all

### Integration

- [ ] Google, GitHub and email login still work
- [ ] no additional login providers appear
- [ ] content in a second locale renders for a reader whose interface language
      matches, and falls back per record where it does not

## Known risks

- **The migrations and the specs have not been run in this environment.** There
  is no Ruby, no database and no bundler on the machine the code was written on;
  the plugin's specs are written but unexecuted. The first rebuild is the real
  test.
- **The Chinese forum's signup form could not be read.** `forum.ingenic.com` is
  behind a login, so the field list behind "sign in and fill in your details"
  is a generic developer set rather than a copy of theirs. It is configurable
  through `ingenic_developer_form_fields`, so matching theirs is a settings edit
  once someone can read the original.
- **The board-store reference URL does not resolve.** The address supplied
  (`forum.ingeinc.com`) is a typo for a domain that does not exist, so the
  board card's fields were designed from the Chinese forum's board module
  instead of from that page.
- **The homepage renders through the `before-topic-list` outlet** and hides
  itself on every route except `/`. Giving it a dedicated route is the natural
  next step once this is running.
