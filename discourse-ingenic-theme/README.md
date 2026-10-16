# discourse-ingenic-theme

Theme for the Ingenic community forum. Pairs with the `discourse-ingenic`
plugin, which supplies the documentation, download and development board data
this theme renders.

It is deliberately **not** a copy of any existing Discourse theme. The layout is
built from Discourse's public theme APIs so it keeps working across upgrades.

## What it provides

- a **Developer Center** group in the sidebar, registered as a real Discourse
  sidebar section, so it inherits the mobile drawer, the section filter, the
  collapse state and active-link handling that core already implements — and so
  it can sit inside the sidebar rather than beside it. Discourse's own Topics,
  More and All categories sections are left exactly as they are.
- admin-configurable navigation items (label, icon, target, order, visibility)
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
| `ingenic_nav_order` | `first` puts the Ingenic navigation above Discourse's own sidebar sections |
| `ingenic_nav_title` | Optional heading above the navigation entries; empty renders a plain list |
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
edited in those two places and nowhere else. The accent is checked against WCAG
AA on white: `#1976d2` is 4.6:1, which is why it is that depth of blue rather
than a lighter, prettier one — a sky blue that passes as a link colour on white
is darker than a sky blue that only fills buttons.

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
  "position": 3,
  "enabled": true,
  "external": false
}
```

Use `"category": "technical-discussions"` instead of `href` to point at a
Discourse category; it resolves to the category route automatically.

Left empty, the theme ships its own list: Documentation, Downloads, Development
Boards and Points. A configured list **replaces** that one wholesale rather than
merging with it, so a site that configured its navigation before Points existed
has no Points entry and will not grow one — add it, or clear the setting.

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

Supported block types: `search`, `announcements`, `discussions`, `downloads`,
`boards`, `html`.

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
