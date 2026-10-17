# Ingenic Community Forum — Usage Guide

This guide is for everyone who uses the English Ingenic forum: members who read
documentation, download SDKs, ask questions or answer them, and administrators
who publish content and decide who may download what.

It covers what the forum does, how each feature is used, where the administrator
screens are, and which requirement each part of the site was built to satisfy.
It is the companion to:

- [`README.md`](../README.md) — architecture, endpoints and data model
- [`DEPLOY.md`](../DEPLOY.md) — installation, settings and rollback
- [`docs/seeding.md`](seeding.md) — bulk content import from the console

Chinese version: [`usage.zh-CN.md`](usage.zh-CN.md).

## Contents

1. [What this forum is](#1-what-this-forum-is)
2. [Requirements summary](#2-requirements-summary)
3. [Feature map](#3-feature-map)
4. [Getting started as a member](#4-getting-started-as-a-member)
5. [Online documentation](#5-online-documentation)
6. [Downloads](#6-downloads)
7. [Development boards and samples](#7-development-boards-and-samples)
8. [Points](#8-points)
9. [Bounties (高分悬赏)](#9-bounties-高分悬赏)
10. [MCP and the AI assistant](#10-mcp-and-the-ai-assistant)
11. [Administrator guide](#11-administrator-guide)
12. [Troubleshooting](#12-troubleshooting)
13. [Repository and support](#13-repository-and-support)

## 1. What this forum is

The Ingenic community forum is a standard Discourse forum with a developer area
added underneath it. Topics, categories, tags, search, notifications, flags and
the rest of the forum are Discourse's own; the extension adds four things that
are specific to Ingenic:

- **Chip documentation** that follows the product tree and is versioned.
- **A download centre** for SDKs, firmware, manuals and tools, with three levels
  of access and an approval workflow.
- **A catalogue of development boards and sample chips**, with application and
  purchase links.
- **A contribution economy** — points for helping, and bounties that let a
  member put points behind a question.

Two optional integrations connect the forum to AI tools: an **MCP server** page
and a **floating assistant**. Both depend on features that a site administrator
enables separately.

The forum is bilingual. The interface switches between English and Chinese in
the header, and documentation, downloads and board entries can each carry a
language. Authentication is untouched: the sign-in methods are whichever ones
the site has configured (email, Google, GitHub and so on).

## 2. Requirements summary

The project grew in stages. Each row is the requirement as it was agreed, what
was built for it, and where a reader can see it.

| # | Requirement | What was delivered | Where to see it |
| --- | --- | --- | --- |
| 1 | Keep Discourse native; add an Ingenic developer area rather than replace the forum | Native topics, categories, tags and sidebar kept; plugin plus theme installed alongside | The whole forum |
| 2 | Online documentation with a product hierarchy | Series → chip product tree, versioned pages, Markdown reader, contents tree, full-text search | `/ingenic/docs` |
| 3 | Versions must not duplicate every page | A version stores only the pages it changed; other pages are inherited from the nearest earlier version | Version selector; Admin → Documentation |
| 4 | Manage documentation from the admin UI | Create series, chips, versions and pages; reorder; rename; override or restore inheritance | Admin → Plugins → Ingenic |
| 5 | SDK/firmware downloads with three access levels | Sign-in, developer information, and application plus approval; files stored outside the web root and streamed after a check | `/ingenic/downloads` |
| 6 | Application workflow with email and per-account grants | Application queue, email to the team address, approve/decline, revocable grants with optional expiry | Admin → Downloads → Applications / Access |
| 7 | Development board catalogue | Boards and samples filed against chips, filters, cards and a detail dialog | `/ingenic/boards` |
| 8 | Application and purchase are separate actions | Apply and Buy buttons drawn side by side, each shown only when its link is configured; neither link means Sold out | Board card and dialog |
| 9 | Scoped management | A user or group can be granted management of a product, page, board or download; enforced on the server | Admin → Permissions |
| 10 | Points for contribution | Rules table, append-only ledger, balances, member history, spending on downloads | `/ingenic/points`; Admin → Points |
| 11 | High-value bounties on questions | Points escrowed on the asker's topic, paid on accepted answer, refunded on withdrawal, expiry or topic deletion | `/ingenic/bounties`; topic banner |
| 12 | A front page that is a page, not a topic list | Registered homepage, configurable blocks, section cards, promotions, header buttons, partner platforms, footer columns | `/` and `/ingenic/home` |
| 13 | A forum that reads as Ingenic, in both languages | Sky-blue palette, three-group sidebar, bilingual strings, language switcher, wider layout and clearer borders | Theme |
| 14 | Connect the forum to AI clients | MCP landing page with endpoint and client steps; floating assistant into the AI bot | `/ingenic/mcp`; bottom-right robot |
| 15 | Ship it and explain it | Plugin and theme in separate repositories; deployment, seeding and this usage guide in both languages | Repositories and `docs/` |

### Not included

These were considered and deliberately left out of this version:

- Translating posts and replies between Chinese and English (a separate project).
- Migrating existing content out of the Chinese forum into this one.
- A chip selector inside the documentation header — the picker lives in the
  documentation control column, as approved.

## 3. Feature map

| Area | Members can | Administrators can |
| --- | --- | --- |
| Forum | Read, post, reply, like, flag, bookmark, message, search | Categories, groups, trust levels, site settings — all core Discourse |
| Documentation | Pick a series and chip, switch version, search, read, follow previous/next, open the forum discussion | Create the product tree, versions and pages; control publishing; grant scoped edit rights |
| Downloads | Filter the catalogue; download, fill in developer details, apply for access, unlock with points | Upload files, set access and price, review applications, grant or revoke access, read the download record |
| Boards | Filter by type and chip, read the dialog, follow Apply, Buy or documentation links | Create cards, set type, chip, links, specifications, publication and order |
| Points | See their balance, the price list and their own history | Edit rules, adjust an account, inspect balances and movements, recompute balances |
| Bounties | Put points on their own question, withdraw, accept an answer | Nothing specific: settle by accepting; repair mistakes through points adjustments |
| Site content | See the home page, promotions and footer the team configured | Edit home blocks, home cards, promotions, header buttons, partner platforms and footer columns |
| MCP / assistant | Copy the MCP endpoint and connect a client; open the assistant | Enable or disable the core MCP server and the AI bot |

## 4. Getting started as a member

### 4.1 Signing in

Use the sign-in methods the site offers. The Ingenic extension does not add or
change authentication, so the account, password reset, email verification and
social login all behave as they do on any Discourse forum.

Some downloads and all bounties require an account. Reading the forum,
documentation and the board catalogue does not.

### 4.2 Finding your way

The left sidebar has three Ingenic groups, plus Discourse's own sections:

- **Forum** (no heading): New Post, Home, Official Announcements, Technical
  Discussions.
- **Developer Resources** (under a heading): Online Documentation, Open Source,
  SDK & Firmware Downloads, Development Boards.
- **Member** (no heading): Bounties, Points.

Below that, in Discourse's community section, are **MCP**, **Site Feedback** and
**All Categories**. The MCP link appears only while the site's MCP server is
enabled; Site Feedback appears when the site has that category.

The site may let you collapse sections or filter the sidebar; those controls are
Discourse's own. The developer-resources heading can be renamed by an
administrator, and the whole list can be replaced in the site settings, so a
particular site's labels may differ slightly from the ones above.

### 4.3 The front page

The front page is assembled from blocks: popular sections, latest or hot
discussions, downloads, boards, promotions, bounties and the weekly contributor
ranking. Which blocks appear, their order, width and row count are set by the
administrators.

The **weekly contributors** block ranks members by the points they earned in
the current week. It is a display of the points ledger, not a separate score.

### 4.4 Posting and discussions

Posting, replying, quoting, mentions, likes, bookmarks, notifications and
flags are all standard Discourse behaviour. Two Ingenic features attach to
topics:

- A **bounty banner** appears above the posts when the topic carries a standing
  offer (see section 9).
- The **official identity badge** appears beside the names of members of the
  groups an administrator listed for it.

### 4.5 Language

Use the language menu in the header. Each language is written in its own
language — **EN** and **中文** — so the menu is readable whichever language is
currently active. The choice changes the interface; content such as
documentation pages and downloads follows the same language when a translation
exists, and falls back to the site's default content language otherwise.

## 5. Online documentation

### 5.1 Opening the reader

Choose **Online Documentation** in the sidebar. The page has:

- a **product picker** in the left control column: choose a series first, then a
  chip from that series;
- a **version selector** for the chosen chip;
- a **search box** that searches page bodies;
- a collapsible **contents tree** built from the page hierarchy;
- the **page body**, rendered from Markdown, with previous and next links.

A chip whose documentation has not been written yet says so instead of showing
an empty reader.

### 5.2 Products and versions

The product tree has exactly two levels: a **series** (for example `T Series`)
and a **chip** under it (for example `T33`). The same tree drives the download
filters and each board's chip, so all three agree about the name of a chip.

A version stores only the pages that were edited in it. If a page was not
touched in the selected version, the reader shows the version of that page from
the nearest earlier version that did edit it. This is why a new version does not
need a copy of the whole manual, and why a typo fixed in an old version can
still be inherited by a newer one. The administrator's page list shows which
version each inherited page currently comes from.

The version marked **latest** is the one the chip opens on. Older versions stay
readable, and a version can be marked as no longer maintained by the team.

### 5.3 Search and navigation

Search checks the pages of the selected chip and version and lists the pages
where the text appears. The
contents tree follows the parent/child structure set in the admin screen;
previous and next follow the same reading order. **Discuss in forum** opens the
topic linked to the page, or the site's documentation discussion category when
no topic is linked.

### 5.4 Sharing links

Documentation addresses are shareable and refreshable:

```text
/ingenic/docs
/ingenic/docs/<series>
/ingenic/docs/<series>/<chip>
/ingenic/docs/<series>/<chip>/<version>
/ingenic/docs/<series>/<chip>/<version>/<page>
```

Each level fills in from the one before when it is omitted, so a short link
still lands on real content. The reader replaces a short address with the
canonical one, so what you copy from the address bar is the full path.

### 5.5 On a phone

The control column collapses into the reader's mobile layout; the contents tree
and product picker remain reachable, and the page body takes the full width.
The sidebar itself becomes Discourse's standard drawer.

## 6. Downloads

### 6.1 Filtering the catalogue

The download centre has three filter rows:

1. **Chip series** — including the catalogue entry for algorithms.
2. **Model** — the chips inside the chosen series.
3. **Resource type** — SDK, firmware, manual, datasheet, toolchain, example,
   release notes or another type the team defined.

Each resource row shows its version, platform, size, release date and SHA-256
checksum. The filters are buttons, not drop-downs; the current choice is filled
in, and choosing another button changes the list immediately.

### 6.2 The three access levels

Every resource is published at one of three levels:

| Level | What you see | What you do |
| --- | --- | --- |
| Anyone signed in | **Download** when signed in, **Sign in to download** otherwise | Sign in |
| Signed in with developer information | **Add your details** the first time | Fill in the developer form once; it is reused for every gated download |
| Signed in with information and approval | **Apply for access** | Fill in the form, send an application, wait for the team to approve |

The developer form asks for the fields the team configured — by default full
name, company, job title, country or region, contact email, intended use,
project stage, estimated annual volume and anything else. It is stored with your
account, not with one download.

An application is visible in the administrator queue and is emailed to the
team's configured address. When it is approved you receive an email and can
download that resource. Approval is **per account and per resource**: an
approval for one SDK does not open another, and the team can revoke a grant. A
grant may also carry an expiry date.

While an application is waiting, the button says **Waiting for review**. If it is
declined, the card says **Access was declined** and explains how to follow up.

### 6.3 Resources that cost points

Some resources also carry a point price. The price is asked **after** the access
level, not instead of it: a resource that needs approval and costs points still
requires sign-in, developer information and approval before the points are
mentioned.

When you are eligible, the action becomes **Unlock for N points** if you can
afford it, or **Needs N points** if you cannot. Unlocking is a one-off payment —
once bought, the resource stays yours to download again. Points are spent from
the balance shown on the downloads page and on the points page.

### 6.4 Downloading

The file is streamed through the forum after the access check; it is not a
public link that can be shared around the gate. The stored SHA-256 lets you
confirm that the bytes arrived intact. If a file is missing from storage, the
forum reports the resource as unavailable and does not charge points.

## 7. Development boards and samples

### 7.1 The catalogue

**Development Boards** lists two kinds of item: **development boards** and
**sample chips**. Two filter rows match the download centre's style:

1. **Type** — Development boards or Sample chips.
2. **Chip** — All chips, or one chip from the product tree.

The chip list comes from the product tree, not from the cards currently shown,
so choosing a chip does not remove the control that undoes the choice.

### 7.2 Cards and the detail dialog

Each card shows an image, name, chip, short introduction and a short
specification list. Selecting a card opens a dialog with the longer details,
the full specification list, the documentation link and the same actions.

### 7.3 Apply, Buy and Sold out

The bottom of the card and the dialog carry the actions the team configured:

- **Apply** — opens the application page for the board.
- **Buy now** — opens the purchase page.
- Both buttons sit side by side when both links are configured.
- Only one button is shown when only one link is configured; it takes the full
  width of the action row.
- When **neither** link is configured, the item is still listed but there is
  nothing to click: a single grey **Sold out** button is shown and is disabled.

Links open in a new tab. An administrator can change either link at any time,
and the card follows on the next page load.

### 7.4 Documentation link

A board may also carry a documentation link, shown in the dialog separately from
Apply and Buy. It stays available when the item is sold out, because the
documentation is still useful.

## 8. Points

### 8.1 Earning points

The default rules are:

| Action | Points |
| --- | --- |
| Opening a discussion | 5 |
| Answering in one | 2 |
| A post of yours being liked | 1 |
| Your answer being accepted | 15 |

The amounts, labels and order are editable in the admin screen. A rule can be
switched off or set to zero without deleting the entries already written under
it. By default administrators and moderators do not earn points, but a like from
a staff member still counts for the member who wrote the post.

If a post is deleted, a like removed or an accepted answer unmarked, the points
that action earned are taken back with a second, opposite ledger entry. The
history shows both rows, so a balance can always be explained.

### 8.2 Seeing your points

**Points** in the sidebar shows your balance, the current price list and your
own recent movements. It is read-only and shows nobody else's rows. Signed-out
visitors are asked to sign in.

### 8.3 Spending points

Points are spent in the download centre, on resources that carry a price.
Unlocking is permanent for that account. Points are not transferable between
members; the one exception is a bounty, which moves points to whoever writes the
accepted answer.

## 9. Bounties (高分悬赏)

### 9.1 What a bounty is

A bounty is points a member sets aside on **their own topic** and pays, in full,
to whoever writes the answer they accept. It is a way to make a hard question
worth somebody's afternoon.

The points are **escrowed**, not merely promised: opening a bounty takes them off
your balance immediately, so they cannot be spent on a download while the offer
stands. The default limits are 50 to 5000 points per offer, and an offer stands
for 14 days before it expires; both limits and the number of days are site
settings.

Each topic can carry one standing bounty at a time. A bounty can only be opened
in a category that allows accepted answers, and the feature needs the points
system and the solved plugin to be enabled.

### 9.2 Opening and settling

1. Open your own topic.
2. Choose **Set a bounty on this question**, enter an amount within the allowed
   range and submit. The points leave your balance at that moment.
3. When an answer is accepted, the full amount is paid to its author. Accepting
   the answer is the payment; there is no separate release step.
4. Un-accepting an answer afterwards does **not** take the points back. The
   answerer may already have spent them. An administrator can adjust the two
   accounts by hand if a mistake must be repaired.

Staff can accept an answer on the asker's behalf when necessary.

### 9.3 Withdrawing, expiry and deletion

- The asker can withdraw a standing offer; the points return immediately.
- If nobody answers before the deadline, a scheduled job closes the offer and
  refunds the points.
- Permanently deleting the topic closes the offer and refunds whatever is still
  standing. Moving a topic to the trash does not refund it; the offer stands
  until its deadline and disappears from the board while trashed.
- Switching bounties off stops new offers but still refunds the ones already
  standing.

### 9.4 The bounty board

**Bounties** in the sidebar lists the standing offers across the forum, richest
first, with the question, the amount and the time left. On the topic itself, a
banner shows the offer, who made it, and — for the asker — a way to withdraw it.
Once settled, the banner says what was paid and to whom.

## 10. MCP and the AI assistant

### 10.1 The MCP page

The Model Context Protocol (MCP) lets an AI assistant reach the forum's tools
and data. **MCP** in the community section opens a landing page with:

- the server endpoint, which is the site's own address followed by `/mcp`;
- a copy button;
- the three steps of connecting a client: add the endpoint, sign in and approve,
  then start asking;
- ready-made commands for Claude Code and Visual Studio Code, and a note for
  any other client that supports remote MCP over HTTP;
- a description of what an approved client can see.

An approved client acts as the account that approved it. It sees only the
categories, topics and posts that account can see, and it stops working when the
authorization is revoked. The site administrator manages the server and the
approved clients under **Admin → MCP**.

If the site has not enabled the MCP server, the page explains that and the
sidebar link is hidden.

### 10.2 The assistant

The robot button in the bottom-right corner opens the Ingenic assistant panel.
It explains what the assistant is for and leads into the AI bot's conversations.
A signed-out visitor is asked to sign in first and is returned to the assistant
afterwards.

The assistant answers from the forum and points to documentation when it can.
Answers are generated by AI; check anything important against the documentation.
The button only appears while the AI bot is enabled for the site.

## 11. Administrator guide

### 11.1 Where the screens are

Everything the plugin owns is under **Admin → Plugins → Ingenic**. The admin
sidebar opens the **Documentation** screen; the other screens have their own
addresses:

| Screen | Address | What it manages |
| --- | --- | --- |
| Documentation | `/admin/plugins/discourse-ingenic/documentation` | Series, chips, versions, pages |
| Downloads | `/admin/plugins/discourse-ingenic/downloads` | Resources, applications, access, categories, download record |
| Development boards | `/admin/plugins/discourse-ingenic/boards` | Board and sample cards |
| Points | `/admin/plugins/discourse-ingenic/points` | Rules, adjustments, balances, movements |
| Permissions | `/admin/plugins/discourse-ingenic/permissions` | Scoped management grants |
| Site content | `/admin/plugins/discourse-ingenic/site` | Home layout, home cards, promotions, header buttons, partner platforms, footer |

Scoped managers see the documentation, boards and downloads they were granted.
The application queue, access list, download record, points, permissions and
site content remain administrator-only. The server enforces this; hiding a
button is not the boundary.

Before the first content is added, deploy the plugin and theme and run the
category seeding task — see [`DEPLOY.md`](../DEPLOY.md) and
[`docs/seeding.md`](seeding.md).

### 11.2 Documentation

1. **Create a series.** Give it a name, a slug and a locale. A series is one row
   in the product tree.
2. **Add a chip under the series.** A chip must have a series as its parent;
   the admin screen and the database both refuse a chip without one.
3. **Add a version to the chip.** Give it a version slug (for example `1.1.0`),
   a label and an order. One version can be flagged **latest**.
4. **Add pages to the version.** Each page has a title, slug, optional parent
   slug, Markdown body and a published switch. The parent slug is what builds
   the contents tree.
5. **Order and rename** rows with the arrows and the rename control. A row with
   children cannot be deleted; remove or move the children first.
6. **Override an inherited page** by choosing **Override in this version**; the
   page becomes editable in this version. **Restore inheritance** deletes the
   copy in this version and returns to the earlier source.

A published page is visible to readers; an unpublished page is absent from the
tree and returns not-found when requested directly. A version with no page of
its own simply inherits the pages of the version before it.

The product tree is shared by three features, so build it before downloads or
boards: documentation uses it for the picker, downloads for the series/model
filters, and boards for each card's chip.

### 11.3 Downloads

The Downloads screen has up to five tabs:

- **Resources** — add and edit a resource. Fields include name, catalogue
  (`chip` or `algorithm`), product slug, category, version, locale, platform,
  architecture, access level, point cost, file upload or URL, file size,
  checksum, release date, order, description and published.
- **Applications** — the queue of access requests. Open one to read the
  applicant's developer information, add a note, then **Approve and grant** or
  **Decline**. An optional expiry can be set on the grant.
- **Access** — every live grant, per account and per resource, with the option
  to revoke it.
- **Categories** — the labels used by the resource-type filter. Retiring a label
  leaves its resources in the list, unfiled, so they can be reclassified one at
  a time.
- **Download record** — who downloaded what and when. Administrator-only,
  because it names accounts.

Uploading a file stores it under the configured download directory (outside the
web root) and computes its SHA-256. The file is streamed through the forum only
after the access check. If the configured storage directory is not writable,
the screen says so before an upload is attempted; set
`ingenic_download_storage_path` to a writable volume.

The three access levels are explained in section 6.2. The point price is
optional and is charged only when the file is actually released.

### 11.4 Development boards and samples

Add a card, then set:

- **Type** — development board or sample chip.
- **Chip** — a chip in the product tree. This files the card under its series,
  keeps the chip name in step with the documentation, and is what the Chip
  filter uses. A card whose chip is not in the tree yet can keep a typed name.
- **Application URL** and **Purchase URL** — each button appears only when its
  link is filled in. Leave one empty to hide that button; leave both empty to
  show the grey, disabled **Sold out** state.
- **Documentation URL** — shown in the card's dialog.
- **Introduction**, **Details**, **Specifications** (one per line), **Image
  URL**, **Order** and **Published**.

Withdrawing a card removes it from the public catalogue without deleting it.

### 11.5 Points

- **Rules** — edit what each action is worth, its label and order, and whether
  it is in use. Setting a value to zero or switching the rule off stops future
  awards without touching the ledger. There is no delete, because old entries
  refer to the rule.
- **Adjust one account** — choose a member, enter a positive or negative number
  and a reason. The adjustment is written into the ledger like any other
  movement.
- **Balances** — every account holding points and when it last moved.
- **Recent movements** — the last hundred entries, newest first. An award that
  was reversed appears twice.
- **Recompute every balance** — rebuilds the balance cache from the ledger.
  Run it after a restore or import, or if a number looks wrong.

Points can be switched off in the site settings. Existing balances and entries
are untouched, and an administrator's manual adjustment still works.

### 11.6 Permissions

A grant names a principal (a user or a group), a resource type and a resource
ID. The resource types offered in the screen are documentation product,
documentation page and development board; scoped download management is also
supported by the data model. A product grant is inherited by its versions and
pages; a page grant is inherited only by that page's children. Granting a series
lets a manager edit its chips and their pages; granting one chip does not give
access to its siblings or its parent.

Every create, read, update and delete is checked on the server, so a hidden
button is only presentation.

### 11.7 Site content

The **Site content** screen has six tabs:

- **Home page** — the ordered list of blocks: block type, heading, width
  (automatic, full, main or side), row count, category or section list, and
  whether the "All categories" link is shown. Saving replaces the theme's default
  layout.
- **Home cards** — the cards under Popular sections. Name a category to borrow
  its address, colour, icon and topic count, or give a label, link, description,
  icon, image, colour and order of your own.
- **Promotions** — headline, corner label, description, button, background
  image, locale, show-from/show-until window, order and publication. A slot with
  no dates stays until it is unpublished.
- **Header buttons** — the buttons beside the logo: label, link, built-in icon
  or image, whether the name is drawn, external flag, order and visibility.
- **Partner platforms** — the footer's "Find us" strip. Each entry is a link or
  a QR code, with a label, image or QR picture, optional caption and order.
- **Footer columns** — headings and their links (label, address, external flag,
  order, visibility).

The home page block types are: popular sections, promotions, announcements,
discussions, latest topics, hot topics, downloads, development boards, bounties
and the weekly contributor leaderboard.

### 11.8 Site settings

The settings that matter most are under **Admin → Settings** (search for
`ingenic`):

| Setting | Purpose |
| --- | --- |
| `ingenic_enabled` | Master switch for the extension |
| `ingenic_nav_items` | JSON list of sidebar entries: label, icon, target, group, order, visibility |
| `ingenic_homepage_blocks` | JSON list of home-page blocks (the Site content screen edits the same list) |
| `ingenic_default_locale` | Content language used when a translation is missing |
| `ingenic_docs_discussion_category` | Category used by "Discuss in forum" when a page has no linked topic |
| `ingenic_download_storage_path` | Where uploaded files are stored; must be outside `public/` |
| `ingenic_download_admin_email` | Address notified when an application is submitted |
| `ingenic_developer_form_fields` | JSON description of the developer information form |
| `ingenic_official_groups` | Groups whose members wear the official identity badge |
| `ingenic_points_enabled` | Turns earning and spending on or off without clearing balances |
| `ingenic_points_exclude_staff` | Whether staff are excluded from earning points (on by default) |
| `ingenic_bounties_enabled` | Turns new bounties on or off; standing offers still expire and refund |
| `ingenic_bounty_min_points` | Smallest allowed bounty (default 50) |
| `ingenic_bounty_max_points` | Largest allowed bounty (default 5000) |
| `ingenic_bounty_expiry_days` | Days before an unanswered bounty is refunded (default 14) |

`ingenic_nav_items` is a JSON array. An entry looks like this:

```json
{
  "key": "docs",
  "label": "Online Documentation",
  "icon": "book",
  "href": "/ingenic/docs",
  "section": "resources",
  "position": 4,
  "enabled": true
}
```

`section` is `forum`, `resources` or `member`; `position` orders entries within
the group. Use `"category": "technical-discussions"` instead of `href` to point
at a Discourse category. An empty setting uses the theme's default list. A
configured list replaces the default wholesale.

### 11.9 Theme settings

Under **Admin → Customize → Themes → Ingenic Community → Settings**:

| Setting | Purpose |
| --- | --- |
| `ingenic_locales` | Languages offered by the header switcher, in order |
| `ingenic_sidebar_width` | Desktop sidebar width in pixels |
| `ingenic_sidebar_position` | Left or right |
| `ingenic_nav_order` | Ingenic navigation above or below Discourse's own sidebar sections |
| `ingenic_nav_title` | Heading over the developer-resources group |
| `ingenic_hero_title` | Optional headline above the home blocks |
| `ingenic_hero_subtitle` | Optional supporting line |

The language switcher also needs Discourse's `allow_user_locale` and
`set_locale_from_cookie` settings. The accent colour is the **Ingenic Light**
colour scheme, editable with Discourse's normal colour pickers.

### 11.10 Content languages

Every documentation page, download and board row carries a locale. Use
Discourse's own codes — `en`, `zh_CN` — because they are compared with the
reader's interface language. `zh-CN` is not the same code and will not match.
Missing translations fall back to `ingenic_default_locale` per record, so a
half-translated site still renders.

The theme's interface strings live in `locales/en.yml` and `locales/zh_CN.yml`;
adding another language means adding a file with the same keys. The header
switcher only offers languages listed in `ingenic_locales`.

### 11.11 Housekeeping

- Run `rake ingenic:doctor` after a restore or a category change; it reports
  missing forum sections.
- The plugin exports and imports its content through `ingenic:config` tasks
  described in `DEPLOY.md`; use them to move content between sites.
- A permanently deleted member leaves ledger entries, applications and grants
  behind with the account blanked; the screens say **deleted account**.
- A permanently deleted topic refunds any standing bounty before the topic row
  is removed.

## 12. Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| MCP link is missing from the sidebar | `mcp_server_enabled` is off | Enable it under Admin → Settings → MCP |
| Assistant button does not appear | `ai_bot_enabled` is off, or discourse-ai is not installed | Enable the AI bot; the button hides rather than linking nowhere |
| A download says "Sign in to download" | The resource needs an account at minimum | Sign in |
| A download asks for developer information every time | The profile did not save, or the site's form fields changed | Submit the form again; check the required fields |
| An application stays "Waiting for review" | Nobody has decided it, or the notification email address is empty | Check Admin → Downloads → Applications; set `ingenic_download_admin_email` |
| "Access was declined" | The team declined this application | Contact the team; a new application may be possible after the situation changes |
| "Needs N points" | The balance is below the resource price | Earn points by contributing, or ask the team |
| A bounty cannot be opened | Points or solved is off, the topic is not yours, the category does not allow accepted answers, or a bounty already stands | Check the category and the site settings |
| A documentation page cannot be edited | It is inherited from an earlier version | Choose **Override in this version**, or edit the source version |
| A page is missing from the reader | It is unpublished, or its parent is unpublished | Publish it in Admin → Documentation |
| Uploads fail | The download storage directory is not writable | Point `ingenic_download_storage_path` at a writable volume outside `public/` |
| The home page looks empty | The extension or theme is disabled, or no blocks are configured | Check `ingenic_enabled`, the default homepage setting and Site content → Home page |
| Content appears in the wrong language | The row's locale code does not match the reader's locale | Use `en` or `zh_CN`; check `ingenic_default_locale` |

## 13. Repository and support

- Plugin: <https://github.com/aishangletaohua/discourse-ingenic-plugin>
- Theme: <https://github.com/aishangletaohua/discourse-ingenic-theme>
- Deployment: [`DEPLOY.md`](../DEPLOY.md) · [中文](../DEPLOY.zh-CN.md)
- Bulk seeding: [`docs/seeding.md`](seeding.md) · [中文](seeding.zh-CN.md)

For account, content or access problems, contact the Ingenic community team
through the forum's **Site Feedback** category or the address the team
publishes on the site.
