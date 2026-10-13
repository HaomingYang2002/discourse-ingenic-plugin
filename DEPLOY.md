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
   separate brand-colour setting.
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

`ingenic_nav_items` and `ingenic_homepage_blocks` are JSON. Both are optional —
with `ingenic_nav_items` left empty the theme falls back to its shipped
navigation (Documentation, Downloads, Development Boards, Points).

**A configured `ingenic_nav_items` replaces the shipped list wholesale**, it does
not merge with it. So a site that configured its navigation before Points
existed has no Points entry and will not grow one: add it to the JSON, or clear
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
  { "key": "points",    "label": "Points",               "icon": "star",      "href": "/ingenic/points", "position": 6, "enabled": true }
]
```

`category` entries resolve to `/c/<slug>`, so navigation can point at a forum
section instead of a URL. Each chip gets its own category, and its own
documentation entry pointing at that chip's `/ingenic/docs/<product>`.

A starting `ingenic_homepage_blocks`:

```json
[
  { "type": "promotions",    "enabled": true, "position": 0 },
  { "type": "search",        "enabled": true, "position": 1 },
  { "type": "announcements", "enabled": true, "position": 2, "limit": 5,  "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 3, "limit": 10, "category": "technical-discussions" },
  { "type": "downloads",     "enabled": true, "position": 4, "limit": 6 },
  { "type": "boards",        "enabled": true, "position": 5, "limit": 4 }
]
```

`promotions` draws the activity slots managed in **Ingenic → Site → Promotions**;
with no promotions configured the block renders nothing. A supported type with
no component behind it also renders nothing, so a mistyped name is a block that
silently never appears.

### Theme settings

| Setting | Default | Effect |
| --- | --- | --- |
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
- [ ] with `ingenic_points_enabled` off, a priced resource downloads free and nobody earns anything; the balances are still there when it goes back on
- [ ] `/ingenic/boards` shows boards, and a board with a purchase link shows a **Buy now** button
- [ ] the Ingenic navigation appears in the sidebar, and in the mobile drawer on a phone
- [ ] a docs URL can be pasted into a fresh tab and opens directly
- [ ] `/` shows the homepage blocks above the topic list, and the promotions you configured in **Ingenic → Site**
- [ ] the footer shows the partner platform strip — a link for one kind, a scannable code for the other — and the link columns you configured
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

## What has and has not been tested

Not tested in a running Discourse. There is no Ruby, no bundler and no database
in the environment this was built in, so:

- the plugin's spec suite is written but has never been executed
- the theme has never been compiled by Discourse's asset pipeline
- nothing has been rendered in a browser

What *was* done: every file was parsed (Babel and Glimmer for the theme's
JavaScript, tree-sitter for Ruby, a YAML parser for the settings and locale
files), and every Discourse API used was read in the `2026.10.0-latest` source
to confirm the signature — `api.addSidebarSection`, the custom sidebar section
and link base classes, the order in which theme route maps are merged, and the
path that turns theme settings into SCSS variables.

Expect the first rebuild to be where anything that is wrong shows up. If the
theme reports a compile error, it will name the file and line in
**Admin → Customize → Themes**.
