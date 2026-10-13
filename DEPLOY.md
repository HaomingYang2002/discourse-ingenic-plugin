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

The rebuild runs the plugin's migration and creates its five tables. It takes a
few minutes, and the forum is offline while it runs — there is no zero-downtime
rebuild in `discourse_docker`.

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

`ingenic_nav_items` and `ingenic_homepage_blocks` are JSON. Both are optional —
with `ingenic_nav_items` left empty the theme falls back to its shipped
navigation (Home, Documentation, Downloads, Development Boards).

A starting `ingenic_nav_items`:

```json
[
  { "key": "home",      "label": "Home",                 "icon": "house",     "href": "/",               "position": 0, "enabled": true },
  { "key": "announce",  "label": "Official Announcements", "icon": "bullhorn", "category": "official-announcements", "position": 1, "enabled": true },
  { "key": "discuss",   "label": "Technical Discussions",  "icon": "comments", "category": "technical-discussions",  "position": 2, "enabled": true },
  { "key": "docs",      "label": "Documentation",        "icon": "book",      "href": "/ingenic/docs",   "position": 3, "enabled": true },
  { "key": "downloads", "label": "Downloads",            "icon": "download",  "href": "/ingenic/downloads", "position": 4, "enabled": true },
  { "key": "boards",    "label": "Development Boards",   "icon": "microchip", "href": "/ingenic/boards", "position": 5, "enabled": true }
]
```

`category` entries resolve to `/c/<slug>`, so navigation can point at a forum
section instead of a URL. Each chip gets its own category, and its own
documentation entry pointing at that chip's `/ingenic/docs/<product>`.

A starting `ingenic_homepage_blocks`:

```json
[
  { "type": "search",        "enabled": true, "position": 0 },
  { "type": "announcements", "enabled": true, "position": 1, "limit": 5,  "category": "official-announcements" },
  { "type": "discussions",   "enabled": true, "position": 2, "limit": 10, "category": "technical-discussions" },
  { "type": "downloads",     "enabled": true, "position": 3, "limit": 6 },
  { "type": "boards",        "enabled": true, "position": 4, "limit": 4 }
]
```

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

Documentation, downloads and boards can now be managed from the Discourse admin
plugin page rather than only from Rails Console. Open **Admin → Plugins → Ingenic**
to manage products, versions, Markdown pages, development boards, and scoped
permissions. A product-family grant is inherited by its versions and pages; a
page grant is limited to that page and its child pages. Assignments can target a
user or group, and the server enforces every write operation.

Use `docs/seeding.md` for console examples and migration/bootstrap workflows.
The console remains useful for bulk imports, but normal editing should use the
management pages.

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
- [ ] the page tree expands, and previous/next move through the pages in order
- [ ] the version picker switches versions and stays on the same page where it exists
- [ ] `/ingenic/downloads` filters by product, type, version and platform
- [ ] `/ingenic/boards` shows boards, and the apply button opens a new tab
- [ ] the Ingenic navigation appears in the sidebar, and in the mobile drawer on a phone
- [ ] a docs URL can be pasted into a fresh tab and opens directly
- [ ] `/` shows the Chinese-forum-style hero, quick links and homepage blocks above the topic list
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
