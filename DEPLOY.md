# Deploying the Ingenic community theme and plugin

Two pieces, installed separately:

| Piece | What it is | How it installs |
| --- | --- | --- |
| `discourse-ingenic` | Rails plugin — documentation, downloads, boards, admin settings | files in `plugins/`, then rebuild |
| `discourse-ingenic-theme` | Theme — layout, navigation, homepage, documentation UI | uploaded as a zip, no rebuild |

Nothing here touches authentication. Google, GitHub and email login stay exactly
as your Discourse is configured today.

Target: Discourse `2026.10.0-latest`. Both pieces were developed and statically
verified against that version.

---

## 1. Plugin

### Option A — from a git repository (recommended)

Put the `discourse-ingenic` directory in a repository your server can reach,
then add it to `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://<your-git-host>/discourse-ingenic.git
```

### Option B — copy the files

```bash
# from this machine
scp -r discourse-ingenic <user>@<host>:/tmp/discourse-ingenic

# on the server
sudo mv /tmp/discourse-ingenic /var/discourse/plugins/discourse-ingenic
```

### Then rebuild

```bash
cd /var/discourse
./launcher rebuild app
```

The rebuild runs the plugin's migrations and creates its eighteen tables. It
takes a few minutes, and the forum is offline while it runs — there is no
zero-downtime rebuild in `discourse_docker`.

A **rebuild** is what is needed here, not a container restart: the front page
added a controller and a route, and Discourse reads a plugin's files at boot.
Updating only the theme is the other case — a theme zip upload needs no rebuild
at all.

Confirm the plugin loaded:

```bash
./launcher enter app
rails c
SiteSetting.ingenic_enabled          # => true
IngenicDocProduct.count              # => 0, no content yet
```

---

## 2. Theme

**Admin → Customize → Themes → Install → From a file**, and upload
`discourse-ingenic-theme.zip`.

Then:

1. Open the theme and pick the **Ingenic Light** colour scheme. This is where the
   accent colour lives — the standard colour pickers edit it, and there is no
   separate brand-colour setting. It ships a light sky blue: accent
   `#2FC1FF`, text `#12263a`, header `#f2f9fd`, highlight `#cfe8fb`. If the
   header comes out grey rather than faintly blue, the theme is still on the
   site's old colour scheme and this step was missed.

   The accent is deliberately pale, which means it is a surface rather than a
   letter. The theme handles that itself: links and button labels are painted
   with a readable sibling of the same hue (see **Colours** in the theme's
   README). If you change the accent to a deeper blue, the theme still works —
   you will simply have a darker link colour than it needs.
2. Set it as the site's default theme, or make it a selectable one first and
   switch over once you are happy with it.

The theme is not a component and does not need one.

---

## 3. Settings to set after installing

### Site settings (plugin)

| Setting | Suggested value |
| --- | --- |
| `ingenic_enabled` | on |
| `ingenic_default_locale` | the language most of your documentation is written in |
| `ingenic_docs_discussion_category` | slug of the category that documentation discussions belong in |
| `ingenic_download_storage_path` | a directory on a large volume, outside `public/`; empty means `<app>/ingenic-downloads` |
| `ingenic_download_admin_email` | the address that should receive download applications |
| `ingenic_developer_form_fields` | JSON; empty uses the built-in developer form |
| `ingenic_official_groups` | the groups whose members should wear the official badge, e.g. `admins` |
| `ingenic_points_enabled` | on, unless you are not ready for it yet |
| `ingenic_points_exclude_staff` | on |
| `ingenic_bounties_enabled` | on, once you are ready to let members offer points |
| `ingenic_bounty_min_points` | 10 |
| `ingenic_bounty_max_points` | 1000 |
| `ingenic_bounty_expiry_days` | 14 |

`ingenic_download_storage_path` holds the uploaded SDKs and firmware. It has to
be outside `public/`: a file the web server will serve to anyone who guesses
its URL cannot be gated by anything the plugin does, so the files are streamed
through the plugin instead. Point it at a larger volume when the downloads
outgrow the application disk.

`ingenic_download_admin_email` is where an application for a restricted
resource is sent. Left empty, applications are still recorded and shown in the
admin queue — nobody is emailed about them.

