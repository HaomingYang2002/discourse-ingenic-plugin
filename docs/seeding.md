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

## The forum sections

Not every section of the site is content in the plugin's tables: Official
Announcements, Technical Discussions and Open Source are ordinary Discourse
categories, because they are places people post. The navigation links to them,
and a fresh install has no categories at all, so they arrive through a rake task
rather than through the console:

```bash
cd /var/discourse
./launcher enter app
rake ingenic:seed_categories
```

Open Source is a section holding two sub-forums rather than a place to post:

| Section | Parent | Who may start a topic |
| --- | --- | --- |
| Official Announcements (`official-announcements`) | — | Staff |
| Technical Discussions (`technical-discussions`) | — | Everyone |
| Open Source (`open-source`) | — | Nobody: it is a container |
| Third-Party Open Source (`third-party`) | `open-source` | Everyone |
| Official Open Source (`official`) | `open-source` | Administrators only |

A second run leaves categories that already exist exactly as the forum has them —
renaming, re-colouring and re-parenting included. Permissions are the one thing a
re-run will write, and only when asked:

```bash
rake ingenic:seed_categories[permissions]
```

Do that after changing the table above, or to repair an Official Open Source that
somebody can post into. `rake ingenic:doctor` reports any of the five that is
missing (`Ingenic::ForumCategories.missing` from the console gives the same list).

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

`family` is the catalogue's top-level line: `chip` (the default) or
`algorithm`. An algorithm is offered across chips and is not filed under one,
so it leaves `product_slug` empty:

```ruby
algorithms = IngenicDownloadCategory.find_or_create_by!(name: "algorithm", locale: "en")

IngenicDownload.create!(
  family: "algorithm",
  category: algorithms,
  version: "2.1",
  locale: "en",
  name: "Smart H.264 encoder library",
  platform: "Linux",
  access_level: "public_login",
  file_url: "https://download.ingenic.com/algorithms/h264-2.1.tar.gz",
)
```

The download centre's series row is drawn from the product tree, with the
algorithm line as one option beside the chip series. The option appears only
once a published `algorithm` resource exists. If the tree has a series whose
slug is `algorithm`, its name is used as the option's label, so it can be
renamed on the documentation screen; otherwise the interface's own "Algorithms"
string is used. Choosing it hides the model row and narrows the resource types
to the ones algorithm resources actually use.

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
  details: "See the [T32Pro documentation](/ingenic/docs/t-series/t32pro).",
  specs: "2 GB DDR3 · dual Gigabit Ethernet · camera interface",
  image_url: "https://download.ingenic.com/boards/t32pro-evk.png",
  application_url: "https://www.ingenic.com.cn/apply?board=t32pro-evk",
  purchase_url: "https://www.ingenic.com.cn/buy?board=t32pro-evk",
  sold_out: false,
  position: 0,
)
```

`chip` is filled in from the linked product, so it does not need setting — it
stays a column because a board can be listed before its chip exists. Both
`application_url` and `purchase_url` are outbound links, rendered with
`rel="noopener noreferrer"` in a new tab. Neither is required: the card always
draws **Apply** and **Buy now** and grays the one without an address.
`sold_out` is a separate switch — it stamps the card and disables both buttons
while leaving the links in place. `details` is Markdown shown in the dialog.

## Points

Points are what members earn by contributing, and what a resource can cost to
unlock. Three tables: `ingenic_point_rules` (the price list),
`ingenic_point_entries` (the ledger — one append-only row per movement) and
`ingenic_point_balances` (a running total per account, derived from the entries
and rebuildable from them).

The migration seeds four rules, which is where the plugin starts rather than
where it has to stay:

| `event` | Points | Label |
| --- | ---: | --- |
| `topic_created` | 5 | Opening a discussion |
| `post_created` | 2 | Answering in one |
| `like_received` | 1 | A post of yours being liked |
| `solution_accepted` | 15 | Your answer being accepted |

The list of events is the plugin's — each one needs somewhere in Discourse that
reports it — and the numbers, the wording and the order are yours. All four are
editable on **Ingenic → Points**, and the usual way to change them is there
rather than here:

```ruby
IngenicPointRule.for(IngenicPointRule::SOLUTION_ACCEPTED).update!(points: 25)

# Retire an action without deleting its row: the ledger keeps referring to it.
IngenicPointRule.for(IngenicPointRule::LIKE_RECEIVED).update!(published: false)
```

`IngenicPointRule.amount_for(event)` is what one occurrence is worth right now,
and reads as `0` for a retired rule or one that was never seeded, which is what
makes retiring an action safe.

### The ledger

Nothing writes an entry by hand. Every movement goes through `Ingenic::Points`,
which writes the entry and moves the balance in the same transaction:

```ruby
Ingenic::Points.award(user: someone, event: IngenicPointRule::TOPIC_CREATED, subject: post)
Ingenic::Points.reverse(entry, reason: "the post went away", by: admin)
Ingenic::Points.reverse_subject(post, reason: "the post went away")
Ingenic::Points.spend(user: someone, points: 50, subject: resource, reason: "unlocked")
Ingenic::Points.adjust(user: someone, points: 25, note: "helped with a bug", by: admin)
Ingenic::Points.total_for(someone)          # their balance
Ingenic::Points.unlocked_download_ids(someone)
Ingenic::Points.rebuild!                    # re-derives every balance
```

An award is recorded once per subject: the thing it is for is part of the unique
index, so the same event arriving twice produces nothing the second time rather
than a second helping. `award` returns the entry, or `nil` when there was
nothing to record — no rule, a rule priced at nothing, points switched off, or
this exact thing already rewarded. `nil` is the ordinary answer, not a failure.

`spend` answers rather than raises, because the caller is a download and "you
have not got enough" is a state to show: `:spent`, `:already` (bought before, so
nothing more is owed) or `:insufficient` (nothing written).

An entry is never edited. Taking an award back writes a second, opposite entry,
so the ledger says what happened — points were given, and then taken back — and
the original award is still there to be read.

`ingenic_point_balances` is a cache. If it ever disagrees with the entries —
after a restore, or after somebody has been editing rows — `Ingenic::Points.rebuild!`
puts it back and reports how many rows it corrected. That is also why a balance
can be trusted without being the authority.

### What a resource costs

Pricing a resource is a column on the resource itself. Zero, the default, means
free:

```ruby
resource.update!(point_cost: 50)
```

The price is asked *after* the access level, never instead of it: a
`login_form_request` resource that costs 50 points still sends a new visitor
through sign-in, developer details and approval before it mentions points. The
listing draws **Unlock for N points** for an account that can afford it and
**Needs N points** for one that cannot, and the purchase is recorded as an entry,
so a second download of the same resource costs nothing.

### The member's page

`/ingenic/points` shows the signed-in member their balance, the price list and
their own history. It is read-only from the front end, and it shows nobody
else's rows. Reaching it from the navigation is the theme's job, not the
plugin's: the theme ships a Points entry, and a site that has configured its own
`ingenic_nav_items` needs to add one itself, because a configured list replaces
the shipped one wholesale.

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
