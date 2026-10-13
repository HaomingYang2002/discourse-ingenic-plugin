# discourse-ingenic

Ingenic community extension for Discourse. Adds:

- chip-scoped documentation with version selection and a nested page tree
- a download centre for SDKs, firmware, manuals and datasheets (metadata only —
  files stay on your object storage or CDN)
- development board listings whose action button links out to the Ingenic
  application/purchase page
- read-only JSON endpoints under `/ingenic` that the companion theme renders
- web management pages for documentation, development boards, and scoped content permissions

It intentionally does **not** touch authentication. Google, GitHub and email
login stay exactly as configured in Discourse core.

## Requirements

- Discourse `2026.10.0-latest` or later (developed against this version)
- The companion theme `discourse-ingenic-theme` for the UI

## Installation

Add the plugin to `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/<org>/discourse-ingenic.git
```

Then rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

After the rebuild the plugin runs its migrations automatically and the new
tables are created.

## Management

Administrators can open **Admin → Plugins → Ingenic** to manage documentation,
development boards, and permissions. A product permission is inherited by its
versions and pages; a page permission is inherited only by that page's children.
Permissions can be assigned to a user or group. The server checks every create,
read, update, delete, and permission mutation, so hiding a button in the admin UI
is not the authorization boundary.

The documentation model supports explicit product families and child products:
for example, create `T Series` as a parent product and `T33` as its child. Granting
`T Series` lets a manager edit its descendants, while granting `T33` does not grant
access to sibling products or the parent.

## Endpoints

| Method | Path | Description |
| --- | --- | --- |
| GET | `/ingenic/docs` | The first published product's default version and page tree |
| GET | `/ingenic/docs/:product` | Product with its default (latest) version and page tree |
| GET | `/ingenic/docs/:product/:version` | A specific version, or `latest` |
| GET | `/ingenic/docs/:product/:version/:page` | A single page plus previous/next navigation |
| GET | `/ingenic/downloads` | Download resources; accepts `product`, `kind`, `version`, `platform` |
| GET | `/ingenic/boards` | Published development boards |

All endpoints are read-only and require no authentication.

Each URL answers two ways: JSON when the frontend asks for it with
`Accept: application/json`, and the application shell when a visitor opens or
refreshes the address directly. That is what makes a documentation or download
link shareable rather than only reachable by clicking through the app.

The documentation paths are one Rails glob, not three nested routes: the
controller splits the path into product / version / page itself, so adding a
level later does not mean touching the route table. The bare `/ingenic/docs` is
declared separately because a glob only matches when the slash is present.

## Site settings

| Setting | Purpose |
| --- | --- |
| `ingenic_enabled` | Master switch |
| `ingenic_nav_items` | JSON array — left navigation items, their order, icon, target and visibility |
| `ingenic_homepage_blocks` | JSON array — which homepage blocks render and in what order |
| `ingenic_default_locale` | Fallback locale for documentation and downloads |
| `ingenic_docs_discussion_category` | Category used for "Discuss in forum" when a page has no linked topic |

Both JSON settings accept the shapes documented in `config/settings.yml`. The
locale setting offers only the languages this Discourse can serve, so enabling a
language in Discourse makes it selectable here.

## Data model

```
ingenic_doc_products   one row per chip family / product per locale
ingenic_doc_versions   versions of a product, one flagged `latest`
ingenic_doc_pages      pages with parent_id forming the sidebar tree
ingenic_downloads      downloadable resources (metadata only)
ingenic_boards         development boards and their outbound links
```

Every table carries a `locale` column, so additional languages can be enabled
later without a schema migration. Codes are Discourse's own (`zh_CN`, `pt_BR`),
because they are compared against `I18n.locale` — the language the reader picked
in their preferences. A request resolves content in the reader's language first
and falls back to `ingenic_default_locale` per page, so a half-translated
version still renders and a page appears once in the tree, not once per locale.

## Adding content

Documentation pages are authored as Markdown in `ingenic_doc_pages.body` and are
rendered through `PrettyText.cook`, so they support the same formatting as
forum posts.

See `docs/seeding.md` for a worked example.

## Development

There is no local Discourse checkout in this repository. To run the plugin test
suite you need a Discourse development environment:

```bash
bundle exec rspec plugins/discourse-ingenic/spec
```

## Support

Contact the Ingenic community team.