`ingenic_developer_form_fields` replaces the built-in developer form. It is a
JSON array of `{ "key", "label", "type", "required" }`, where `type` is `text`
or `textarea`:

```json
[
  { "key": "full_name", "label": "Full name", "type": "text", "required": true },
  { "key": "use_case",  "label": "Intended use", "type": "textarea", "required": true }
]
```

The form the visitor sees, the validation on submit and the admin's view of an
answer all come from this one definition, so the three cannot disagree. Leave
it empty for the built-in set. Answers to a field that is later removed from
the configuration are kept rather than erased, so dropping a question does not
destroy what was already answered under it.

No telephone number is asked for, in the built-in form or in the example
above. An account already has an email address the team can write to, and a
field nobody reads is one more reason for a developer to abandon the form.

`ingenic_official_groups` names the groups whose members wear an official
identity badge beside their username. One group name per entry, spelled as the
group is spelled on its own page; case and stray spaces do not matter. The
badge is Discourse's own group flair, which the group's own settings already
let you upload or pick from an icon set — this setting only decides who wears
it. A member who already wears a badge they chose keeps it, and can pick up
the official one from their preferences page instead. Listing more than one
group is a way of saying which badge outranks which: the first listed group a
member belongs to is the one that wins. The setting is safe to fill in before
the artwork exists — a listed group with no flair configured grants nothing,
and the badges appear once it is uploaded.

`ingenic_points_enabled` is the whole points system's switch. Off, the forum
stops handing points out and a resource that carries a price is free to
whoever is cleared for it. It does not clear the ledger: the entries and the
balances are left where they were, and switching it back on resumes from
there. An administrator adjusting an account by hand still works while it is
off, because that is somebody deciding on purpose rather than the forum
deciding for them.

`ingenic_points_exclude_staff` keeps administrators and moderators off the
ledger. It is on by default, on the grounds that answering here is a member of
staff's job rather than their contribution, and a leaderboard nobody in the
community can reach the top of is not much of a leaderboard. Worth knowing
while trying the feature out: a moderator posting to test it will see nothing
happen. It does not stop staff *giving* points — a like from a moderator still
counts for the member who wrote the post.

Both settings can be changed at any time. Turning `ingenic_points_exclude_staff`
off does not back-pay the posts staff have already written; it applies from the
next one.

`ingenic_bounties_enabled` lets a member offer points on their own question,
paid in full to whoever writes the answer they accept. It needs the points system
and discourse-solved, and is off on its own if either of those is off — a bounty
is points moving, and the answer it settles on is discourse-solved's ✓.
Switching it off stops the forum taking new offers and still lets the standing
ones run out and refund; that is deliberate, because a switch meant to stop new
offers should not strand points that are already set aside.

The floor and the ceiling are what a member may offer, in points.
`ingenic_bounty_expiry_days` is how long an offer stands before it is closed and
the points go back to whoever offered them — long enough that answering takes
less time than the offer does. There is no per-category setting: a bounty belongs
to a topic, and a topic belongs to a category only incidentally.

Worth knowing before switching this on: the points are **escrowed**, so a member
who offers 500 points has 500 fewer to spend on a download until the offer is
settled. That is the mechanism rather than a side effect — it is what stops one
member offering the same 500 points on ten questions — but it is the part that
surprises people the first time.

`ingenic_nav_items` and `ingenic_homepage_blocks` are JSON. Both are optional —
with `ingenic_nav_items` left empty the theme falls back to its shipped
navigation (Documentation, Downloads, Development Boards, Bounties, Points).

**A configured `ingenic_nav_items` replaces the shipped list wholesale**, it does
not merge with it. So a site that configured its navigation before Bounties
existed has no Bounties entry and will not grow one: add it to the JSON, or clear
the setting and start from the list below.

A starting `ingenic_nav_items`:

