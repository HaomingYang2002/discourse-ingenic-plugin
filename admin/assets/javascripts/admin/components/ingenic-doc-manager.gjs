import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import IngenicDocPageForm from "./ingenic-doc-page-form";
import IngenicDocPageTree from "./ingenic-doc-page-tree";

const BASE = "/admin/plugins/discourse-ingenic";

// A version sits at depth 2 (series 0, chip 1); its pages start one indent
// step below it. The page tree adds this to each page's own depth, so the
// first level of pages lands on the same indent scale as the rows above.
const PAGE_INDENT_BASE = 3;

/**
 * Authoring workbench for the documentation tree.
 *
 * The whole hierarchy lives in the left pane: series, the chips under each
 * series, the versions under each chip, and — once a version is opened — its
 * pages. Every level can be created, renamed, moved and deleted there, so the
 * old top bar that selected one series/chip/version at a time had nothing left
 * to do. What survives is the language filter above the tree, which only hides
 * version rows of other languages.
 *
 * Series and chips are expanded by default, versions are collapsed until their
 * pages are asked for: a site with a few dozen chips should not fetch every
 * manual's page tree on load. A version's pages are cached by id, so folding
 * and unfolding it costs one request, not one per click.
 *
 * Moving is drag-only, as a file manager does it: a grip lifts a row, the top
 * or bottom half of a sibling row decides before/after, and the middle of a
 * parent row — a chip dropped on a series, a version dropped on a chip — files
 * the row under it at the end of that list. Reordering sends the whole list in
 * one request, in one transaction.
 */
export default class IngenicDocManager extends Component {
  @tracked series = this.args.series;

  // Documentation is written per language, so the workbench shows exactly one
  // language's tree: the site's default until the editor picks another. There
  // is no mixed view. `null` only happens before any language is known, and
  // `activeLanguage` resolves it to the first option.
  @tracked languageFilter = this.args.defaultLocale ?? null;

  // Series and chips expand by default, so this records the folded ones.
  @tracked collapsedProducts = new Set();

  // Versions collapse by default, so this records the opened ones.
  @tracked expandedVersions = new Set();

  @tracked pagesByVersion = {};
  @tracked loadingVersions = new Set();

  // The version whose pages are on screen and, within it, the selected page.
  @tracked selectedVersionId = null;
  @tracked selectedPageSlug = null;
  @tracked selectedNodeKey = null;

  // The version row whose + menu (article/folder) is open.
  @tracked addMenuKey = null;

  @tracked busy = false;
  @tracked error = null;
  @tracked importMessage = null;

  // { kind: "series" | "chip" | "version", action: "create" | "edit", record }
  @tracked drawer = null;

  // What the create drawer's parent pickers start on. They are editable, not
  // read-only: the row being added can be filed somewhere other than the row
  // whose + was pressed, and choosing a series narrows the chip list.
  @tracked formLocale = null;
  @tracked formSeriesId = null;
  @tracked formChipId = null;

  // The row in hand and the row it is over: { key, kind, record } and
  // { key, mode: "before" | "after" | "into" }.
  @tracked drag = null;
  @tracked drop = null;

  // The page trees register their inline-create entry here, keyed by version.
  treeApis = new Map();

  // A response for a tree that was requested before the last one is stale —
  // folding and unfolding quickly, or reloading after a language change, can
  // deliver the older tree last.
  treeTokens = new Map();

  get selectedVersion() {
    return this.#versionById(this.selectedVersionId);
  }

  get selectedPage() {
    const pages = this.selectedVersion
      ? this.pagesFor(this.selectedVersion)
      : [];

    return pages.find((page) => page.slug === this.selectedPageSlug) ?? null;
  }

  get noSeries() {
    return this.series.length === 0;
  }

  get drawerTitle() {
    if (!this.drawer) {
      return "";
    }

    return i18n(
      `admin.ingenic.documentation.workbench.${this.drawer.action}_${this.drawer.kind}`
    );
  }

  // Editing uses the row's own language; creating starts where the row whose +
  // was pressed says.
  get drawerLocale() {
    return this.drawer?.record?.locale ?? this.formLocale ?? null;
  }

  // A new series or chip starts out published; an existing one keeps whatever
  // it has. The checkbox has to show the same thing the request will send.
  get drawerPublished() {
    return this.drawer?.record?.published ?? true;
  }

  // The chips the create drawer can file a version under. It follows the
  // series picker above it, so changing that picker cannot leave a version
  // pointing at a chip from another series.
  get formChips() {
    return this.series.find((entry) => entry.id === this.formSeriesId)?.chips ?? [];
  }

  get formHasNoChips() {
    return this.formChips.length === 0;
  }

