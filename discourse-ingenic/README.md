# discourse-ingenic

Ingenic community extension for Discourse. It keeps the forum as it is —
topics, categories, tags, search and the native sidebar all stay core's own —
and adds a developer area below them:

- **Online documentation**: chip-scoped, with a series → chip product picker, a
  version selector, full-text search, a collapsible contents tree, and page
  bodies authored in Markdown. A version only stores the pages that changed in
  it; everything else is inherited from the version before, and the reader says
  which version a page actually came from.
- **Download centre** for SDKs, firmware, manuals, datasheets and toolchains,
  behind three tiers of access (see below), with the files themselves stored
  outside `public/` and streamed through the plugin once access is checked.
- **Development board catalogue**, with each board filed against a chip in the
  product tree and an action button that links out to the Ingenic
  application/purchase page.
- **Scoped management**: a manager can be granted one product family and edit
  only that, enforced on the server for every write.
- Read-only JSON endpoints under `/ingenic` that the companion theme renders,
  plus the admin screens that manage all of the above.

It intentionally does **not** touch authentication. Google, GitHub and email
login stay exactly as configured in Discourse core.

## Access tiers

Each download record carries one of three levels:

| Level | What a visitor does | What the server requires |
| --- | --- | --- |
| `public_login` | Signs in, then downloads | A signed-in account |
| `login_form` | Signs in and submits the developer information form once | A signed-in account with a stored profile |
| `login_form_request` | Signs in, submits the form, then applies for that resource | A signed-in account with a stored profile **and** a live grant for that resource |

An application emails the team address in `ingenic_download_admin_email` and
appears in the admin queue, where it is approved or rejected. Approving creates
a grant, which can be revoked — per resource and per account, so an approval for
one SDK does not open the rest.

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
development boards, downloads, the application queue, grants and permissions.

The documentation screen edits the contents tree, decides which node an article
belongs to, and edits articles under any version. A version that has not edited
a page inherits it from the version before, and the screen says so: each page
shows the version it currently comes from, with controls to override it in this
version or drop the override and go back to inheriting.

A permission can be granted to a user or a group. A product permission is
inherited by its versions and pages; a page permission is inherited only by that
page's children. The server checks every create, read, update, delete and
permission mutation, so hiding a button in the admin UI is not the authorization
boundary.

The product tree is explicit about its two levels: create `T Series` as a
`series` and `T33` as a `chip` under it. The same tree drives the documentation
picker, the download filters and each board's chip, so the three cannot disagree
about what a chip is called. Granting `T Series` lets a manager edit its
descendants; granting `T33` does not grant access to its siblings or its parent.

## Endpoints

Public, read-only except where noted:

| Method | Path | Description |
| --- | --- | --- |
| GET | `/ingenic/docs` | The first published series, its first chip, and that chip's default version |
| GET | `/ingenic/docs/*path` | `/<series>[/<chip>[/<version>[/<page>]]]` — each level filled in from the one before when omitted |
| GET | `/ingenic/docs-search` | Full-text search across the documentation |
| GET | `/ingenic/downloads` | Download records; accepts `product`, `kind`, `version`, `platform` |
| GET | `/ingenic/downloads/:id/file` | The file itself, streamed after the access check |
| POST | `/ingenic/downloads/profile` | Stores the developer information form (signed in) |
| POST | `/ingenic/downloads/:id/request` | Applies for an access-restricted resource (signed in) |
| GET | `/ingenic/boards` | Published development boards; accepts `series` and `chip` |

The two POSTs need a signed-in account; everything else is readable signed out.
Each GET answers two ways — JSON when the frontend asks for it with
`Accept: application/json`, and the application shell when a visitor opens or
refreshes the address directly. That is what makes a documentation or download
link shareable rather than only reachable by clicking through the app.

The documentation paths are one Rails glob rather than four nested routes: the
controller splits the path itself, so adding a level later does not mean
touching the route table. The bare `/ingenic/docs` is declared separately
because a glob only matches when the slash is present. Search is a sibling of
the glob rather than a path inside it, so a chip called `search` stays usable.

## Site settings

| Setting | Purpose |
| --- | --- |
| `ingenic_enabled` | Master switch |
| `ingenic_nav_items` | JSON array — sidebar entries, their order, icon, target and visibility |
| `ingenic_homepage_blocks` | JSON array — which homepage blocks render and in what order |
| `ingenic_default_locale` | Fallback locale for documentation, downloads and boards |
| `ingenic_docs_discussion_category` | Category used for "Discuss in forum" when a page has no linked topic |
| `ingenic_download_storage_path` | Where uploaded SDKs and firmware are written. Must be outside `public/` |
| `ingenic_download_admin_email` | Address that receives an application for a restricted download |
| `ingenic_developer_form_fields` | JSON array describing the developer information form |

The three JSON settings accept the shapes documented inline in
`config/settings.yml`. The locale setting offers only the languages this
Discourse can serve, so enabling a language in Discourse makes it selectable
here without touching the file.

## Data model

```
ingenic_doc_products      series and chips, per locale, one tree with two levels
ingenic_doc_versions      versions of a chip, one flagged `latest`
ingenic_doc_pages         the pages a version actually changed, with parent_id
                          forming the contents tree
ingenic_downloads         downloadable resources and their access level
ingenic_developer_profiles  the developer information form, one per account
ingenic_download_requests   applications, with their review state
ingenic_download_grants     approvals, per account and per resource
ingenic_boards            development boards, filed against a chip
ingenic_permissions       scoped grants to a user or group
```

`ingenic_doc_pages` holds one row per page **per version it changed in**, not
per version: a version with no row for a slug inherits the nearest earlier
version that has one. That is what keeps a documentation set from multiplying
by its version count.

Every content table carries a `locale` column, so additional languages can be
enabled later without a schema migration. Codes are Discourse's own (`zh_CN`,
`pt_BR`), because they are compared against `I18n.locale` — the language the
reader picked in their preferences. A request resolves content in the reader's
language first and falls back to `ingenic_default_locale` per page, so a
half-translated version still renders and a page appears once in the tree, not
once per locale.

## Adding content

Documentation pages are authored as Markdown in `ingenic_doc_pages.body` and are
rendered through `PrettyText.cook`, so they support the same formatting as
forum posts.

See `docs/seeding.md` for a worked example.

## Development

There is no local Discourse checkout in this repository. To run the plugin test
suite you need a Discourse development environment — either a checkout of
Discourse `2026.10.0-latest` with the plugin under `plugins/`, or its dev
container:

```bash
bin/docker/boot_dev --init    # from a Discourse checkout
bin/docker/rspec plugins/discourse-ingenic/spec
```

## Support

Contact the Ingenic community team.