```json
[
  { "key": "home",      "label": "Home",                 "icon": "house",     "href": "/",               "position": 0, "enabled": true },
  { "key": "announce",  "label": "Official Announcements", "icon": "bullhorn", "category": "official-announcements", "position": 1, "enabled": true },
  { "key": "discuss",   "label": "Technical Discussions",  "icon": "comments", "category": "technical-discussions",  "position": 2, "enabled": true },
  { "key": "docs",      "label": "Documentation",        "icon": "book",      "href": "/ingenic/docs",   "position": 3, "enabled": true },
  { "key": "downloads", "label": "Downloads",            "icon": "download",  "href": "/ingenic/downloads", "position": 4, "enabled": true },
  { "key": "boards",    "label": "Development Boards",   "icon": "microchip", "href": "/ingenic/boards", "position": 5, "enabled": true },
  { "key": "bounties",  "label": "Bounties",             "icon": "gift",      "href": "/ingenic/bounties", "position": 6, "enabled": true },
  { "key": "points",    "label": "Points",               "icon": "star",      "href": "/ingenic/points", "position": 7, "enabled": true }
]
```

`category` entries resolve to `/c/<slug>`, so navigation can point at a forum
section instead of a URL. Each chip gets its own category, and its own
documentation entry pointing at that chip's `/ingenic/docs/<product>`.

A starting `ingenic_homepage_blocks`:

```json
[
  { "type": "categories",    "enabled": true, "position": 0 },
  { "type": "bounties",      "enabled": true, "position": 1, "limit": 4 },
  { "type": "promotions",    "enabled": true, "position": 2 },
  { "type": "announcements", "enabled": true, "position": 3, "limit": 5,  "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 4, "limit": 10, "category": "technical-discussions" },
  { "type": "downloads",     "enabled": true, "position": 5, "limit": 6 },
  { "type": "boards",        "enabled": true, "position": 6, "limit": 4 }
]
```

`promotions` draws the activity slots managed in **Ingenic → Site → Promotions**;
with no promotions configured the block renders nothing. The `bounties` block
lists the richest standing offers and renders nothing while there are none, so it
is safe to leave on from the first day. A supported type with no component behind
it also renders nothing, so a mistyped name is a block that silently never
appears.

### The front page

The plugin offers its home page to Discourse as a **homepage**, so this is one
core setting rather than a plugin one:

| Setting | Value | Why |
| --- | --- | --- |
| `default_homepage` | the Ingenic home page (stored value `ingenic-home`) | Makes `/` the front page |

Admin → Settings → Interface, or by console:

```bash
./launcher enter app
rails c
SiteSetting.default_homepage = "ingenic-home"
```

The option is listed only while `ingenic_enabled` is on. A site that has it
selected and then switches the plugin off falls back to the ordinary homepage
instead of showing an error.

What the front page is: a banner, a strip of the five tool pages
(Documentation, Downloads, Development Boards, Bounties, Points), and then the
homepage blocks. It is **not** a topic list and it has no latest/hot/new tabs of
its own — those belong to the topic lists, which are now somewhere else. Choosing
*Latest* in the navigation goes to the latest topics and leaves the front page
where it is; before, the front page was drawn above whatever list you were on
and disappeared the moment you switched to one.

Its own address is `/ingenic/home`, so a link to it can be written down and a
refresh serves the same page.

A starting `ingenic_homepage_blocks` for a front page — the section grid plus the
bounty panel, which is also what an empty setting gives you:

```json
[
  { "type": "categories", "enabled": true, "position": 0, "limit": 8 },
  { "type": "bounties",   "enabled": true, "position": 1, "limit": 4 }
]
```

`categories` lists the forum's sections as cards, each one linking into its
category. Add `"categories": ["official-announcements", "technical-discussions"]`
to name the sections and their order; leave it out and it takes the busiest
top-level ones up to `limit`. `"show_all": false` drops the **All sections**
link at the end of the block's heading.

`bounties` lists the richest standing offers and draws nothing at all — no
heading, no empty row — while there are none, which is what makes it safe to
leave on before the forum has taken to bounties. It is the one block that is in
the default set for that reason.

To keep the announcements and discussions blocks as well, put them after it:

```json
[
  { "type": "categories",    "enabled": true, "position": 0, "limit": 8 },
  { "type": "bounties",      "enabled": true, "position": 1, "limit": 4 },
  { "type": "announcements", "enabled": true, "position": 2, "limit": 5, "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 3, "limit": 6, "category": "technical-discussions" }
]
```

### Language