  // Every language the forum serves, plus any language a row still carries:
  // values written before the default was fixed must stay reachable, or saving
  // another field would silently move the row.
  get languageOptions() {
    const served = this.args.locales ?? [];
    const values = served.map((locale) => locale.value);

    for (const series of this.series) {
      values.push(this.#localeOf(series));

      for (const chip of series.chips ?? []) {
        values.push(this.#localeOf(chip));

        for (const version of chip.versions ?? []) {
          values.push(this.#localeOf(version));
        }
      }
    }

    if (this.args.defaultLocale) {
      values.push(this.args.defaultLocale);
    }

    const unique = [...new Set(values.filter(Boolean))];

    return unique.map((value) => ({ value, name: this.#localeName(value) }));
  }

  // The language whose tree is on screen: the editor's pick, or the first
  // known language before one was made. Row filtering and every create default
  // go through this, so the tree can never mix two languages.
  get activeLanguage() {
    return this.languageFilter ?? this.languageOptions[0]?.value ?? null;
  }

  get selectedLanguage() {
    return this.activeLanguage ?? "";
  }

  // The flat list the template renders. Pages are a marker row, not nested
  // markup: a version and its page tree are two rows in the same list, and the
  // subtree is rendered when the marker is reached.
  get structureRows() {
    const rows = [];

    for (const series of this.#visibleSeries()) {
      const seriesKey = this.#keyOf("series", series);
      const seriesOpen = !this.collapsedProducts.has(seriesKey);
      rows.push(this.#rowFor("series", series, 0, seriesOpen));

      if (!seriesOpen) {
        continue;
      }

      const chips = this.#visibleChips(series);

      if (chips.length === 0) {
        // The series may simply have no chip in the selected language, which
        // is a different situation from a brand new, empty series.
        const hint =
          this.activeLanguage && (series.chips ?? []).length > 0
            ? "no_chips_in_locale"
            : "no_chips_in_series";

        rows.push(this.#hintRow(`${seriesKey}-empty`, 1, hint));
        continue;
      }

      for (const chip of chips) {
        const chipKey = this.#keyOf("chip", chip);
        const versions = this.#visibleVersions(chip);
        // A chip whose versions are all hidden by the language filter stays
        // open even if it was folded: otherwise it would show no chevron, no
        // rows and no hint, and there would be nothing to act on.
        const chipOpen =
          !this.collapsedProducts.has(chipKey) || versions.length === 0;
        rows.push(this.#rowFor("chip", chip, 1, chipOpen));

        if (!chipOpen) {
          continue;
        }

        if (versions.length === 0) {
          rows.push(
            this.#hintRow(
              `${chipKey}-empty`,
              2,
              this.activeLanguage ? "no_versions_in_locale" : "empty_version"
            )
          );
        }

        for (const version of versions) {
          const expanded = this.expandedVersions.has(version.id);
          rows.push(this.#rowFor("version", version, 2, expanded));

          if (expanded) {
            rows.push({
              key: `pages-${version.id}`,
              kind: "pages",
              record: version,
              depth: PAGE_INDENT_BASE,
            });
          }
        }
      }
    }

    return rows;
  }

  #rowFor(kind, record, depth, expanded) {
    const key = this.#keyOf(kind, record);
    const latest = kind === "version" && record.latest;

    return {
      key,
      kind,
      record,
      depth,
      expanded,
      writable: record.writable ?? true,
      // The tree shows one language at a time, so a row needs no badge; the
      // latest version is marked the way the old version selector did, in the
      // title itself.
      label:
        kind === "version"
          ? [record.label, latest && i18n("admin.ingenic.documentation.latest")]
              .filter(Boolean)
              .join(" · ")
          : record.name,
      addTitle: i18n(
        `admin.ingenic.documentation.workbench.add_${kind === "series" ? "chip" : kind === "chip" ? "version" : "page"}`
      ),
      // A version always has a page tree to open, even when it is empty.
      hasChildren:
        kind === "version"
          ? true
          : kind === "series"
            ? this.#visibleChips(record).length > 0
            : this.#visibleVersions(record).length > 0,
      isSelected: key === this.selectedNodeKey,
      isDragging: this.drag?.key === key,
      isDropBefore: this.drop?.key === key && this.drop.mode === "before",
      isDropAfter: this.drop?.key === key && this.drop.mode === "after",
      isDropInto: this.drop?.key === key && this.drop.mode === "into",
      addMenuOpen: this.addMenuKey === key,
    };
  }

  #hintRow(key, depth, textKey) {
    return {
      key,
      kind: "hint",
      depth,
      text: i18n(`admin.ingenic.documentation.workbench.${textKey}`),
    };
  }

  #keyOf(kind, record) {
    return `${kind}-${record.id}`;
  }

  #compareRows(a, b) {
    return (a.position ?? 0) - (b.position ?? 0) || a.id - b.id;
  }

  #orderedSeries() {
    return [...this.series].sort((a, b) => this.#compareRows(a, b));
  }

  #orderedChips(series) {
    return [...(series?.chips ?? [])].sort((a, b) => this.#compareRows(a, b));
  }

  // Positions are chip-global and shared by every language, so a move always
  // sees the full list — filtering the view must not renumber half of it.
  #versionsOf(chip) {
    return [...(chip?.versions ?? [])].sort((a, b) => this.#compareRows(a, b));
  }

  #localeMatches(record) {
    const locale = this.activeLanguage;

    return !locale || this.#localeOf(record) === locale;
  }

  #visibleVersions(chip) {
    return this.#versionsOf(chip).filter((version) =>
      this.#localeMatches(version)
    );
  }

  // A chip belongs to the language on its own row, and is also shown when it
  // holds versions in the selected language — older data can mix the two, and
  // hiding the parent would strand those versions with no row to live under.
  #visibleChips(series) {
    return this.#orderedChips(series).filter(
      (chip) =>
        this.#localeMatches(chip) || this.#visibleVersions(chip).length > 0
    );
  }

