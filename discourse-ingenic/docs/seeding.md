# Seeding documentation, downloads and boards

Content is stored in the plugin's own tables. You can create it through the
Rails console inside the container.

```bash
cd /var/discourse
./launcher enter app
rails c
```

## Documentation

Create a product, then a version, then pages. `parent_id` builds the sidebar
tree, so a page with children becomes a collapsible group.

```ruby
product = IngenicDocProduct.create!(
  slug: "t32pro",
  name: "T32Pro",
  locale: "en",
  description: "T32Pro series development documentation",
  position: 0,
)

latest = IngenicDocVersion.create!(
  product: product,
  slug: "2.1.0",
  label: "2.1.0",
  locale: "en",
  latest: true,
  released_on: Date.new(2026, 9, 1),
  position: 0,
)

previous = IngenicDocVersion.create!(
  product: product,
  slug: "2.0.0",
  label: "2.0.0",
  locale: "en",
  released_on: Date.new(2026, 3, 1),
  position: 1,
)

overview = IngenicDocPage.create!(
  version: latest,
  slug: "overview",
  title: "Overview",
  locale: "en",
  position: 0,
  body: <<~MD,
    ## Chip introduction

    The T32Pro series is a highly integrated vision SoC.

    | Item | Value |
    | --- | --- |
    | CPU | ... |
  MD
)

IngenicDocPage.create!(
  version: latest,
  parent: overview,
  slug: "key-parameters",
  title: "Key parameters",
  locale: "en",
  position: 0,
  body: "Detailed parameter tables.",
)

IngenicDocPage.create!(
  version: latest,
  slug: "quick-start",
  title: "Quick Start",
  locale: "en",
  position: 1,
  body: "How to build and flash your first image.",
)
```

Visiting `/ingenic/docs/t32pro` now returns the latest version with its tree;
`/ingenic/docs/t32pro/2.0.0` returns the older version. `/ingenic/docs` on its
own redirects to the first published product — the one with the lowest
`position` — so navigation can point at a single stable URL.

To link a page to an existing forum discussion, set `topic_url`:

```ruby
overview.update!(topic_url: "/t/getting-started-with-t32pro/123")
```

## Downloads

Files are not uploaded to Discourse. Store them on object storage or a CDN and
record the URL here.

```ruby
IngenicDownload.create!(
  product_slug: "t32pro",
  kind: "sdk",
  version: "2.1.0",
  locale: "en",
  name: "T32Pro SDK 2.1.0",
  description: "Linux SDK including toolchain and examples.",
  platform: "Linux",
  architecture: "x86_64",
  file_url: "https://download.ingenic.com/t32pro/sdk-2.1.0-en.tar.gz",
  file_size: "1.4 GB",
  sha256: "0000000000000000000000000000000000000000000000000000000000000000",
  released_on: Date.new(2026, 9, 1),
)
```

`kind` must be one of: `sdk`, `firmware`, `manual`, `datasheet`, `toolchain`,
`example`, `release_notes`, `other`.

## Development boards

```ruby
IngenicBoard.create!(
  slug: "t32pro-evk",
  name: "T32Pro EVK",
  chip: "T32Pro",
  locale: "en",
  description: "Evaluation kit for the T32Pro series.",
  image_url: "https://download.ingenic.com/boards/t32pro-evk.png",
  documentation_url: "/ingenic/docs/t32pro",
  application_url: "https://www.ingenic.com.cn/apply?board=t32pro-evk",
  position: 0,
)
```

`application_url` is an outbound link and is rendered with
`rel="noopener noreferrer"` in a new tab.

## Adding a second language

Every row carries `locale`. To add Chinese documentation for the same product,
create rows with `locale: "zh_CN"`. Requests resolve content using the visitor
locale first and fall back to `ingenic_default_locale`, so a partially
translated product still renders.

Use Discourse's own spelling for the code — `zh_CN`, `pt_BR`, `zh_TW`, never
`zh-CN`. It is compared against `I18n.locale`, which is the language the visitor
picked under *Preferences → Interface language*, and a hyphenated code matches
nothing, so the row would be invisible.

A page can be translated one slug at a time. Where both `en` and `zh_CN` rows
exist for the same slug, the reader's language wins and the translated page
appears once in the tree; slugs with no translation fall back to
`ingenic_default_locale`. A product with no translated row at all still opens
in the default language.