The interface language is Discourse's own feature, so these are core settings
rather than plugin ones. Three of them decide whether the header's language
switcher works at all:

| Setting | Value | Why |
| --- | --- | --- |
| `default_locale` | `en` | The language a first-time visitor gets |
| `allow_user_locale` | on (already the default) | With it off nobody may choose a language, and the switcher hides itself |
| `set_locale_from_cookie` | on | A signed-out reader's choice is kept in a cookie, and Discourse does not read that cookie back while this is off — the switch then looks like it does nothing |

The switcher sits at the far right of the header — signed out, just left of the
**Log in** button; signed in, immediately left of the avatar — and offers the
languages listed in the theme's `ingenic_locales` setting, `en` and `zh_CN` by
default. Each language is labelled in its own language, so a reader who cannot
read the current one can still find theirs.

Discourse remembers a language in two places and the switcher writes to
whichever one applies: a signed-in account carries its own preference (the same
one under the account's preferences), and a signed-out visitor is served from
the cookie. A reader who is signed in never sees the cookie — that is
Discourse's rule, not the plugin's.

### The foot of the page

Below the theme's own footer (the partner platform strip and the link columns,
configured in **Ingenic → Site**) Discourse draws a line of its own: **Powered by
Discourse**, the last thing on most pages. Hiding it is one core setting, not a
theme change:

| Setting | Value | Why |
| --- | --- | --- |
| `enable_powered_by_discourse` | off | Removes the **Powered by Discourse** line, leaving the end of the page to this forum's own footer |

It is under **Admin → Settings → Site admin**, or search the settings screen for
`powered by`. The theme's own footer is a separate thing — it comes from
**Ingenic → Site** and is unaffected by this setting.

### Theme settings

| Setting | Default | Effect |
| --- | --- | --- |
| `ingenic_locales` | `en\|zh_CN` | The languages the header's switcher offers; it stays hidden with fewer than two |
| `ingenic_sidebar_width` | 272 | Sidebar width on desktop |
| `ingenic_sidebar_position` | left | Move the sidebar to the right |
| `ingenic_nav_order` | first | Ingenic navigation above or below Discourse's own sections |
| `ingenic_nav_title` | empty | Optional heading above the navigation; empty renders a plain list |
| `ingenic_hero_title` | empty | Optional headline above the homepage blocks |
| `ingenic_hero_subtitle` | empty | Optional supporting line |

---

## 4. Content

Documentation, downloads, boards, points, scoped permissions and the site's own
front page are all managed from **Admin → Plugins → Ingenic**, which has six
tabs. An administrator is offered all six. A moderator, or anyone granted a
scoped permission over a product or a board, is offered only the two screens
that grant covers — Documentation and Development boards — because the other
four are decided on the server as an administrator's, and a link to a page that
refuses you is worse than no link. Discourse's own Plugins page is staff-only,
so it is an administrator or a moderator who reaches these screens at all.

**Documentation** — the product tree (series → chips), the versions of each
product, and the page tree of a version. A page edited under one version can be
overridden in a later one; a page that is not overridden is inherited from the
version before it, so a new version starts as the last one without anybody
copying anything. The editor says which version a page currently comes from and
offers **Override in this version** and **Restore inheritance**.

**Downloads** — five tabs. *Resources* is the catalogue: name, product, version,
platform, classification, the file (uploaded, or a URL held elsewhere), release
date and access level. *Applications* is the queue for restricted resources,
showing each applicant's developer information, with Approve and Reject.
*Access* is who currently holds a grant, with Revoke. *Download record* is who
downloaded what, and when. *Categories* is the editable list of classifications
— add, rename, order and retire.

**Boards** — the development board cards: picture, chip, description,
specifications, the documentation link and the **Buy now** link.

**Permissions** — scoped access to documentation. A product-family grant is
inherited by its versions and pages; a page grant is limited to that page and
its child pages. Assignments can target a user or group, and the server enforces
every write operation.

**Points** — what members earn for contributing, and what a resource can cost to
unlock. One screen, four parts. *What earns points* is the price list: what each
action is worth, what to call it on a member's history, the order they are shown
in, and whether the forum still pays it at all. *Adjust one account* moves a
balance by hand, picked by username, with a note that becomes the reason on the
ledger row. *Repair the balances* re-derives every running total from the
entries, for when the two have drifted — the entries are the record, the balances
are only a cache of them. *Recent movements* is the last hundred rows, with
*Balances* above it naming who is holding what.