  #visibleSeries() {
    return this.#orderedSeries().filter(
      (series) =>
        this.#localeMatches(series) || this.#visibleChips(series).length > 0
    );
  }

  #seriesOfChip(chipId) {
    return (
      this.series.find((series) =>
        (series.chips ?? []).some((chip) => chip.id === chipId)
      ) ?? null
    );
  }

  #chipById(chipId) {
    for (const series of this.series) {
      const chip = (series.chips ?? []).find((entry) => entry.id === chipId);

      if (chip) {
        return chip;
      }
    }

    return null;
  }

  #chipOfVersion(versionId) {
    for (const series of this.series) {
      for (const chip of series.chips ?? []) {
        if ((chip.versions ?? []).some((version) => version.id === versionId)) {
          return chip;
        }
      }
    }

    return null;
  }

  #versionById(versionId) {
    if (!versionId) {
      return null;
    }

    for (const series of this.series) {
      for (const chip of series.chips ?? []) {
        const version = (chip.versions ?? []).find(
          (entry) => entry.id === versionId
        );

        if (version) {
          return version;
        }
      }
    }

    return null;
  }

  #seriesIdOfChip(chipId) {
    return this.#seriesOfChip(chipId)?.id ?? null;
  }

  // Rows written before the language default was fixed may have no locale at
  // all. The documentation default is the language they were meant for.
  #localeOf(record) {
    return record?.locale || this.args.defaultLocale || "";
  }

  #localeName(value) {
    return (
      (this.args.locales ?? []).find((locale) => locale.value === value)?.name ??
      value
    );
  }

  pagesFor(version) {
    return this.pagesByVersion[version.id] ?? [];
  }

  // Only a tree with nothing to show yet displays the loading line. Re-fetching
  // after a save keeps the current rows mounted, so the inline editor and the
  // page's scroll position survive the round trip.
  isLoading(version) {
    return (
      this.loadingVersions.has(version.id) && !this.pagesByVersion[version.id]
    );
  }

  @action
  async reload() {
    const payload = await ajax(`${BASE}/documentation`);
    this.series = payload.series;

    // Prune what the server no longer has: a deleted version must not keep a
    // cached tree, an expanded flag, or the editor's selection.
    const liveVersions = new Set();

    for (const series of this.series) {
      for (const chip of series.chips ?? []) {
        for (const version of chip.versions ?? []) {
          liveVersions.add(version.id);
        }
      }
    }

    this.expandedVersions = new Set(
      [...this.expandedVersions].filter((id) => liveVersions.has(id))
    );

    const pages = {};

    for (const [id, rows] of Object.entries(this.pagesByVersion)) {
      if (liveVersions.has(Number(id))) {
        pages[id] = rows;
      }
    }

    this.pagesByVersion = pages;

    if (this.selectedVersionId && !liveVersions.has(this.selectedVersionId)) {
      this.selectedVersionId = null;
      this.selectedPageSlug = null;
      this.selectedNodeKey = null;
    }
  }

  @action
  selectLanguage(event) {
    this.languageFilter = event.target.value || null;

    // The editor can stay on a version the filter just hid; keeping the
    // selection is fine, but it must not look like the row vanished.
    if (
      this.activeLanguage &&
      this.selectedVersion &&
      this.#localeOf(this.selectedVersion) !== this.activeLanguage
    ) {
      this.selectedVersionId = null;
      this.selectedPageSlug = null;
      this.selectedNodeKey = null;
    }
  }

  // ---------------------------------------------------------------- files ---

  @action
  async loadPages(version) {
    const token = (this.treeTokens.get(version.id) ?? 0) + 1;
    this.treeTokens.set(version.id, token);
    this.loadingVersions = new Set(this.loadingVersions).add(version.id);

    try {
      // The server resolves the tree in the version's own language, not the
      // admin's UI language.
      const locale = this.#localeOf(version);
      const query = locale ? `?locale=${encodeURIComponent(locale)}` : "";
      const payload = await ajax(
        `${BASE}/documentation/versions/${version.id}/tree${query}`
      );

      if (this.treeTokens.get(version.id) !== token) {
        return;
      }

      this.pagesByVersion = { ...this.pagesByVersion, [version.id]: payload.pages };
    } catch (error) {
      if (this.treeTokens.get(version.id) === token) {
        this.error = this.#errorMessage(error);
      }
    } finally {
      if (this.treeTokens.get(version.id) === token) {
        const next = new Set(this.loadingVersions);
        next.delete(version.id);
        this.loadingVersions = next;
      }
    }
  }

  async #ensurePages(version) {
    if (!this.pagesByVersion[version.id]) {
      await this.loadPages(version);
    }
  }

  @action
  toggleRow(row) {
    if (row.kind === "version") {
      this.#toggleVersion(row.record);
    } else {
      this.#toggleProduct(row.record);
    }
  }

  #toggleProduct(record) {
    const key = this.#keyOf(record.kind, record);
    const next = new Set(this.collapsedProducts);

    if (next.has(key)) {
      next.delete(key);
    } else {
      next.add(key);
    }

    this.collapsedProducts = next;
  }

  #toggleVersion(version) {
    const next = new Set(this.expandedVersions);

    if (next.has(version.id)) {
      next.delete(version.id);
      // The tree unmounts; drop its inline-create entry as well.
      this.treeApis.delete(version.id);
    } else {
      next.add(version.id);
      this.#ensurePages(version);
    }

    this.expandedVersions = next;
  }

  // Clicking a series or chip name folds it; clicking a version name opens it
  // (the chevron is the control that folds it again).
  @action
  openRow(row) {
    this.selectedNodeKey = row.key;
    this.addMenuKey = null;

    if (row.kind === "version") {
      if (this.selectedVersionId !== row.record.id) {
        this.selectedVersionId = row.record.id;
        this.selectedPageSlug = null;
      }

      if (!this.expandedVersions.has(row.record.id)) {
        this.expandedVersions = new Set(this.expandedVersions).add(
          row.record.id
        );
        this.#ensurePages(row.record);
      }
    } else {
      this.#toggleProduct(row.record);
    }
  }

  @action
  addChild(row) {
    this.selectedNodeKey = row.key;

    if (row.kind === "series") {
      this.openDrawer("chip", "create", null, row.record);
    } else if (row.kind === "chip") {
      this.openDrawer("version", "create", null, row.record);
    } else {
      this.addMenuKey = this.addMenuKey === row.key ? null : row.key;
    }
  }

  // A version row's + asks the page tree to insert its draft row. Opening the
  // tree first means waiting for the pages to exist in the DOM.
  @action
  async startPageDraft(version, kind) {
    this.addMenuKey = null;

    if (!this.expandedVersions.has(version.id)) {
      this.expandedVersions = new Set(this.expandedVersions).add(version.id);
    }

    if (!this.pagesByVersion[version.id]) {
      await this.loadPages(version);
    }

    requestAnimationFrame(() => {
      this.treeApis.get(version.id)?.startDraft(null, kind);
    });
  }

  // ------------------------------------------------------------ page CRUD ---

  @action
  selectPage(version, page) {
    this.selectedVersionId = version.id;
    this.selectedPageSlug = page.slug;
    this.selectedNodeKey = this.#keyOf("version", version);
    this.addMenuKey = null;
  }

  @action
  registerTree(version, api) {
    if (api) {
      this.treeApis.set(version.id, api);
    } else {
      this.treeApis.delete(version.id);
    }
  }

  @action
  async createPage(version, parent, kind, title) {
    const name = title?.trim();

    if (!name) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const response = await ajax(`${BASE}/documentation/pages`, {
        type: "POST",
        data: {
          title: name,
          slug: this.#slugFor(name),
          kind,
          parent_id: parent?.id ?? null,
          locale: this.#localeOf(version),
          published: true,
          body: kind === "folder" ? null : "",
          version_id: version.id,
        },
      });

      await this.loadPages(version);

      if (response?.page?.slug) {
        this.selectedVersionId = version.id;
        this.selectedPageSlug = response.page.slug;
      }
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async renamePage(version, page, title) {
    const name = title?.trim();

    if (!name || name === page.title) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const owned = await this.#ownPage(version, page);
      await ajax(`${BASE}/documentation/pages/${owned.id}`, {
        type: "PUT",
        data: { title: name },
      });
      await this.loadPages(version);
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // A row this version only inherits is edited like any other. The first write
  // copies it into this version and the write lands on the copy, so the earlier
  // version keeps its text and the user never meets the word "inherit".
  async #ownPage(version, page) {
    if (!page.inherited) {
      return page;
    }

    const response = await ajax(
      `${BASE}/documentation/versions/${version.id}/pages/${page.slug}/override`,
      { type: "POST", data: { locale: this.#localeOf(version) } }
    );

    return response?.page ?? page;
  }

  // A Latin title keeps a readable slug. A Chinese one has nothing to
  // transliterate in the browser, so it gets a short fallback. The slug is
  // derived once, never asked for again, and only has to be unique within the
  // version and locale.
  #slugFor(title) {
    const ascii = title
      .normalize("NFKD")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");

    return ascii || `page-${Math.random().toString(36).slice(2, 8)}`;
  }

  @action
  async savePage(version, page, values) {
    this.busy = true;
    this.error = null;

    try {
      const owned = await this.#ownPage(version, page);
      await ajax(`${BASE}/documentation/pages/${owned.id}`, {
        type: "PUT",
        data: values,
      });
      await this.loadPages(version);
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Dragging does both structural jobs the tree offers. Dropping on a row's
  // upper or lower half reorders it among that parent's children; dropping on
  // the middle of a folder moves it inside the folder. The second is the only
  // way to change a page's parent now that the editor no longer has a picker.
  @action
  async dropPage(version, dragged, target, after, into) {
    if (!dragged || !target || dragged.id === target.id || dragged.inherited) {
      return;
    }

    const pages = this.pagesFor(version);

    if (into) {
      if (
        target.kind !== "folder" ||
        this.#descendantSlugs(pages, dragged.slug).has(target.slug)
      ) {
        return;
      }

      await this.#movePageUnder(version, dragged, target);
      return;
    }

    if (
      target.inherited ||
      (dragged.parent_slug ?? null) !== (target.parent_slug ?? null)
    ) {
      return;
    }

    const siblings = pages.filter(
      (entry) =>
        (entry.parent_slug ?? null) === (dragged.parent_slug ?? null) &&
        !entry.inherited
    );
    const reordered = siblings.filter((entry) => entry.id !== dragged.id);
    const index = reordered.findIndex((entry) => entry.id === target.id);

    if (index < 0) {
      return;
    }

    reordered.splice(after ? index + 1 : index, 0, dragged);

    this.busy = true;
    this.error = null;

    try {
      await Promise.all(
        reordered.map((entry, position) =>
          ajax(`${BASE}/documentation/pages/${entry.id}`, {
            type: "PUT",
            data: { position },
          })
        )
      );
      await this.loadPages(version);
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // Appends the page to the folder's children. A folder lower in the tree than
  // the page is fine; one inside the page's own subtree is refused above,
  // because a loop in the parent chain makes every tree walk recurse forever.
  async #movePageUnder(version, page, folder) {
    const pages = this.pagesFor(version);
    const children = pages.filter(
      (entry) => entry.parent_id === folder.id && entry.id !== page.id
    );
    const position = children.length
      ? Math.max(...children.map((entry) => entry.position ?? 0)) + 1
      : 0;

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, {
        type: "PUT",
        data: { parent_id: folder.id, position },
      });
      await this.loadPages(version);
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  #descendantSlugs(pages, slug) {
    const found = new Set();
    let changed = true;

    while (changed) {
      changed = false;

      for (const entry of pages) {
        if (
          entry.parent_slug &&
          (entry.parent_slug === slug || found.has(entry.parent_slug)) &&
          !found.has(entry.slug)
        ) {
          found.add(entry.slug);
          changed = true;
        }
      }
    }

    return found;
  }

  @action
  async destroyPage(version, page) {
    // The row belongs to another version. Deleting it here would delete it
    // from that version (and from every version inheriting it), not from this
    // one, so the request is refused with a sentence that says where to go.
    if (page.inherited) {
      this.error = i18n(
        "admin.ingenic.documentation.workbench.inherited_delete_blocked"
      );
      return;
    }

    if (!window.confirm(i18n("admin.ingenic.documentation.delete_page_confirm"))) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, { type: "DELETE" });

      if (this.selectedPageSlug === page.slug) {
        this.selectedPageSlug = null;
      }

      await this.loadPages(version);
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async importPages(event) {
    event.preventDefault();

    if (!this.selectedVersion) {
      return;
    }

    const version = this.selectedVersion;
    this.busy = true;
    this.error = null;
    this.importMessage = null;

    try {
      const response = await ajax(
        `${BASE}/documentation/versions/${version.id}/import`,
        {
          type: "POST",
          data: new FormData(event.target),
          processData: false,
          contentType: false,
        }
      );

      this.importMessage = i18n("admin.ingenic.documentation.imported", {
        count: response.imported?.length ?? 0,
      });

      if (response.errors?.length) {
        this.error = response.errors
          .map((entry) => `${entry.file}: ${entry.error}`)
          .join("; ");
      }

      event.target.reset();
      await this.loadPages(version);
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // -------------------------------------------------------------- dragging ---

  @action
  startDrag(row, event) {
    if (!row.writable) {
      return;
    }

    this.drag = { key: row.key, kind: row.kind, record: row.record };
    event.dataTransfer.effectAllowed = "move";
    // Firefox refuses to start a drag without payload, even when the payload
    // is never read.
    event.dataTransfer.setData("text/plain", row.key);
  }

  @action
  dragOver(row, event) {
    const drag = this.drag;

    // Ids are per table, so a chip and a series can both be #1; the kind has
    // to match before the two rows can be called the same row.
    if (
      !drag ||
      (drag.kind === row.kind && drag.record.id === row.record?.id)
    ) {
      return;
    }

    if (!["series", "chip", "version"].includes(row.kind)) {
      return;
    }

    const into = this.#dropIntoAllowed(drag, row);
    const sibling = this.#siblingDropAllowed(drag, row);

    if (!into && !sibling) {
      return;
    }

    event.preventDefault();
    event.dataTransfer.dropEffect = "move";

    if (into) {
      this.drop = { key: row.key, mode: "into" };
      return;
    }

    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = (event.clientY - rect.top) / Math.max(rect.height, 1);
    this.drop = { key: row.key, mode: ratio > 0.5 ? "after" : "before" };
  }

  // Moving into a child element fires a dragleave on the row; only a leave
  // that actually exits the row clears the highlight.
  @action
  dragLeave(row, event) {
    if (
      this.drop?.key === row.key &&
      !event.currentTarget.contains(event.relatedTarget)
    ) {
      this.drop = null;
    }
  }

  // A chip dropped on a series, or a version dropped on a chip, is filed at
  // the end of that parent. Its own parent is not a target — that would be a
  // no-op that reads as a failed drop.
  #dropIntoAllowed(drag, row) {
    // Filing a row under a parent the account cannot write would only fail on
    // the server, so the row refuses the drop up front.
    if (!row.writable) {
      return false;
    }

    if (drag.kind === "chip" && row.kind === "series") {
      return drag.record.parent_id !== row.record.id;
    }

    if (drag.kind === "version" && row.kind === "chip") {
      return drag.record.product_id !== row.record.id;
    }

    return false;
  }

  #siblingDropAllowed(drag, row) {
    if (drag.kind !== row.kind) {
      return false;
    }

    if (drag.kind === "chip") {
      return drag.record.parent_id === row.record.parent_id;
    }

    if (drag.kind === "version") {
      return drag.record.product_id === row.record.product_id;
    }

    return true;
  }

  @action
  async dropOn(row, event) {
    event.preventDefault();

    const drag = this.drag;
    const mode = this.drop?.mode;

    this.endDrag();

    if (!drag || !mode) {
      return;
    }

    if (mode === "into") {
      await this.#moveInto(drag, row.record);
    } else {
      await this.#reorderBeside(drag, row.record, mode === "after");
    }
  }

  @action
  endDrag() {
    this.drag = null;
    this.drop = null;
  }

  async #reorderBeside(drag, target, after) {
    let rows;

    if (drag.kind === "series") {
      rows = this.#orderedSeries();
    } else if (drag.kind === "chip") {
      // The chip itself is what identifies its series; `parent_id` on a chip is
      // already the series id, not a chip id.
      rows = this.#orderedChips(this.#seriesOfChip(drag.record.id));
    } else {
      rows = this.#versionsOf(this.#chipOfVersion(drag.record.id));
    }

    const reordered = rows.filter((entry) => entry.id !== drag.record.id);
    const index = reordered.findIndex((entry) => entry.id === target.id);

    if (index < 0) {
      return;
    }

    reordered.splice(after ? index + 1 : index, 0, drag.record);

    if (drag.kind === "version") {
      await this.#persistVersionOrder(
        drag.record.product_id,
        drag.record,
        reordered
      );
    } else {
      const parentId = drag.kind === "series" ? null : drag.record.parent_id;
      await this.#persistProductOrder(drag.kind, parentId, drag.record, reordered);
    }
  }

  async #moveInto(drag, target) {
    this.busy = true;
    this.error = null;

    try {
      if (drag.kind === "chip") {
        await ajax(`${BASE}/documentation/products/${drag.record.id}`, {
          type: "PUT",
          data: { parent_id: target.id },
        });
        this.#expandProductKeys([this.#keyOf("series", target)]);
      } else {
        await ajax(`${BASE}/documentation/versions/${drag.record.id}`, {
          type: "PUT",
          data: { product_id: target.id },
        });

        const series = this.#seriesOfChip(target.id);
        this.#expandProductKeys(
          [this.#keyOf("chip", target), series && this.#keyOf("series", series)]
        );
      }

      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
      await this.reload();
    } finally {
      this.busy = false;
    }
  }

  #expandProductKeys(keys) {
    const next = new Set(this.collapsedProducts);
    keys.filter(Boolean).forEach((key) => next.delete(key));
    this.collapsedProducts = next;
  }

  async #persistProductOrder(kind, parentId, moved, rows) {
    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/reorder/products`, {
        type: "PUT",
        data: {
          kind,
          parent_id: parentId,
          moved_id: moved.id,
          ids: rows.map((row) => row.id),
        },
      });
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }

    // The screen always shows what the server has, including after a failed
    // move.
    try {
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    }
  }

  async #persistVersionOrder(productId, moved, rows) {
    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/reorder/versions`, {
        type: "PUT",
        data: {
          product_id: productId,
          moved_id: moved.id,
          ids: rows.map((row) => row.id),
        },
      });
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }

    try {
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    }
  }

  // ------------------------------------------------------------- versions ---

  @action
  async saveVersion(event, version) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));
    const previousLocale = version.locale;

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, {
        type: "PUT",
        data: {
          label: values.label?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          // An empty date input is "no date", not the epoch.
          released_on: values.released_on || null,
          deprecated: form.elements.deprecated.checked,
          latest: form.elements.latest?.checked ?? false,
        },
      });
      await this.reload();

      // A version moved to another language resolves its pages in that
      // language, so the cached tree is no longer the one the editor wrote.
      if (previousLocale !== values.locale) {
        this.#forgetPages(version.id);
        const updated = this.#versionById(version.id);

        if (updated && this.expandedVersions.has(version.id)) {
          await this.loadPages(updated);
        }
      }
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  #forgetPages(versionId) {
    const pages = { ...this.pagesByVersion };
    delete pages[versionId];
    this.pagesByVersion = pages;
    // Invalidate the request in flight, and clear its spinner: the response
    // will be dropped, so nothing else would ever remove it.
    this.treeTokens.delete(versionId);

    if (this.loadingVersions.has(versionId)) {
      const loading = new Set(this.loadingVersions);
      loading.delete(versionId);
      this.loadingVersions = loading;
    }
  }

  @action
  async destroyVersion(version) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_version_confirm"))) {
      return false;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/versions/${version.id}`, {
        type: "DELETE",
      });

      if (version.id === this.selectedVersionId) {
        this.selectedVersionId = null;
        this.selectedPageSlug = null;
        this.selectedNodeKey = null;
      }

      this.#forgetPages(version.id);
      const expanded = new Set(this.expandedVersions);
      expanded.delete(version.id);
      this.expandedVersions = expanded;
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  async moveVersion(version, direction) {
    const chip = this.#chipOfVersion(version.id);
    const siblings = this.#versionsOf(chip);
    const index = siblings.findIndex((entry) => entry.id === version.id);
    const target = index + direction;

    if (!chip || index < 0 || target < 0 || target >= siblings.length) {
      return;
    }

    const reordered = [...siblings];
    reordered.splice(index, 1);
    reordered.splice(target, 0, version);

    await this.#persistVersionOrder(chip.id, version, reordered);
  }

  // ------------------------------------------------ series and chips CRUD ---

  // Series and chips are the front end's first two filter rows, so the words a
  // visitor picks from — and the slug the address spells, the language a reader
  // must be using to see it, and whether it is on the site at all — are edited
  // here rather than in code.
  @action
  async saveProduct(event, record) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));
    const localeChanged = record.locale !== values.locale;

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "PUT",
        data: {
          name: values.name?.trim(),
          slug: values.slug?.trim(),
          locale: values.locale,
          published: form.elements.published.checked,
        },
      });
      await this.reload();

      // Correcting a row's language moves its whole subtree with it, which
      // changes how every affected version resolves its pages.
      if (localeChanged) {
        this.pagesByVersion = {};
        await this.#reloadExpandedPages();
      }
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  async #reloadExpandedPages() {
    const versions = [...this.expandedVersions]
      .map((id) => this.#versionById(id))
      .filter(Boolean);

    await Promise.all(versions.map((version) => this.loadPages(version)));
  }

  // The arrows in the settings modal move a series or chip one place among its
  // siblings; the left pane offers the same operation as a drag.
  @action
  async moveProduct(record, direction) {
    const siblings =
      record.kind === "series"
        ? this.#orderedSeries()
        : this.#orderedChips(this.#seriesOfChip(record.id));
    const index = siblings.findIndex((entry) => entry.id === record.id);
    const target = index + direction;

    if (index < 0 || target < 0 || target >= siblings.length) {
      return;
    }

    const reordered = [...siblings];
    reordered.splice(index, 1);
    reordered.splice(target, 0, record);

    const parentId = record.kind === "series" ? null : record.parent_id;
    await this.#persistProductOrder(record.kind, parentId, record, reordered);
  }

  @action
  async destroyProduct(record) {
    if (!window.confirm(i18n("admin.ingenic.documentation.delete_confirm"))) {
      return false;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "DELETE",
      });

      // Deleting a series deletes its chips and versions; `reload` prunes the
      // caches and the selection of anything that is gone.
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  // ----------------------------------------------------------------- modal ---

  @action
  openDrawer(kind, action = "edit", record = null, parent = null) {
    this.error = null;
    this.addMenuKey = null;

    if (action === "create") {
      // Pre-fill the parent pickers from the row whose + was pressed, but
      // leave them editable: a new row may belong somewhere else.
      // The new row starts in the language the tree is showing, so it lands
      // in view; the parent's language is only the fallback when no language
      // is known yet.
      this.formLocale =
        this.activeLanguage ??
        (parent ? this.#localeOf(parent) : null) ??
        this.args.defaultLocale ??
        null;

      if (kind === "series") {
        this.formSeriesId = null;
        this.formChipId = null;
      } else if (kind === "chip") {
        this.formSeriesId = parent?.id ?? this.#orderedSeries()[0]?.id ?? null;
        this.formChipId = null;
      } else {
        this.formChipId = parent?.id ?? null;
        this.formSeriesId =
          this.#seriesIdOfChip(this.formChipId) ??
          this.#orderedSeries()[0]?.id ??
          null;
      }
    } else {
      this.formLocale = record?.locale ?? null;
      this.formSeriesId =
        kind === "chip"
          ? (record?.parent_id ?? null)
          : kind === "version"
            ? this.#seriesIdOfChip(record?.product_id)
            : null;
      this.formChipId = kind === "version" ? (record?.product_id ?? null) : null;
    }

    this.drawer = { kind, action, record };
  }

  @action
  closeDrawer() {
    this.drawer = null;
  }

  @action
  selectFormLocale(event) {
    this.formLocale = event.target.value || null;
  }

  @action
  selectFormSeries(event) {
    this.formSeriesId = Number(event.target.value) || null;

    if (!this.formChips.some((chip) => chip.id === this.formChipId)) {
      this.formChipId = this.formChips[0]?.id ?? null;
    }
  }

  @action
  selectFormChip(event) {
    this.formChipId = Number(event.target.value) || null;
  }

  // The site's served languages, plus the row's own value when it is not one
  // of them: a row filed under "en" on a Chinese site has to show "en" in the
  // picker, or saving any other field would silently move it to the first
  // option and take it off the reader's screen.
  localeOptions(current) {
    const options = this.args.locales ?? [];

    if (current && !options.some((option) => option.value === current)) {
      return [{ value: current, name: current }, ...options];
    }

    return options;
  }

  @action
  async submitDrawer(event) {
    event.preventDefault();
    const form = event.target;
    const values = Object.fromEntries(new FormData(form));
    const { kind, action, record } = this.drawer;

    if (kind === "version") {
      if (action === "create") {
        const chipId = Number(values.product_id);

        if (!chipId) {
          this.error = i18n(
            "admin.ingenic.documentation.workbench.no_chips_in_series"
          );
          return;
        }

        const response = await this.#createRecord("documentation/versions", {
          label: values.label?.trim(),
          slug: values.slug?.trim(),
          // The drawer's pickers are editable, so use what they say rather
          // than what the row's + pre-filled.
          locale: values.locale,
          released_on: values.released_on || null,
          deprecated: form.elements.deprecated?.checked ?? false,
          latest: form.elements.latest?.checked ?? false,
          product_id: chipId,
        });

        if (response?.version) {
          const version = response.version;
          const chip = this.#chipById(chipId);
          const series = chip ? this.#seriesOfChip(chip.id) : null;
          this.#expandProductKeys([
            chip && this.#keyOf("chip", chip),
            series && this.#keyOf("series", series),
          ]);
          this.expandedVersions = new Set(this.expandedVersions).add(
            version.id
          );

          // A version created in another language must not land behind the
          // language filter and look like it was not created at all. The tree
          // shows one language, so follow the new row to its language.
          const createdLocale = this.#localeOf(version);

          if (createdLocale && createdLocale !== this.activeLanguage) {
            this.languageFilter = createdLocale;
          }

          this.selectedVersionId = version.id;
          this.selectedPageSlug = null;
          this.selectedNodeKey = this.#keyOf("version", version);
          await this.loadPages(version);
        }
      } else {
        await this.saveVersion(event, record);
      }
    } else if (action === "create") {
      const seriesId = Number(values.series_id);
      const response = await this.#createRecord("documentation/products", {
        name: values.name?.trim(),
        slug: values.slug?.trim(),
        // The parent pickers default to the row's + but can be changed here,
        // so the row is filed where the drawer says.
        locale: values.locale,
        published: form.elements.published?.checked ?? true,
        kind,
        parent_id: kind === "chip" ? seriesId : null,
      });

      if (response?.product) {
        // Same rule as versions: follow the new row to the language it was
        // filed under, or the tree would look like it dropped the creation.
        const productLocale = this.#localeOf(response.product);

        if (productLocale && productLocale !== this.activeLanguage) {
          this.languageFilter = productLocale;
        }

        if (kind === "series") {
          this.selectedNodeKey = this.#keyOf("series", response.product);
        } else {
          const series = this.#seriesOfChip(response.product.id);
          this.#expandProductKeys([series && this.#keyOf("series", series)]);
          this.selectedNodeKey = this.#keyOf("chip", response.product);
        }
      }
    } else {
      await this.saveProduct(event, record);
    }

    if (!this.error) {
      this.drawer = null;
    }
  }

  @action
  async deleteFromDrawer() {
    const { kind, record } = this.drawer;
    const done =
      kind === "version"
        ? await this.destroyVersion(record)
        : await this.destroyProduct(record);

    // A refused delete (a series with chips) leaves the error on screen and
    // the modal open, so the user can see why and act on it. A cancelled
    // confirmation (`false`) leaves the modal open too — the row is still
    // there to look at.
    if (done !== false && !this.error) {
      this.drawer = null;
    }
  }

  async #createRecord(endpoint, data) {
    this.busy = true;
    this.error = null;

    try {
      const response = await ajax(`${BASE}/${endpoint}`, { type: "POST", data });
      await this.reload();
      return response;
    } catch (error) {
      this.error = this.#errorMessage(error);
      return null;
    } finally {
      this.busy = false;
    }
  }

  #errorMessage(error) {
    return (
      error.jqXHR?.responseJSON?.errors?.join(", ") ||
      i18n("admin.ingenic.save_failed")
    );
  }

  <template>
    {{#if this.error}}
      <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
    {{/if}}

    <div class="ingenic-doc-workbench">
      <div class="ingenic-doc-workbench__body">
        <aside class="ingenic-doc-workbench__tree">
          <div class="ingenic-doc-tree-toolbar">
            <label class="ingenic-doc-tree-toolbar__field">
              <span>{{i18n "admin.ingenic.documentation.workbench.language"}}</span>
              <select {{on "change" this.selectLanguage}}>
                {{#each this.languageOptions as |locale|}}
                  <option value={{locale.value}} selected={{eq locale.value this.selectedLanguage}}>
                    {{locale.name}}
                  </option>
                {{/each}}
              </select>
            </label>

          </div>

          <div class="ingenic-doc-tree-scroll">
            {{! The tree is the only place rows are created: a series has no
                parent row, so its + sits at the top of the tree itself. }}
            <button
              type="button"
              class="ingenic-doc-tree-new"
              {{on "click" (fn this.openDrawer "series" "create" null)}}
            >＋ {{i18n "admin.ingenic.documentation.workbench.new_series"}}</button>

            {{#each this.structureRows key="key" as |row|}}
              {{#if (eq row.kind "pages")}}
                <div class="ingenic-doc-subtree">
                  {{#if (this.isLoading row.record)}}
                    <p class="ingenic-admin-tree__empty">
                      {{i18n "admin.ingenic.documentation.workbench.loading_pages"}}
                    </p>
                  {{else}}
                    <IngenicDocPageTree
                      @pages={{this.pagesFor row.record}}
                      @selectedSlug={{this.selectedPageSlug}}
                      @indentBase={{row.depth}}
                      @writable={{row.record.writable}}
                      @onSelect={{fn this.selectPage row.record}}
                      @onDrop={{fn this.dropPage row.record}}
                      @onCreate={{fn this.createPage row.record}}
                      @onRename={{fn this.renamePage row.record}}
                      @onReady={{fn this.registerTree row.record}}
                    />
                  {{/if}}
                </div>
              {{else if (eq row.kind "hint")}}
                <p class="ingenic-admin-tree__empty ingenic-doc-tree-hint ingenic-doc-tree-hint--{{row.depth}}">
                  {{row.text}}
                </p>
              {{else}}
                <div
                  class="ingenic-admin-tree__row ingenic-admin-tree__row--indent-{{row.depth}} {{if row.isSelected 'is-selected'}} {{if (eq row.kind 'version') 'is-version'}} {{if row.isDragging 'is-dragging'}} {{if row.isDropBefore 'is-drop-before'}} {{if row.isDropAfter 'is-drop-after'}} {{if row.isDropInto 'is-drop-into'}}"
                  {{on "dragover" (fn this.dragOver row)}}
                  {{on "dragleave" (fn this.dragLeave row)}}
                  {{on "drop" (fn this.dropOn row)}}
                >
                  {{#if row.writable}}
                    <span
                      class="ingenic-admin-tree__handle"
                      draggable="true"
                      title={{i18n "admin.ingenic.documentation.workbench.drag"}}
                      {{on "dragstart" (fn this.startDrag row)}}
                      {{on "dragend" this.endDrag}}
                    >⠿</span>
                  {{else}}
                    <span class="ingenic-admin-tree__handle ingenic-admin-tree__handle--empty"></span>
                  {{/if}}

                  {{#if row.hasChildren}}
                    <button
                      type="button"
                      class="ingenic-admin-tree__chevron"
                      aria-expanded={{if row.expanded "true" "false"}}
                      {{on "click" (fn this.toggleRow row)}}
                    >{{if row.expanded "▾" "▸"}}</button>
                  {{else}}
                    <span class="ingenic-admin-tree__chevron ingenic-admin-tree__chevron--empty"></span>
                  {{/if}}

                  <button
                    type="button"
                    class="ingenic-admin-tree__select"
                    {{on "click" (fn this.openRow row)}}
                  >
                    <span class="ingenic-admin-tree__title">{{row.label}}</span>
                  </button>

                  {{#if row.writable}}
                    <span class="ingenic-admin-tree__tools">
                      <button
                        type="button"
                        class="ingenic-admin-tree__add"
                        title={{i18n "admin.ingenic.documentation.workbench.settings"}}
                        {{on "click" (fn this.openDrawer row.kind "edit" row.record null)}}
                      >⚙</button>
                      <button
                        type="button"
                        class="ingenic-admin-tree__add"
                        title={{row.addTitle}}
                        {{on "click" (fn this.addChild row)}}
                      >＋</button>
                    </span>
                  {{/if}}

                  {{#if row.addMenuOpen}}
                    <span class="ingenic-admin-tree__add-menu">
                      <button type="button" {{on "click" (fn this.startPageDraft row.record "page")}}>
                        📄 {{i18n "admin.ingenic.documentation.workbench.new_article"}}
                      </button>
                      <button type="button" {{on "click" (fn this.startPageDraft row.record "folder")}}>
                        📁 {{i18n "admin.ingenic.documentation.workbench.new_folder"}}
                      </button>
                    </span>
                  {{/if}}
                </div>
              {{/if}}
            {{else}}
              <p class="ingenic-admin-tree__empty">
                {{#if this.noSeries}}
                  {{i18n "admin.ingenic.documentation.workbench.empty_series"}}
                {{else}}
                  {{i18n "admin.ingenic.documentation.workbench.empty_series_in_locale"}}
                {{/if}}
              </p>
            {{/each}}

            {{#if this.selectedVersion}}
              <details class="ingenic-doc-workbench__import">
                <summary>{{i18n "admin.ingenic.documentation.import_action"}}</summary>
                <form class="ingenic-admin-form" {{on "submit" this.importPages}}>
                  <input type="file" name="files[]" accept=".md,.markdown,.txt,.docx" multiple required />
                  <button type="submit" disabled={{this.busy}}>
                    {{i18n "admin.ingenic.documentation.import_action"}}
                  </button>
                </form>
                <p class="ingenic-admin-note">
                  {{i18n "admin.ingenic.documentation.import_hint"}}
                </p>
                {{#if this.importMessage}}
                  <p class="ingenic-admin-note">{{this.importMessage}}</p>
                {{/if}}
              </details>
            {{/if}}
          </div>
        </aside>

        <section class="ingenic-doc-workbench__editor">
          {{#if this.selectedPage}}
            {{! The right pane edits the page chosen on the left. Adding a child
                is a tree action, so that button lives on the row's + menu. }}
            <div class="ingenic-doc-workbench__editor-head">
              <h3>{{this.selectedPage.title}}</h3>
            </div>

            <IngenicDocPageForm
              @page={{this.selectedPage}}
              @version={{this.selectedVersion}}
              @writable={{this.selectedVersion.writable}}
              @busy={{this.busy}}
              @onSave={{fn this.savePage this.selectedVersion}}
              @onDestroy={{fn this.destroyPage this.selectedVersion}}
            />
          {{else}}
            <div class="ingenic-doc-workbench__empty">
              <p>{{i18n "admin.ingenic.documentation.workbench.empty_editor"}}</p>
              {{#if this.noSeries}}
                <p class="ingenic-admin-note">
                  {{i18n "admin.ingenic.documentation.workbench.empty_series"}}
                </p>
              {{else if this.selectedVersion}}
                <p class="ingenic-admin-note">
                  {{i18n "admin.ingenic.documentation.workbench.pick_version"}}
                </p>
              {{/if}}
            </div>
          {{/if}}
        </section>
      </div>
    </div>

    {{#if this.drawer}}
      <div class="ingenic-doc-drawer__backdrop" role="presentation" {{on "click" this.closeDrawer}}></div>

      <aside class="ingenic-doc-drawer" role="dialog" aria-modal="true">
        <header class="ingenic-doc-drawer__head">
          <h3>{{this.drawerTitle}}</h3>
          <button type="button" class="ingenic-doc-drawer__close" {{on "click" this.closeDrawer}}>×</button>
        </header>

        <form class="ingenic-admin-form ingenic-doc-drawer__form" {{on "submit" this.submitDrawer}}>
          {{#if this.error}}
            <p class="ingenic-admin-note ingenic-admin-note--error">{{this.error}}</p>
          {{/if}}

          {{#if (eq this.drawer.kind "version")}}
            {{#if (eq this.drawer.action "create")}}
              {{! The pickers start on the row whose + was pressed but stay
                  editable: the new version may belong to another series or
                  chip, and the series picker narrows the chip list. }}
              <label>
                <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
                <select name="locale" required {{on "change" this.selectFormLocale}}>
                  {{#each (this.localeOptions this.formLocale) as |locale|}}
                    <option value={{locale.value}} selected={{eq locale.value this.formLocale}}>
                      {{locale.name}}
                    </option>
                  {{/each}}
                </select>
              </label>
              <label>
                <span>{{i18n "admin.ingenic.documentation.workbench.series"}}</span>
                <select name="series_id" required {{on "change" this.selectFormSeries}}>
                  {{#each this.series as |series|}}
                    <option value={{series.id}} selected={{eq series.id this.formSeriesId}}>
                      {{series.name}}
                    </option>
                  {{/each}}
                </select>
              </label>
              <label>
                <span>{{i18n "admin.ingenic.documentation.workbench.chip"}}</span>
                <select name="product_id" required disabled={{this.formHasNoChips}}>
                  {{#each this.formChips as |chip|}}
                    <option value={{chip.id}} selected={{eq chip.id this.formChipId}}>
                      {{chip.name}}
                    </option>
                  {{/each}}
                </select>
              </label>
              {{#if this.formHasNoChips}}
                <p class="ingenic-admin-note">
                  {{i18n "admin.ingenic.documentation.workbench.no_chips_in_series"}}
                </p>
              {{/if}}
            {{/if}}

            <label>
              <span>{{i18n "admin.ingenic.documentation.version_label"}}</span>
              <input name="label" value={{this.drawer.record.label}} required />
            </label>
            <label>
              <span>{{i18n "admin.ingenic.documentation.version_slug"}}</span>
              <input name="slug" value={{this.drawer.record.slug}} required />
            </label>
            {{#if (eq this.drawer.action "edit")}}
              <label>
                <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
                <select name="locale" required>
                  {{#each (this.localeOptions this.drawerLocale) as |locale|}}
                    <option value={{locale.value}} selected={{eq locale.value this.drawerLocale}}>
                      {{locale.name}}
                    </option>
                  {{/each}}
                </select>
              </label>
            {{/if}}
            <label>
              <span>{{i18n "admin.ingenic.documentation.released_on"}}</span>
              <input type="date" name="released_on" value={{this.drawer.record.released_on}} />
            </label>
            <label class="checkbox-label">
              <input type="checkbox" name="latest" checked={{this.drawer.record.latest}} />
              <span>{{i18n "admin.ingenic.documentation.latest"}}</span>
            </label>
            <label class="checkbox-label">
              <input type="checkbox" name="deprecated" checked={{this.drawer.record.deprecated}} />
              <span>{{i18n "admin.ingenic.documentation.deprecated"}}</span>
            </label>
          {{else}}
            {{#if (eq this.drawer.action "create")}}
              {{! Language, then (for a chip) the series it belongs to. Both
                  default to the row whose + was pressed and can be changed. }}
              <label>
                <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
                <select name="locale" required {{on "change" this.selectFormLocale}}>
                  {{#each (this.localeOptions this.formLocale) as |locale|}}
                    <option value={{locale.value}} selected={{eq locale.value this.formLocale}}>
                      {{locale.name}}
                    </option>
                  {{/each}}
                </select>
              </label>
              {{#if (eq this.drawer.kind "chip")}}
                <label>
                  <span>{{i18n "admin.ingenic.documentation.workbench.series"}}</span>
                  <select name="series_id" required {{on "change" this.selectFormSeries}}>
                    {{#each this.series as |series|}}
                      <option value={{series.id}} selected={{eq series.id this.formSeriesId}}>
                        {{series.name}}
                      </option>
                    {{/each}}
                  </select>
                </label>
              {{/if}}
            {{/if}}

            <label>
              <span>
                {{#if (eq this.drawer.kind "series")}}
                  {{i18n "admin.ingenic.documentation.series_name"}}
                {{else}}
                  {{i18n "admin.ingenic.documentation.chip_name"}}
                {{/if}}
              </span>
              <input name="name" value={{this.drawer.record.name}} required />
            </label>
            <label>
              <span>
                {{#if (eq this.drawer.kind "series")}}
                  {{i18n "admin.ingenic.documentation.series_slug"}}
                {{else}}
                  {{i18n "admin.ingenic.documentation.chip_slug"}}
                {{/if}}
              </span>
              <input name="slug" value={{this.drawer.record.slug}} required />
            </label>
            {{#if (eq this.drawer.action "edit")}}
              <label>
                <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
                <select name="locale" required>
                  {{#each (this.localeOptions this.drawerLocale) as |locale|}}
                    <option value={{locale.value}} selected={{eq locale.value this.drawerLocale}}>
                      {{locale.name}}
                    </option>
                  {{/each}}
                </select>
              </label>
            {{/if}}
            <label class="checkbox-label">
              <input type="checkbox" name="published" checked={{this.drawerPublished}} />
              <span>{{i18n "admin.ingenic.documentation.published"}}</span>
            </label>
          {{/if}}

          <div class="ingenic-doc-drawer__actions">
            <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.save"}}</button>
            <button type="button" class="btn" {{on "click" this.closeDrawer}}>
              {{i18n "admin.ingenic.documentation.cancel"}}
            </button>
          </div>
        </form>

        {{#if (eq this.drawer.action "edit")}}
          <div class="ingenic-doc-drawer__danger">
            {{#if (eq this.drawer.kind "version")}}
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveVersion this.drawer.record -1)}}
              >↑ {{i18n "admin.ingenic.documentation.move_up"}}</button>
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveVersion this.drawer.record 1)}}
              >↓ {{i18n "admin.ingenic.documentation.move_down"}}</button>
            {{else}}
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveProduct this.drawer.record -1)}}
              >↑ {{i18n "admin.ingenic.documentation.move_up"}}</button>
              <button
                type="button"
                class="btn btn-small"
                disabled={{this.busy}}
                {{on "click" (fn this.moveProduct this.drawer.record 1)}}
              >↓ {{i18n "admin.ingenic.documentation.move_down"}}</button>
            {{/if}}
            <button
              type="button"
              class="btn btn-danger"
              disabled={{this.busy}}
              {{on "click" this.deleteFromDrawer}}
            >{{i18n "admin.ingenic.documentation.delete"}}</button>
          </div>
        {{/if}}
      </aside>
    {{/if}}
  </template>
}
