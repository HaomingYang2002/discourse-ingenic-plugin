import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const BASE = "/admin/plugins/discourse-ingenic";

/**
 * Editor for a single page.
 *
 * Everything that locates a page is decided above the pane: the top bar picks
 * the chip and the language, the version list narrows it to one manual, and the
 * tree on the left owns the structure — the + menu says whether a row is an
 * article or a folder, indentation and drag decide where it sits, and
 * double-clicking the name renames it. A page's address is derived when it is
 * created; the editor does not ask for it again.
 *
 * What is left is the article itself. Apart from its name, the pane is the
 * writing surface: one large textarea, with save, published state and delete
 * kept in a single compact toolbar so they never push the text into a corner.
 *
 * A page that this version only inherits is edited like any other. Saving it
 * first materialises the row into this version (see the manager), so the user
 * never has to know whether a row is inherited before typing into it.
 *
 * The body has an edit and a preview tab. The preview is cooked by the server
 * with the same pipeline the reader's page uses, because approximating Markdown
 * in the browser is how an editor and the article it produces drift apart.
 */
export default class IngenicDocPageForm extends Component {
  @tracked bodyDraft = null;
  @tracked publishedDraft = null;
  @tracked tabDraft = null;
  @tracked preview = null;
  @tracked previewBusy = false;

  // The tree decides whether a row is an article or a folder (the + menu asks
  // once, at creation). The editor only needs to know which form to show.
  get folder() {
    return this.args.page.kind === "folder";
  }

  get body() {
    if (this.bodyDraft?.id === this.args.page.id) {
      return this.bodyDraft.body;
    }

    return this.args.page.body ?? "";
  }

  // Read through the page's id, not a bare flag: selecting another row has to
  // forget a draft left on this one, or the next save writes it to the wrong
  // article.
  get published() {
    if (this.publishedDraft?.id === this.args.page.id) {
      return this.publishedDraft.published;
    }

    return this.args.page.published;
  }

  get tab() {
    if (this.tabDraft?.id === this.args.page.id) {
      return this.tabDraft.tab;
    }

    return "edit";
  }

  get previewing() {
    return this.tab === "preview";
  }

  get previewHtml() {
    if (this.preview?.id !== this.args.page.id) {
      return "";
    }

    return this.preview.html;
  }

  @action
  updateBody(event) {
    this.bodyDraft = { id: this.args.page.id, body: event.target.value };
  }

  @action
  updatePublished(event) {
    this.publishedDraft = {
      id: this.args.page.id,
      published: event.target.checked,
    };
  }

  @action
  showEdit(event) {
    event?.preventDefault();
    this.tabDraft = { id: this.args.page.id, tab: "edit" };
  }

  @action
  async showPreview(event) {
    event?.preventDefault();
    this.tabDraft = { id: this.args.page.id, tab: "preview" };
    this.previewBusy = true;

    try {
      const response = await ajax(`${BASE}/documentation/preview`, {
        type: "POST",
        data: {
          version_id: this.args.page.version_id,
          body: this.body,
        },
      });

      this.preview = { id: this.args.page.id, html: response.html ?? "" };
    } catch {
      this.preview = {
        id: this.args.page.id,
        html: `<p class="ingenic-doc-editor__preview-error">${i18n(
          "admin.ingenic.documentation.workbench.preview_failed"
        )}</p>`,
      };
    } finally {
      this.previewBusy = false;
    }
  }

  // The editor sends only what it owns. Title, kind, parent, slug and locale
  // are not in this pane: the tree named the row, the + menu picked the kind,
  // the structure is the row's place in the tree, and the address and language
  // come from the top bar and the version being edited.
  @action
  save(event) {
    event?.preventDefault();

    this.args.onSave(this.args.page, {
      body: this.folder ? null : this.body,
      published: this.published,
    });

    // The preview was rendered from text that no longer matches the saved
    // article; drop it rather than show a stale page.
    this.preview = null;
    this.showEdit();
  }

  <template>
    <div class="ingenic-doc-editor">
      <div class="ingenic-doc-editor__toolbar">
        {{#unless this.folder}}
          <div class="ingenic-doc-editor__tabs" role="tablist">
            <button
              type="button"
              class="ingenic-doc-editor__tab {{if (eq this.tab 'edit') 'is-active'}}"
              {{on "click" this.showEdit}}
            >{{i18n "admin.ingenic.documentation.workbench.edit_tab"}}</button>
            <button
              type="button"
              class="ingenic-doc-editor__tab {{if (eq this.tab 'preview') 'is-active'}}"
              disabled={{this.previewBusy}}
              {{on "click" this.showPreview}}
            >{{i18n "admin.ingenic.documentation.workbench.preview_tab"}}</button>
          </div>
        {{/unless}}

        <span class="ingenic-doc-editor__toolbar-spacer"></span>

        <label class="checkbox-label ingenic-doc-editor__published">
          <input
            type="checkbox"
            checked={{this.published}}
            disabled={{@busy}}
            {{on "change" this.updatePublished}}
          />
          <span>{{i18n "admin.ingenic.documentation.published"}}</span>
        </label>

        <button type="button" class="btn btn-primary btn-small" disabled={{@busy}} {{on "click" this.save}}>
          {{i18n "admin.ingenic.save"}}
        </button>

        {{#unless @page.inherited}}
          <button
            type="button"
            class="btn btn-danger btn-small"
            disabled={{@busy}}
            {{on "click" (fn @onDestroy @page)}}
          >{{i18n "admin.ingenic.documentation.delete_page"}}</button>
        {{/unless}}
      </div>

      {{#if this.previewing}}
        <div class="ingenic-doc-editor__preview">
          {{#if this.previewBusy}}
            <p class="ingenic-admin-note">
              {{i18n "admin.ingenic.documentation.workbench.preview_loading"}}
            </p>
          {{else}}
            {{{this.previewHtml}}}
          {{/if}}
        </div>
      {{else if this.folder}}
        <p class="ingenic-admin-form__notice">
          {{i18n "admin.ingenic.documentation.folder_hint"}}
        </p>
      {{else}}
        <textarea
          class="ingenic-doc-editor__body"
          value={{this.body}}
          placeholder={{i18n "admin.ingenic.documentation.workbench.body_placeholder"}}
          {{on "input" this.updateBody}}
        ></textarea>
      {{/if}}
    </div>
  </template>
}