Reading this screen is administrator-only, not just writing it: the ledger names
accounts, and an adjustment moves a member's standing. A product or board scoped
permission does not reach it — there is no product a points balance belongs to.

**Site** — the three parts of the site that are content rather than forum, in
three tabs. *Promotions* are the homepage activity slots, each with a picture, a
headline and a destination. *Partner platforms* is the strip in the footer,
which takes either a link or a QR code image — a platform whose home is a web
page gets a link, one that lives in an app gets a code the visitor scans.
*Footer columns* are the footer's link columns: as many as you want, each with
its own heading and its own ordered links.

### Access levels

Every resource carries one of three levels, and the plugin enforces it on the
file endpoint rather than in the page, so the button and the file cannot
disagree.

| Level | What a visitor has to do first |
| --- | --- |
| `public_login` | sign in |
| `login_form` | sign in, and have developer information on file |
| `login_form_request` | sign in, have developer information on file, and have an application approved |

The developer information is asked for once and reused by every restricted
resource — it is not a form per file. An approval lasts: a grant has no end
date, so the log, not the grant, is what says a file was collected. Nothing
hands a URL to a resource the visitor has not been cleared for; the listing
shows the endpoint and the endpoint decides.

### What a resource costs

Above the level, a resource can also carry a **point cost**, set on the same
form in **Ingenic → Downloads → Resources**. Zero is the default and means free.

The price is asked *after* the level, never instead of it: a `login_form_request`
resource that costs 500 points still asks a new visitor to sign in, fill in
their details and be approved before it mentions points. Nothing is for sale to
an account that has not been cleared for it.

A purchase is recorded as a ledger entry, not as a new column somewhere, which
is what makes it idempotent: once bought, the resource is never charged for
again, however many times it is downloaded, and the purchase survives the
visitor's balance being spent down to nothing in the meantime. The listing draws
**Unlock for N points** when the balance suffices and **Needs N points** when it
does not, so the button never offers what the endpoint will refuse.

Charging happens in the branch of the file endpoint that actually releases the
file, never in the one that reports a resource unavailable — so a download that
turns out to be missing from storage costs nothing.

Points are earned by contributing: opening a discussion, replying, having a post
liked, having an answer accepted. Each of those also has a matching event that
takes the points back when the post is deleted, the like is removed or the
answer is unmarked. A member sees their own balance, the price list and their
own history at **`/ingenic/points`**, which is read-only from the front end —
points are earned by contributing and spent on a download, and neither happens
through that address. A visitor with no account still gets the price list, so
the page has an answer for them rather than a locked door.

Points are a plugin feature; the page is reached through the theme's navigation.
The theme ships a Points entry, and a site that has configured its own
`ingenic_nav_items` needs to add one itself.

### Deleting a member

Deleting an account in **Admin → Users** works even for a member who has been
here a while. It did not always: anyone who had earned a point, applied for a
download or set a bounty had rows pointing at their account with a key that
refused to let go, and nothing in the plugin was listening for the deletion —
so the admin screen answered with a database error instead. The plugin's
references to `users` are now either **nullifying**, where the row stays and the
account is blanked, or **cascading**, where the row is about the person rather
than about the forum.

| Table | What happens to their rows |
| --- | --- |
| `ingenic_point_entries` | kept, account blanked — the ledger still has to add up |
| `ingenic_bounties` | kept, account blanked; a settled bounty stays on its topic |
| `ingenic_download_requests` | kept, account blanked — the application and the answer it got are the record of a decision |
| `ingenic_download_grants` | kept, account blanked — it lets nobody in, and still says access was granted once |
| `ingenic_developer_profiles` | deleted — it is answers about a person, not about the forum |
| `ingenic_point_balances` | deleted — a cached total nobody holds, recomputable from the ledger |
| `ingenic_permissions` | deleted — a grant to an account or a group that no longer exists |
| `ingenic_download_logs` | deleted (this was already the case) |

Two consequences worth knowing before deleting somebody:

