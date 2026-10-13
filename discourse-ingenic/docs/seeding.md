# Seeding documentation, downloads and boards

Content is stored in the plugin's own tables. Normal editing happens in
**Admin → Plugins → Ingenic**; the console is for the first import and for bulk
work. Both go through the same models, so nothing here can create a row the
management pages would not.

```bash
cd /var/discourse
./launcher enter app
rails c
```

## The product tree

Everything else hangs off this, so it comes first. A product is either a
`series` or a `chip`, and the shape is enforced in the database: a series has no
parent, a chip has a series as its parent. `position` orders both levels.

The distinction is load-bearing. The documentation's two-level picker, the
download centre's series and chip filters and the board catalogue all read it,
so a tree built the wrong way round shows up as filters that find nothing.

```ruby
series = IngenicDocProduct.create!(
  slug: "t-series",
  name: "T Series",
  kind: "series",
  locale: "en",
  description: "Vision SoCs for cameras and set-top boxes",
  position: 0,
)

chip = IngenicDocProduct.create!(
  slug: "t32pro",
  name: "T32Pro",
  kind: "chip",
  parent: series,
  locale: "en",
  position: 0,
)
```

## Documentation

Versions hang off a chip, and pages hang off a version. `parent_id` on a page
builds the sidebar tree, so a page with children becomes a collapsible group.

```ruby
latest = IngenicDocVersion.create!(
  product: chip,
  slug: "2.1.0",
  label: "2.1.0",
  locale: "en",
  latest: true,
  released_on: Date.new(2026, 9, 1),
  position: 0,
)

previous = IngenicDocVersion.create!(
  product: chip,
  slug: "2.0.0",
  label: "2.0.0",
  locale: "en",
  released_on: Date.new(2026, 3, 1),
  position: 1,
)

overview = IngenicDocPage.create!(
  version: previous,
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
  parent: nil,
  slug: "quick-start",
  title: "Quick Start",
  locale: "en",
  position: 1,
  body: "How to build and flash your first image.",
)
```

### Version inheritance

A version stores only the pages that were edited for it. `overview` above was
written for 2.0.0 and never touched in 2.1.0, so 2.1.0 shows it anyway — the
resolver walks the versions oldest first and the newest definition of each slug
wins. Publishing a new version therefore does not mean duplicating the whole
manual and then keeping every copy in step.

The order is the `position` column, lowest first. Moving a version changes what
inherits from what, which is the whole mechanism: a version placed below 2.0.0
would inherit from nothing.

A page that exists in one version while its parent exists only in an earlier one
is placed under that parent, so overriding a single page does not detach it from
the tree.

### URLs

`/ingenic/docs/<series>/<chip>/<version>/<page>`, with everything after the
series optional. Missing segments resolve to the first published entry at that
level — the lowest `position` — and `latest` is an alias for the version flagged
`latest: true`. So `/ingenic/docs` opens the first series' first chip, and
`/ingenic/docs/t-series` opens the first chip in T Series.

Note that the first segment is always read as a series. `/ingenic/docs/t32pro`
does not open the chip `t32pro`; it looks for a series with that slug, finds
none, and falls back to the first series. Link to `/ingenic/docs/t-series/t32pro`.

To link a page to an existing forum discussion, set `topic_url`:

```ruby
overview.update!(topic_url: "/t/getting-started-with-t32pro/123")
```

## Downloads

The classifications are a table rather than a fixed list, so they can be added
to and renamed from **Ingenic → Downloads → Classifications**. The migration
seeds the list the plugin shipped with — `sdk`, `firmware`, `manual`,
`datasheet`, `toolchain`, `example`, `release_notes`, `other` — as rows, so the
usual case is to pick one rather than create one.

```ruby
sdk = IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en")
```

A resource either points at a file held elsewhere or has one uploaded against
it. For a file held elsewhere:

```ruby
IngenicDownload.create!(
  product_slug: "t32pro",
  category: sdk,
  version: "2.1.0",
  locale: "en",
  name: "T32Pro SDK 2.1.0",
  description: "Linux SDK including toolchain and examples.",
  platform: "Linux",
  architecture: "x86_64",
  access_level: "public_login",
  file_url: "https://download.ingenic.com/t32pro/sdk-2.1.0-en.tar.gz",
  file_size: "1.4 GB",
  file_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
  released_on: Date.new(2026, 9, 1),
)
```

`product_slug` is the chip's slug from the tree, so a resource filed against a
series-wide product should use the series' slug instead.

`access_level` is one of `public_login` (sign in), `login_form` (sign in and
have developer information on file) or `login_form_request` (sign in, have
information on file, and have an application approved). The default is
`public_login`.

`file_url` is never sent to the browser by the listing, whatever the level —
the page shows the plugin's own endpoint and the endpoint decides. Uploading
instead is the better choice for anything gated: an address on object storage
is an address anyone holding it can fetch.

A file uploaded through the management page is written under
`ingenic_download_storage_path` and recorded as `storage_path` plus
`original_filename`. Doing that from the console means going through the same
helper the controller uses:

```ruby
stored = Ingenic::DownloadStorage.store(uploaded_file)
resource.update!(
  storage_path: stored[:path],
  original_filename: uploaded_file.original_filename,
  file_sha256: stored[:sha256],
  file_size: stored[:size],
  file_url: nil,
)
```

### Applications and grants

An application is a row in `ingenic_download_requests`; approving it issues a
row in `ingenic_download_grants`. Grants have no end date: once an application
is approved the resource stays available to that account. What says a file was
actually collected is the log, not the grant.

```ruby
request = IngenicDownloadRequest.create!(user: someone, download: resource)
request.approve!(admin, note: "welcome")

IngenicDownloadGrant.issue!(someone, resource, granted_by: admin)
IngenicDownloadGrant.find_by(user: someone, download: resource).revoke!(admin)
```

The same actions are on **Ingenic → Downloads → Applications** and **Grants**,
and the record of who downloaded what is on **Ingenic → Downloads → Log**.

## Development boards

A board belongs to one chip in the tree, which is what lets the catalogue filter
by series as well as by chip. The link is optional — a board can be listed
before its chip exists — but a board linked to a series rather than a chip is
refused, because it would then appear under every chip in that series.

```ruby
IngenicBoard.create!(
  slug: "t32pro-evk",
  name: "T32Pro EVK",
  product: chip,
  locale: "en",
  description: "Evaluation kit for the T32Pro series.",
  specs: "2 GB DDR3 · dual Gigabit Ethernet · camera interface",
  image_url: "https://download.ingenic.com/boards/t32pro-evk.png",
  documentation_url: "/ingenic/docs/t-series/t32pro",
  application_url: "https://www.ingenic.com.cn/apply?board=t32pro-evk",
  purchase_url: "https://www.ingenic.com.cn/buy?board=t32pro-evk",
  position: 0,
)
```

`chip` is filled in from the linked product, so it does not need setting — it
stays a column because a board can be listed before its chip exists. Both
`application_url` and `purchase_url` are outbound links, rendered with
`rel="noopener noreferrer"` in a new tab. `application_url` is required and
draws the apply button; `purchase_url` is optional and draws **Buy now** — not
every board is sold, and a board that is lent on application has nowhere to buy.

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

Products, versions, pages, resources and boards all work this way. The product
tree itself is per-locale too: a chip row carries the language of its name, so a
translated chip is a second row under the same parent rather than a translation
of the first.
