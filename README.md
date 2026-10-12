# Ingenic English Forum

First version of the Ingenic English Discourse forum implementation.

This repository contains two independent Discourse installable pieces:

- `discourse-ingenic/` — plugin: documentation products, versions, pages,
  downloads, development boards and JSON endpoints.
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

The first version stores documentation and development-board records in the
plugin's own tables. The initial content workflow uses the Rails console; see
[`discourse-ingenic/docs/seeding.md`](discourse-ingenic/docs/seeding.md).

The current version does not yet include an admin CRUD interface for editing
products, versions, pages or boards. That is a planned next-stage improvement.

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