- A standing bounty whose asker has gone is still paid if an answer is accepted,
  and still expires at its deadline and returns the points. If the asker is gone
  at that point the refund has nowhere to land and is recorded against nobody —
  the escrow left an account, and there is no account left to return it to. The
  ledger shows it rather than losing it.
- An application from a deleted account cannot be approved: there would be no
  account to hold the access. The queue shows the row with **deleted account**
  where the name was, approving it says why it cannot be, and declining it still
  works. The same label appears in the points ledger and the access list.

Use `docs/seeding.md` for console examples and migration/bootstrap workflows —
in English, or `docs/seeding.zh-CN.md` in Chinese. They cover the same ground:
both are worth skimming, and the Chinese one is the one to hand to somebody who
will be doing the seeding. The console remains useful for bulk imports, but
normal editing should use the management pages.

Short version:

```bash
cd /var/discourse
./launcher enter app
rails c
```

Then create a product, a version and pages, as in `docs/seeding.md`. Until there
is at least one published product, `/ingenic/docs` shows its "not available"
state — that is expected, not a bug.

---

## 5. Verify

Open these and check each one:

- [ ] `/ingenic/docs` lands on the first product and rewrites the address to it
- [ ] the series → chip picker narrows the chips under the series you point at
- [ ] the page tree expands, and previous/next move through the pages in order
- [ ] the version picker switches versions and stays on the same page where it exists
- [ ] a page left unedited in a later version shows the earlier version's text, and the editor names the version it came from
- [ ] `/ingenic/downloads` filters by series, chip, classification, version and platform
- [ ] a `public_login` resource downloads after signing in; a `login_form_request` one asks for an application first
- [ ] approving an application in the queue lets that account download, and **Ingenic → Downloads → Download record** names the account
- [ ] a post written by a member moves their balance, and **Ingenic → Points → Recent movements** shows the entry
- [ ] deleting that post takes the points back, and the original entry is still in the ledger beside the reversal
- [ ] a resource you gave a point cost to shows **Unlock for N points** to an account that can afford it and **Needs N points** to one that cannot
- [ ] buying it costs the points once; downloading it a second time costs nothing
- [ ] `/ingenic/points` shows the signed-in member their balance, the price list and their own history — and nobody else's
- [ ] an administrator adjusting an account by hand moves the balance and writes the note as the reason
- [ ] deleting a test member who has points, an application or a bounty goes through without a database error, and their movements are still in **Ingenic → Points → Recent movements** with **deleted account** where the name was
- [ ] with `ingenic_points_enabled` off, a priced resource downloads free and nobody earns anything; the balances are still there when it goes back on
- [ ] on a question of your own, **Set a bounty on this question** names the range and your balance, and setting one takes the points off your balance at once — **Ingenic → Points** then shows them set aside
- [ ] the standing offer shows on the topic itself, on the front page's bounty panel and on `/ingenic/bounties`, and a member who is not you sees no way to withdraw it
- [ ] accepting an answer on that topic pays the answerer in full, closes the offer, and the topic then says what was paid and to whom
- [ ] withdrawing a standing offer hands the points back, and one nobody answers comes back on its own within the hour after `ingenic_bounty_expiry_days`
- [ ] `/ingenic/boards` shows boards, and a board with a purchase link shows a **Buy now** button
- [ ] the header shows a language switcher at its right end — beside **Log in** when signed out, beside the avatar when signed in; picking **中文** reloads the page in Chinese, and picking **English** brings it back
- [ ] the same switch works when signed in — the choice then survives signing out and back in
- [ ] the Ingenic navigation appears in the sidebar, and in the mobile drawer on a phone
- [ ] a docs URL can be pasted into a fresh tab and opens directly
- [ ] `/` is the front page: banner, the five tool links, and the section cards — with **no** topic list and no latest/hot tabs on it
- [ ] choosing **Latest** in the navigation goes to the topic list and the front page is still there when you come back to it
- [ ] the **All sections** link at the end of the section block opens `/categories`
- [ ] a section card links into its own category
- [ ] the promotions you configured in **Ingenic → Site** appear on the front page if you added a `promotions` block
- [ ] the footer shows the partner platform strip — a link for one kind, a scannable code for the other — and the link columns you configured
- [ ] with `enable_powered_by_discourse` off, the page ends at that footer and the **Powered by Discourse** line is gone
- [ ] a member of a listed `ingenic_official_groups` group wears its badge beside their username, and a member who picked a badge of their own keeps it
- [ ] Google, GitHub and email sign-in all still work
- [ ] **Admin → Customize → Themes** shows no theme errors

