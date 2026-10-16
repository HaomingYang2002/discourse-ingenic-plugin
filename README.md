# Ingenic English Forum

First version of the Ingenic English Discourse forum implementation.

This repository contains two independent Discourse installable pieces:

- `discourse-ingenic/` — plugin: documentation products, versions, pages,
  downloads, development boards, a points ledger, bounties and JSON endpoints.
- `discourse-ingenic-theme/` — theme: Ingenic layout, native Discourse sidebar
  navigation, homepage blocks and documentation UI.

The plugin and theme are designed for Discourse `2026.10.0-latest` and were
built without copying any closed-source theme or plugin.

## Install

Read [`DEPLOY.zh-CN.md`](DEPLOY.zh-CN.md) for the Chinese deployment guide, or
[`DEPLOY.md`](DEPLOY.md) for the English guide.

The plugin is installed by Discourse Docker on the server and requires an app
rebuild when installed through `app.yml`. The theme is uploaded in the Discourse
admin UI as a theme zip.

## Content

Documentation, download, development-board and points records live in the
plugin's own tables. Bounties (高分悬赏) are opened by members on their own topics
rather than by the team, so they have no admin screen: the points screen shows how
much is set aside behind the standing offers. Normal editing is available from
**Admin → Plugins → Ingenic**; the Rails console workflow in
[`discourse-ingenic/docs/seeding.md`](discourse-ingenic/docs/seeding.md) — or its
Chinese counterpart
[`seeding.zh-CN.md`](discourse-ingenic/docs/seeding.zh-CN.md) — remains useful
for initial imports and bulk setup.

The management UI supports product/version/page records, development boards,
download resources with their application queue and grants, points rules and
adjustments, and user/group-scoped permissions. Server-side authorization applies
the assigned product or page scope to every write operation.

## Scope

Authentication is not changed. Google, GitHub and email remain controlled by
Discourse core. The implementation is English-first and keeps locale fields and
translation namespaces ready for additional languages.

## Development

Run the static validators from the parent development workspace when available:

```bash
node .tools/check/validate.mjs discourse-ingenic-theme/javascripts discourse-ingenic
node .tools/check/rubycheck.mjs discourse-ingenic
```

The first release was statically validated against a Discourse
`2026.10.0-latest` checkout. RSpec and a full Discourse asset build must still
be run in a real Discourse environment.
