import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
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
 * The hierarchy is fixed: series → chip → version → pages and folders. Every
 * level lives in the left pane and is edited there like a file explorer — each
 * row has a grip, an icon, a name, and ＋ / − controls. ＋ inserts a draft row
 * under the row that owns it (a series' ＋ above the tree creates a series),
 * Enter creates, Esc cancels; double-clicking a name renames it in place.
 * There is no settings dialog: the slug, language and publish flags a row is
 * born with are the ones it keeps.
 *
 * The language picker above the tree is the only thing in the toolbar. Each
 * language has its own independent tree: the picker filters the whole
 * hierarchy, and every row created while it is set inherits that language.
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

  // The row currently being named in place: { kind, parent }. A series has no
  // parent row, a chip's parent is its series, a version's is its chip.
  @tracked draft = null;
  @tracked draftName = "";
  // Bumped whenever a draft starts. It is part of the draft row's key so the
  // input is a fresh element every time: reusing the old one skips didInsert,
  // and the new draft would open without focus.
  @tracked draftSeq = 0;

  // The row whose name is being edited in place: { key, kind, record }.
  @tracked renaming = null;
  @tracked renameDraft = "";

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
    const options = unique.map((value) => ({
      value,
      name: this.#localeName(value),
    }));

    // The empty value is "all languages": every version in one tree. Without
    // it the screen could only ever show one language, and a chip whose rows
    // were written in another one simply disappeared.
    return [
      {
        value: "",
        name: i18n("admin.ingenic.documentation.workbench.all_languages"),
      },
      ...options,
    ];
  }

  // The language whose versions are on screen, or null for all of them. Only
  // versions are filtered: series and chips are the skeleton of the manual
  // and stay visible in every language, so changing the filter can never make
  // a row look like it moved or vanished.
  get activeLanguage() {
    return this.languageFilter;
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

      for (const chip of this.#visibleChips(series)) {
        const chipKey = this.#keyOf("chip", chip);
        const versions = this.#visibleVersions(chip);
        const chipOpen = !this.collapsedProducts.has(chipKey);
        rows.push(this.#rowFor("chip", chip, 1, chipOpen));

        if (!chipOpen) {
          continue;
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

        // The server appends a new version to its chip, so the draft belongs
        // at the end of the list. Showing it first made the row jump to the
        // bottom the moment it was created.
        if (
          this.draft?.kind === "version" &&
          this.draft.parent?.id === chip.id
        ) {
          rows.push(this.#draftRow(2));
        }
      }

      // Same for chips: created last means drawn last.
      if (this.draft?.kind === "chip" && this.draft.parent?.id === series.id) {
        rows.push(this.#draftRow(1));
      }
    }

    // A series has no parent row; its draft closes the list, matching where
    // the server files the new row.
    if (this.draft?.kind === "series") {
      rows.push(this.#draftRow(0));
    }

    return rows;
  }

  #draftRow(depth) {
    return {
      key: `__draft__-${this.draftSeq}`,
      kind: "draft",
      depth,
      isDraft: true,
    };
  }

  #rowFor(kind, record, depth, expanded) {
    const key = this.#keyOf(kind, record);

    return {
      key,
      kind,
      record,
      depth,
      expanded,
      writable: record.writable ?? true,
      // The first three levels are containers, so they use the same folder
      // glyph as a page folder; an article is the only document row.
      icon: "📁",
      label: kind === "version" ? record.label : record.name,
      isRenaming: this.renaming?.key === key,
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

  // The language filter applies to versions only. Series and chips are the
  // skeleton of the manual: hiding a chip because its own row was written in
  // another language stranded the versions under it, and a series whose rows
  // were all in another language disappeared entirely. Both stay on screen; a
  // chip with nothing in the selected language simply shows no versions.
  #visibleChips(series) {
    return this.#orderedChips(series);
  }

  #visibleSeries() {
    return this.#orderedSeries();
  }

  #seriesOfChip(chipId) {
    return (
      this.series.find((series) =>
        (series.chips ?? []).some((chip) => chip.id === chipId)
      ) ?? null
    );
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

    // A draft lives under a row of the language that is on screen. Switching
    // languages can hide that row, which would leave an input with no owner.
    this.cancelDraft();
    this.cancelRename();
    this.addMenuKey = null;

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

    // Folding removes the row a draft was being typed into. A removed input
    // does not blur, so the draft would stay alive but invisible — and folding
    // a series also hides drafts filed under its chips, not only its own.
    // Keep a name that was already typed, the way clicking away does.
    if (!this.#draftIsVisible()) {
      if (this.draftName.trim()) {
        this.commitDraft();
      } else {
        this.cancelDraft();
      }
    }
  }

  // Whether the draft row would still be rendered after a fold. A version
  // draft needs its chip open, and a chip draft needs its series open.
  #draftIsVisible() {
    const draft = this.draft;

    if (!draft || draft.kind === "series" || !draft.parent) {
      return true;
    }

    if (this.collapsedProducts.has(this.#keyOf(draft.parent.kind, draft.parent))) {
      return false;
    }

    if (draft.kind === "version") {
      const series = this.#seriesOfChip(draft.parent.id);

      if (series && this.collapsedProducts.has(this.#keyOf("series", series))) {
        return false;
      }
    }

    return true;
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

  // Clicking a name only selects the row: the chevron is the control that
  // folds a container, the way a file explorer works, and double-clicking
  // renames it. Folding on the name click as well made every click rearrange
  // the tree under the pointer — the rows looked like they were moving on
  // their own, which is the complaint this screen kept getting.
  @action
  selectRow(row) {
    this.selectedNodeKey = row.key;
    this.addMenuKey = null;

    if (row.kind !== "version") {
      return;
    }

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
  }

  // The + adds the next level down: a series gets a chip, a chip gets a
  // version, a version gets a page or folder. Only the last one has a choice
  // to make, so only it opens a menu; everything else starts typing at once.
  //
  // The menu always opens, never toggles: a second click on + used to close
  // what the first opened, and with the menu drawn as a second line inside
  // the row that read as "the + only works every other time". Choosing an
  // article/folder, clicking any row, or starting another draft closes it.
  @action
  addChild(row) {
    this.selectedNodeKey = row.key;

    if (row.kind === "series") {
      this.#startDraft("chip", row.record);
    } else if (row.kind === "chip") {
      this.#startDraft("version", row.record);
    } else {
      this.addMenuKey = row.key;
    }
  }

  // A series has no parent row, so its + is the button above the tree; the
  // draft still appears as a row at the top, not in a dialog.
  @action
  startSeriesDraft() {
    this.#startDraft("series", null);
  }

  #startDraft(kind, parent) {
    const sameRow =
      this.draft &&
      this.draft.kind === kind &&
      (this.draft.parent?.id ?? null) === (parent?.id ?? null);

    // The + for the row already being typed into must not throw the name
    // away: remount the input so it is focused and visible again.
    if (sameRow) {
      this.draftSeq += 1;
      return;
    }

    // Starting a draft somewhere else keeps what was already typed by
    // creating it first; only an empty draft is dropped.
    if (this.draft) {
      if (this.draftName.trim()) {
        this.commitDraft();
      } else {
        this.cancelDraft();
      }
    }

    this.error = null;
    this.addMenuKey = null;
    this.renaming = null;

    // The draft has to be visible: a folded parent would hide the row being
    // typed into.
    if (parent) {
      const parentKey = this.#keyOf(kind === "version" ? "chip" : "series", parent);
      this.#expandProductKeys([parentKey]);

      if (kind === "version") {
        const series = this.#seriesOfChip(parent.id);
        this.#expandProductKeys([series && this.#keyOf("series", series)]);
      }
    }

    this.draftSeq += 1;
    this.draft = { kind, parent };
    this.draftName = "";
  }

  @action
  focusDraft(element) {
    // A draft is filed at the end of its list, which can be below the fold
    // when earlier rows are expanded. Bring it to the eye by scrolling the
    // tree pane only: `scrollIntoView` also moves the page, so the admin's
    // whole screen jumped and every row appeared to have moved.
    this.#revealInTree(element);
    element.focus({ preventScroll: true });
    element.select?.();
  }

  // The article/folder menu is a second line inside the row. A row near the
  // bottom of the pane opens it below the fold, which reads as "the + did
  // nothing".
  @action
  revealMenu(element) {
    this.#revealInTree(element);
  }

  #revealInTree(element) {
    const pane = element.closest(".ingenic-doc-tree-scroll");

    if (!pane) {
      return;
    }

    const box = element.getBoundingClientRect();
    const frame = pane.getBoundingClientRect();

    if (box.bottom > frame.bottom) {
      pane.scrollTop += box.bottom - frame.bottom + 8;
    } else if (box.top < frame.top) {
      pane.scrollTop -= frame.top - box.top + 8;
    }
  }

  @action
  updateDraftName(event) {
    this.draftName = event.target.value;
  }

  @action
  draftKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.commitDraft();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelDraft();
    }
  }

  // Clicking away commits a named row and discards an empty one, the way a
  // file explorer does. Moving within the workbench is not clicking away:
  // pressing the + or a chevron while half a name is typed used to create a
  // row from the fragment, and pressing the + again silently discarded the
  // draft — which is why the same button seemed to work only sometimes.
  @action
  draftBlur(event) {
    if (!this.draft) {
      return;
    }

    if (event.relatedTarget?.closest?.(".ingenic-doc-workbench")) {
      return;
    }

    if (this.draftName.trim()) {
      this.commitDraft();
    } else {
      this.cancelDraft();
    }
  }

  @action
  async commitDraft() {
    const draft = this.draft;
    const name = this.draftName.trim();
    const seq = this.draftSeq;

    if (!draft || !name) {
      return;
    }

    this.draft = null;
    this.draftName = "";
    this.busy = true;
    this.error = null;

    const locale = this.activeLanguage || this.args.defaultLocale || undefined;

    try {
      if (draft.kind === "series" || draft.kind === "chip") {
        const response = await ajax(`${BASE}/documentation/products`, {
          type: "POST",
          data: {
            kind: draft.kind,
            name,
            slug: this.#slugFor(name, draft.kind),
            locale,
            published: true,
            parent_id: draft.kind === "chip" ? draft.parent.id : null,
          },
        });

        await this.reload();

        if (response?.product) {
          this.selectedNodeKey = this.#keyOf(draft.kind, response.product);

          if (draft.kind === "chip") {
            this.#expandProductKeys([
              this.#keyOf("series", draft.parent),
            ]);
          }
        }
      } else {
        const response = await ajax(`${BASE}/documentation/versions`, {
          type: "POST",
          data: {
            label: name,
            slug: this.#slugFor(name, "version"),
            locale,
            released_on: null,
            deprecated: false,
            // The version just added is the one readers should land on. The
            // server keeps "latest" exclusive within this chip and language.
            latest: true,
            product_id: draft.parent.id,
          },
        });

        await this.reload();

        const series = this.#seriesOfChip(draft.parent.id);
        this.#expandProductKeys([
          this.#keyOf("chip", draft.parent),
          series && this.#keyOf("series", series),
        ]);

        if (response?.version) {
          this.selectedVersionId = response.version.id;
          this.selectedPageSlug = null;
          this.selectedNodeKey = this.#keyOf("version", response.version);
          this.expandedVersions = new Set(this.expandedVersions).add(
            response.version.id
          );
          await this.loadPages(response.version);
        }
      }
    } catch (error) {
      this.error = this.#errorMessage(error);

      // Another + replaced this draft while the request was in flight. Putting
      // the failed one back would overwrite the row the editor is typing into
      // now; the error note is enough.
      if (this.draftSeq !== seq) {
        return;
      }

      // The row was never created, so put the name back instead of making
      // the editor type it again. The bumped sequence remounts the input.
      this.draftSeq += 1;
      this.draft = draft;
      this.draftName = name;
    } finally {
      this.busy = false;
    }
  }

  @action
  cancelDraft() {
    this.draft = null;
    this.draftName = "";
  }

  // Double-clicking a series, chip or version name edits it in place. Only the
  // display name changes: the slug an address uses stays as it was.
  @action
  startRowRename(row, event) {
    event.preventDefault();
    event.stopPropagation();

    if (!row.writable) {
      return;
    }

    this.error = null;
    this.addMenuKey = null;
    this.draft = null;
    this.renaming = { key: row.key, kind: row.kind, record: row.record };
    this.renameDraft =
      row.kind === "version" ? row.record.label : row.record.name;
  }

  @action
  focusRename(element) {
    element.focus();
    element.select?.();
  }

  @action
  updateRename(event) {
    this.renameDraft = event.target.value;
  }

  @action
  renameKeydown(row, event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.commitRowRename();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelRename();
    }
  }

  @action
  renameBlur(row) {
    if (this.renaming?.key === row.key) {
      this.commitRowRename();
    }
  }

  @action
  async commitRowRename() {
    const renaming = this.renaming;
    const name = this.renameDraft.trim();
    this.renaming = null;
    this.renameDraft = "";

    if (!renaming || !name) {
      return;
    }

    const record = renaming.record;
    const current =
      renaming.kind === "version" ? record.label : record.name;

    if (name === current) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      const endpoint =
        renaming.kind === "version"
          ? `${BASE}/documentation/versions/${record.id}`
          : `${BASE}/documentation/products/${record.id}`;
      await ajax(endpoint, {
        type: "PUT",
        data: renaming.kind === "version" ? { label: name } : { name },
      });
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
      this.renaming = renaming;
      this.renameDraft = name;
    } finally {
      this.busy = false;
    }
  }

  @action
  cancelRename() {
    this.renaming = null;
    this.renameDraft = "";
  }

  // A version row's + asks the page tree to insert its draft row. Opening the
  // tree first means waiting for the pages to exist in the DOM — and the page
  // tree only registers itself once it has rendered, which can be one or two
  // frames after the data arrives. A single frame was a race: the click
  // silently did nothing when the tree was not mounted yet.
  @action
  async startPageDraft(version, kind) {
    this.addMenuKey = null;

    if (!this.expandedVersions.has(version.id)) {
      this.expandedVersions = new Set(this.expandedVersions).add(version.id);
    }

    if (!this.pagesByVersion[version.id]) {
      await this.loadPages(version);
    }

    this.#startPageDraftWhenReady(version.id, kind);
  }

  #startPageDraftWhenReady(versionId, kind, attempts = 40) {
    const api = this.treeApis.get(versionId);

    if (api) {
      api.startDraft(null, kind);
      return;
    }

    if (attempts <= 0) {
      return;
    }

    requestAnimationFrame(() =>
      this.#startPageDraftWhenReady(versionId, kind, attempts - 1)
    );
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
      // The page tree restores its draft row with the typed name.
      throw error;
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
      // Put the name back in the row's input.
      throw error;
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
  #slugFor(title, prefix = "page") {
    const ascii = title
      .normalize("NFKD")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");

    return ascii || `${prefix}-${Math.random().toString(36).slice(2, 8)}`;
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

    // An inherited row is a perfectly good landmark to drop beside: the
    // server materialises the inherited rows of that level into this version
    // first (the same copy editing makes), so the reader's order can be
    // expressed without touching the version that wrote them.
    if ((dragged.parent_slug ?? null) !== (target.parent_slug ?? null)) {
      return;
    }

    // Slugs identify a resolved row. An inherited row's id belongs to the
    // version that wrote it, so ids cannot be used to build this list.
    const siblings = pages.filter(
      (entry) => (entry.parent_slug ?? null) === (dragged.parent_slug ?? null)
    );
    const reordered = siblings.filter((entry) => entry.slug !== dragged.slug);
    const index = reordered.findIndex((entry) => entry.slug === target.slug);

    if (index < 0) {
      return;
    }

    reordered.splice(after ? index + 1 : index, 0, dragged);

    this.busy = true;
    this.error = null;

    try {
      // One request: the server renumbers the whole level in a transaction
      // and copies inherited rows into this version as needed. A PUT per row
      // used to leave inherited rows out of the numbering, so their positions
      // collided with the rows that were rewritten and the order scrambled
      // after the reload.
      await ajax(
        `${BASE}/documentation/versions/${version.id}/reorder/pages`,
        {
          type: "PUT",
          data: {
            parent_slug: dragged.parent_slug ?? null,
            moved_slug: dragged.slug,
            slugs: reordered.map((entry) => entry.slug),
          },
        }
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

    if (
      !window.confirm(
        i18n("admin.ingenic.documentation.workbench.delete_item_confirm", {
          name: page.title,
        })
      )
    ) {
      return;
    }

    const pages = this.pagesFor(version);
    const descendants =
      page.kind === "folder"
        ? this.#descendantSlugs(pages, page.slug)
        : new Set();

    // Only rows this version owns are destroyed with the folder; a child it
    // merely inherits stays in the version that wrote it.
    const ownDescendantSlugs = new Set(
      [...descendants].filter((slug) => {
        const entry = pages.find((candidate) => candidate.slug === slug);
        return entry && !entry.inherited;
      })
    );

    if (
      ownDescendantSlugs.size &&
      !window.confirm(
        i18n(
          "admin.ingenic.documentation.workbench.delete_folder_contents",
          { count: ownDescendantSlugs.size }
        )
      )
    ) {
      return;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/pages/${page.id}`, { type: "DELETE" });

      if (
        this.selectedPageSlug === page.slug ||
        ownDescendantSlugs.has(this.selectedPageSlug)
      ) {
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
      (drag.kind === row.kind && drag.record.id === row.record?.id) ||
      !["series", "chip", "version"].includes(row.kind)
    ) {
      this.#clearDrop(row);
      return;
    }

    const into = this.#dropIntoAllowed(drag, row);
    const sibling = this.#siblingDropAllowed(drag, row);

    if (!into && !sibling) {
      this.#clearDrop(row);
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

  // The highlight must never outlive the row it was on: a release over a row
  // that is not a target would otherwise apply the previous row's before/after
  // mode, filing the dragged row somewhere the editor never pointed at.
  #clearDrop(row) {
    if (this.drop?.key === row.key) {
      this.drop = null;
    }
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
    const drop = this.drop;

    this.endDrag();

    // The release has to be on the row the highlight is on. Using a stale
    // highlight here is what moved a row to a neighbour nobody pointed at.
    if (!drag || !drop || drop.key !== row.key) {
      return;
    }

    const mode = drop.mode;

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
    if (
      !window.confirm(
        i18n("admin.ingenic.documentation.workbench.delete_item_confirm", {
          name: version.label,
        })
      )
    ) {
      return false;
    }

    // The warning has to name what disappears, so fetch the tree if this
    // version was never expanded.
    if (!this.pagesByVersion[version.id]) {
      await this.loadPages(version);

      if (!this.pagesByVersion[version.id]) {
        return false;
      }
    }

    const ownPages = (this.pagesByVersion[version.id] ?? []).filter(
      (page) => !page.inherited
    );

    if (
      ownPages.length &&
      !window.confirm(
        i18n(
          "admin.ingenic.documentation.workbench.delete_version_contents",
          { count: ownPages.length }
        )
      )
    ) {
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

  // ------------------------------------------------ series and chips CRUD ---

  // Renaming a series or chip is handled by the inline row editor above; its
  // slug is left alone, because that is the address readers have bookmarked.
  @action
  async destroyProduct(record) {
    const name = record.name;
    const versions = (record.versions ?? []).length;

    if (
      !window.confirm(
        i18n("admin.ingenic.documentation.workbench.delete_item_confirm", {
          name,
        })
      )
    ) {
      return false;
    }

    if (record.kind === "series") {
      const chips = (record.chips ?? []).length;
      const descendantVersions = (record.chips ?? []).reduce(
        (count, chip) => count + (chip.versions ?? []).length,
        0
      );

      if (
        chips &&
        !window.confirm(
          i18n(
            "admin.ingenic.documentation.workbench.delete_series_contents",
            { name, chips, versions: descendantVersions }
          )
        )
      ) {
        return false;
      }
    } else if (
      versions &&
      !window.confirm(
        i18n(
          "admin.ingenic.documentation.workbench.delete_chip_contents",
          { name, versions }
        )
      )
    ) {
      return false;
    }

    this.busy = true;
    this.error = null;

    try {
      await ajax(`${BASE}/documentation/products/${record.id}`, {
        type: "DELETE",
      });

      if (this.selectedNodeKey === this.#keyOf(record.kind, record)) {
        this.selectedNodeKey = null;
      }

      // Deleting a series deletes its chips and versions; `reload` prunes the
      // caches and the selection of anything that is gone.
      await this.reload();
    } catch (error) {
      this.error = this.#errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  @action
  deleteRow(row) {
    if (row.kind === "version") {
      return this.destroyVersion(row.record);
    }

    return this.destroyProduct(row.record);
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
            {{! A series has no row above it; this is its +. Everything else is
                created by the + at the end of the row that will own it. }}
            <button
              type="button"
              class="ingenic-doc-tree-new"
              {{on "click" this.startSeriesDraft}}
            >＋ {{i18n "admin.ingenic.documentation.workbench.new_series"}}</button>

            {{#each this.structureRows key="key" as |row|}}
              {{#if (eq row.kind "pages")}}
                <div class="ingenic-doc-subtree">
                  <IngenicDocPageTree
                    @pages={{this.pagesFor row.record}}
                    @selectedSlug={{this.selectedPageSlug}}
                    @indentBase={{row.depth}}
                    @writable={{row.record.writable}}
                    @onSelect={{fn this.selectPage row.record}}
                    @onDrop={{fn this.dropPage row.record}}
                    @onCreate={{fn this.createPage row.record}}
                    @onRename={{fn this.renamePage row.record}}
                    @onDelete={{fn this.destroyPage row.record}}
                    @onReady={{fn this.registerTree row.record}}
                  />
                </div>
              {{else if row.isDraft}}
                <div class="ingenic-admin-tree__row ingenic-admin-tree__row--indent-{{row.depth}} is-draft">
                  <span class="ingenic-admin-tree__handle ingenic-admin-tree__handle--empty"></span>
                  <span class="ingenic-admin-tree__chevron ingenic-admin-tree__chevron--empty"></span>
                  <span class="ingenic-admin-tree__kind" aria-hidden="true">📁</span>
                  <input
                    class="ingenic-admin-tree__name-input"
                    type="text"
                    value={{this.draftName}}
                    placeholder={{i18n "admin.ingenic.documentation.workbench.name_placeholder"}}
                    {{on "input" this.updateDraftName}}
                    {{on "keydown" this.draftKeydown}}
                    {{on "blur" this.draftBlur}}
                    {{didInsert this.focusDraft}}
                  />
                </div>
              {{else}}
                <div
                  class="ingenic-admin-tree__row ingenic-admin-tree__row--indent-{{row.depth}} is-{{row.kind}} {{if row.isSelected 'is-selected'}} {{if row.isDragging 'is-dragging'}} {{if row.isDropBefore 'is-drop-before'}} {{if row.isDropAfter 'is-drop-after'}} {{if row.isDropInto 'is-drop-into'}}"
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

                  {{#if row.isRenaming}}
                    <span class="ingenic-admin-tree__kind" aria-hidden="true">{{row.icon}}</span>
                    <input
                      class="ingenic-admin-tree__name-input"
                      type="text"
                      value={{this.renameDraft}}
                      {{on "input" this.updateRename}}
                      {{on "keydown" (fn this.renameKeydown row)}}
                      {{on "blur" (fn this.renameBlur row)}}
                      {{didInsert this.focusRename}}
                    />
                  {{else}}
                    <button
                      type="button"
                      class="ingenic-admin-tree__select"
                      title={{i18n "admin.ingenic.documentation.workbench.rename_hint"}}
                      {{on "click" (fn this.selectRow row)}}
                      {{on "dblclick" (fn this.startRowRename row)}}
                    >
                      <span class="ingenic-admin-tree__title">
                        <span class="ingenic-admin-tree__kind" aria-hidden="true">{{row.icon}}</span>
                        {{row.label}}
                      </span>
                    </button>
                  {{/if}}

                  {{#if row.writable}}
                    <span class="ingenic-admin-tree__tools">
                      <button
                        type="button"
                        class="ingenic-admin-tree__add"
                        title={{row.addTitle}}
                        {{on "click" (fn this.addChild row)}}
                      >＋</button>
                      <button
                        type="button"
                        class="ingenic-admin-tree__delete"
                        title={{i18n "admin.ingenic.documentation.delete"}}
                        {{on "click" (fn this.deleteRow row)}}
                      >−</button>
                    </span>
                  {{/if}}

                  {{#if row.addMenuOpen}}
                    <span class="ingenic-admin-tree__add-menu" {{didInsert this.revealMenu}}>
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
            {{/each}}
          </div>
        </aside>

        <section class="ingenic-doc-workbench__editor">
          {{#if this.selectedPage}}
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
          {{/if}}
        </section>
      </div>
    </div>
  </template>
}