`bundle exec rspec plugins/discourse-ingenic/spec` runs the plugin's spec suite
inside the container and is the fastest way to check the endpoints.

---

## 6. Rollback

- **Theme**: switch the default theme back in **Admin → Customize → Themes**.
  No rebuild, no downtime.
- **Plugin**: remove the `git clone` line from `app.yml` (or the directory from
  `plugins/`) and rebuild. The plugin's tables are left in place — they are
  named `ingenic_*` and nothing else reads them, so leaving them costs nothing
  and keeps the content if you reinstall.

---

## 7. Moving a configuration to another machine

Two things make up this forum's configuration: the plugin's settings and content,
and the theme's settings. They are exported separately because they belong to
different objects.

### Theme settings

**Admin → Customize → Themes → Ingenic Community → Export** writes a zip whose
settings field carries the values currently in the theme, so importing that zip
on another machine brings the theme's settings with it. Nothing else is in there
— the theme's files come from this repository.

### Plugin settings and content

```bash
cd /var/www/discourse

# write everything this plugin owns into one file
rake ingenic:export_config[/shared/ingenic-config.yml]

# see what a file holds, without touching anything
rake ingenic:show_config[/shared/ingenic-config.yml]

# apply it — the second argument rolls the whole thing back afterwards
rake ingenic:import_config[/shared/ingenic-config.yml,dry]
rake ingenic:import_config[/shared/ingenic-config.yml]
```

The file holds the plugin's site settings (the ones you changed, not the ones
still on their defaults) and the content an administrator typed in: the product
tree, versions, pages, the download catalogue and its categories, boards,
documentation permissions, promotions, the footer, social links and point rules.

It deliberately holds **nothing members produced**. Point balances, point
entries, bounties, download applications, access grants, developer profiles and
the download record are a record of what people did, and one of those tables
holds personal data about them. A copy of that is a database dump, which is a
different thing with a different lifetime; take one of those if you need it.

`import_config` is an upsert by natural key — a product is identified by its
slug and locale, a version by its product and slug, and so on — so importing the
same file twice changes nothing the second time. It never deletes: a row that
exists in the forum but not in the file is left alone and reported as
`Left alone` at the end, for you to decide about. The whole import runs in one
transaction, so a file it refuses leaves the forum exactly as it was.

Uploaded SDK and firmware files are not in the file either — only the rows that
point at them, including the path each upload was written to. A machine whose
download directory was copied across restores to a working download centre; a
machine without those files gets rows pointing at files that are not there.

### After any deployment

```bash
rake ingenic:doctor
```

It checks the handful of settings whose wrong value produces no error anywhere —
the plugin switched off, a language nobody can switch, a download directory
nothing can be written to — and names what to change.

---

## What has and has not been tested

Not tested in a running Discourse. There is no Ruby, no bundler and no database
in the environment this was built in, so:

- the plugin's spec suite is written but has never been executed
- the theme has never been compiled by Discourse's asset pipeline
- nothing has been rendered in a browser
- the bounty table has never been created by a migration, and the hourly job that
  expires offers has never fired — the escrow, the release and the refund are
  covered by specs, but no points have moved for real
- no account has been deleted from a real forum, so the keys that let a member's
  rows stay behind have only been checked against the migrations that write them

What *was* done: every file was parsed (Babel and Glimmer for the theme's
JavaScript, tree-sitter for Ruby, a YAML parser for the settings and locale
files), and every Discourse API used was read in the `2026.10.0-latest` source
to confirm the signature — `api.addSidebarSection`, the custom sidebar section
and link base classes, the order in which theme route maps are merged, and the
path that turns theme settings into SCSS variables.

Expect the first rebuild to be where anything that is wrong shows up. If the
theme reports a compile error, it will name the file and line in
**Admin → Customize → Themes**.
