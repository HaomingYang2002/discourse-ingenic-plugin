# discourse-ingenic-theme

Theme for the Ingenic community forum. Pairs with the `discourse-ingenic`
plugin, which supplies the documentation, download, development board and bounty
data this theme renders.

It is deliberately **not** a copy of any existing Discourse theme. The layout is
built from Discourse's public theme APIs so it keeps working across upgrades.

## What it provides

- the sidebar's Ingenic navigation, in three groups: the forum at the top
  (start a post, the front page, the forum's own sections), the developer
  resources under their own heading (Documentation, Open Source, Downloads,
  Development Boards), and what a member has earned or set aside at the bottom
  (Bounties, Points). Only the middle group is drawn with a heading; the outer
  two are plain lists, which is what keeps Bounties and Points out of the
  developer resources. Each group is registered as a real Discourse sidebar
  section, so they inherit the mobile drawer, the section filter, the collapse
  state and active-link handling that core already implements — and sit inside
  the sidebar rather than beside it. Discourse's own categories, tags and
  visitor-made sections are left exactly as they are.
- admin-configurable navigation items (label, icon, target, group, order,
  visibility)
- a sidebar that can be moved to either side and resized from theme settings
- an admin-configurable homepage assembled from blocks
- a documentation reader: a two-level product picker (series, then a flyout of
  its chips), a version selector, full-text search, a collapsible contents tree,
  the rendered Markdown body and previous/next navigation
- a download centre with product / type / version / platform filters, showing
  the right prompt and button for each of the three access tiers — and, for a
  resource that is priced, **Unlock for N points** when the reader can afford it
  and **Needs N points** when they cannot
- a development board catalogue with series and chip filters and outbound
  application links
- a points page at `/ingenic/points`, showing the reader their balance, what the
  forum pays for and their own history — read-only, and nobody else's rows
- a **高分悬赏** board at `/ingenic/bounties`: what is on offer across the forum,
  richest first, with the question, the amount and how long is left. On the topic
  itself the same feature is a banner above the posts — the standing offer, with
  a way to withdraw it for whoever may, or, once an answer has been accepted,
  what was paid and to whom
- English strings today, structured so more locales can be added later

## Installation

The theme is installed from a Git repository:

```bash
cd /var/discourse
./launcher enter app
rails c
```

```ruby
Theme.create_from_git_url(
  url: "https://github.com/<org>/discourse-ingenic-theme.git",
  branch: "main"
)
```

Or through the admin UI: **Admin → Customize → Themes → Install → From a git
repository**.

After installing, set it as the default theme and select the **Ingenic Light**
color scheme.

## Theme settings

| Setting | Purpose |
| --- | --- |
| `ingenic_locales` | Languages the header's language switcher offers, in order. Hidden while fewer than two are listed. |
| `ingenic_sidebar_width` | Width of the navigation sidebar on desktop, in pixels |
| `ingenic_sidebar_position` | `left` or `right` |
| `ingenic_nav_order` | `first` puts the Ingenic navigation above Discourse's own sidebar sections (categories, tags, the visitor's own) |
| `ingenic_nav_title` | Heading over the developer-resources group; empty reads *Developer Resources* (开发者资源 in Chinese). The two lists around it are heading-less by design. |
| `ingenic_hero_title` | Optional headline above the homepage blocks |
| `ingenic_hero_subtitle` | Optional supporting line under the headline |

The language switcher in the header also needs two of Discourse's own site
settings: `allow_user_locale` (on by default) and `set_locale_from_cookie`.
Without the second one a signed-out reader's choice goes into a cookie the
server will not read back, which looks like a switch that does nothing.

There is no setting for showing or hiding the sidebar or for collapsing it:
Discourse already has both in the interface, and a second control would fight
with the one visitors know. The accent colour is not a theme setting either —
it is the **Ingenic Light** colour scheme this theme ships, which the standard
admin colour pickers edit.

## Colours

The palette is a light sky blue, and it lives in two places:

- **`about.json`** — the **Ingenic Light** colour scheme: the accent (`tertiary`),
  the text colour (`primary`), the header, the search highlight and the semantic
  red, green and pink. These are the ones an admin may reasonably want to change,
  and Discourse already has pickers for them.
- **`common/common.scss`**, in the `:root` block — the tints a colour scheme has
  no slot for: the wash behind a notice, the hairline around it, the pale blue a
  picture sits on until it loads. `--ingenic-surface-tint` and
  `--ingenic-surface-border` are what the theme's own surfaces use.

Nothing outside that block names a colour, so the shade of the whole theme is
edited in those two places and nowhere else.

The accent is `#2FC1FF`: a sky blue a shade paler than `#0CBBFF`, which is the
shade the theme is meant to have. That shade is a surface, not a letter — as
text on white it is 2.4:1, and white on it is 1.9:1 — so the two places where the
accent has to be read are named separately:

- `--ingenic-link`, `#0f7fa8` — the same hue one step down, 4.5:1 on white. It
  is what links, hover states and the eyebrow use, and it is also written into
  `--d-link-color` and `--d-nav-color--*` so the whole forum, not just this
  theme's own components, keeps legible links.
- `--ingenic-accent-ink` — the colour that goes *on* an accent fill. It resolves
  to `primary`, so a filled button is a pale sky with navy words on it rather
  than white words that cannot be read. Written into `--d-button-primary-*`.

Both follow the scheme: move `tertiary` and they move with it, because they are
the same hue either side of it. The theme's stylesheet is loaded after the colour
scheme's, so the `:root` block here overrides the scheme's own variables.

Typography and spacing are Discourse's own scale (`--font-up-*`, `--space-*`,
`--font-family`), not the theme's invention, so they follow whatever the site's
font settings say and match other Discourse sites without a second style guide.

## Layout configuration

Navigation items and homepage blocks live in the **plugin** settings
(`ingenic_nav_items` and `ingenic_homepage_blocks`) so that content editors can
change them without touching the theme. Both are shipped to the client through
the site serializer.

Navigation item shape:

```json
{
  "key": "documentation",
  "label": "Documentation",
  "icon": "book",
  "href": "/ingenic/docs",
  "section": "resources",
  "position": 4,
  "enabled": true,
  "external": false
}
```

`section` is which of the three sidebar groups the entry is drawn in: `forum`
(the plain list at the top), `resources` (the group under the theme's heading) or
`member` (the plain list at the bottom). `position` orders entries within their
own group; the groups themselves always come in that order. An unknown group name
is read as `forum`, so a typo moves a row rather than losing it.

Use `"category": "technical-discussions"` instead of `href` to point at a
Discourse category; it resolves to the category route automatically.

Left empty, the theme ships its own list in the same three groups:
New Post, Home, Official Announcements, Technical Discussions · Online
Documentation, Open Source, SDK & Firmware Downloads, Development Boards ·
Bounties, Points. A configured list **replaces** that one wholesale rather than
merging with it, so a site that configured its navigation before the bounty board
existed has no Bounties entry and will not grow one — add it, or clear the
setting.

A link stays highlighted for the whole subtree it points at, so
`/ingenic/docs/t32pro/2.1.0/overview` still shows Documentation as active.
External links are never highlighted.

Homepage block shape:

```json
{
  "type": "discussions",
  "position": 2,
  "limit": 10,
  "category": "technical-discussions",
  "title": "Latest discussions",
  "enabled": true
}
```

Supported block types: `announcements`, `discussions`, `downloads`, `boards`,
`bounties`, `promotions`, `categories`, `html`.

The `categories` block is the one that makes the page a front page rather than a
digest: it lists the forum's sections as cards, each linking into its category.
Give it `"categories": ["announcements", "technical-discussions"]` to name the
ones to show, in the order to show them; leave that out and it takes the busiest
top-level sections up to `limit` (default 8). `"show_all": false` removes the
**All sections** link that otherwise sits at the end of the block's heading.

The `bounties` block lists the richest standing offers, up to `limit` (default
5), each linking into the question that carries it. It draws nothing at all while
nothing is on offer — no heading, no empty row — which is what lets it sit on the
front page of a forum that has not taken to bounties yet.

Left empty, the homepage shows the `categories` block with the `bounties` panel
underneath: the section grid, which is what a front page wants before anyone has
decided which parts of the forum deserve a row, plus the one block that costs
nothing to leave on. Unlike the navigation list, the fallback is a fallback: a
configured list of blocks replaces it.

## The home page

The front page is not a page the theme draws over a topic list. It is a
**registered homepage**: the plugin offers it to Discourse as one of the
choices in `default_homepage`, and Discourse mounts it at `/` itself. That is
why choosing *Latest* no longer empties the page — the front page and the topic
lists are separate destinations rather than one page with a switch on it.

To use it, set the site's **`default_homepage`** setting (Admin → Settings →
Interface) to the Ingenic home page; the value stored is `ingenic-home`. The
option only appears in that list while the plugin is enabled, and a site that
has it selected falls back to the ordinary homepage if the plugin is switched
off. Its own address is `/ingenic/home`, so a link to it can be written down,
and refreshing it serves the page rather than redirecting to the latest topic.

The page is assembled in the browser from data the site already sends (the
category list in `site.json`, the homepage blocks from the plugin), so the
server action behind it renders nothing but the application shell. There is no
second copy of the categories to keep in step.

## Adding a language

Locale files live in `locales/`. Duplicate `locales/en.yml` as
`locales/<locale>.yml`, translate the values and keep the keys unchanged.
Discourse registers theme translations under the theme's own namespace, which is
why every lookup goes through `themePrefix` — a bare `i18n("ingenic.docs.version")`
would look in core translations and find nothing.

The file name must be a locale Discourse already serves (`zh_CN`, `pt_BR`), not
an invented one, or no visitor can select it.

Content-level translations are handled by the plugin, which stores a `locale`
per documentation page, download and board. Content uses the same locale codes,
so a translated page appears for a reader whose interface language matches, and
the default language fills in the rest.
