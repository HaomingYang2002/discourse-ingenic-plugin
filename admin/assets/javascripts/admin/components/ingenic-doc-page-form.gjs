import Component from "@glimmer/component";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Editor for a single page.
 *
 * An inherited page is read-only until it is materialised into the current
 * version, so the form shows where it came from and offers the override
 * instead of a save button. The reverse action puts it back to inheriting.
 *
 * The parent is chosen by id from the pages the version resolves to. It used to
 * be typed as a slug, and a slug that matched nothing silently produced a page
 * at the top level — the reason a folder could appear not to accept children.
 * The options exclude the page itself and everything below it, because a loop
 * in the parent chain makes every tree walk recurse forever.
 */
export default class IngenicDocPageForm extends Component {
  @tracked kindDraft = null;

  get inherited() {
    return this.args.page.inherited;
  }

  // Drafts are keyed by page so selecting another row does not carry the
  // previous row's unsaved choice with it.
  get kind() {
    if (this.kindDraft?.id === this.args.page.id) {
      return this.kindDraft.kind;
    }

    return this.args.page.kind ?? "page";
  }

  get folder() {
    return this.kind === "folder";
  }

  // The site's served languages, plus the page's own value when it is not one
  // of them: a page written before the locale default was fixed is filed under
  // "en", and a picker without that option would move it on the next save.
  get localeOptions() {
    const current = this.args.page.locale;
    const options = this.args.locales ?? [];

    if (current && !options.some((option) => option.value === current)) {
      return [{ value: current, name: current }, ...options];
    }

    return options;
  }

  get parentOptions() {
    const banned = new Set([this.args.page.slug]);
    let changed = true;

    while (changed) {
      changed = false;

      for (const entry of this.args.pages) {
        if (
          entry.parent_slug &&
          banned.has(entry.parent_slug) &&
          !banned.has(entry.slug)
        ) {
          banned.add(entry.slug);
          changed = true;
        }
      }
    }

    return this.args.pages.filter((entry) => !banned.has(entry.slug));
  }

  @action
  pickKind(event) {
    this.kindDraft = { id: this.args.page.id, kind: event.target.value };
  }

  @action
  save(event) {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.target));

    this.args.onSave(this.args.page, {
      title: values.title,
      slug: values.slug,
      kind: this.kind,
      body: this.folder ? null : values.body,
      locale: values.locale,
      parent_id: values.parent_id || null,
      published: values.published === "on",
    });
  }

  <template>
    {{#if this.inherited}}
      <p class="ingenic-admin-form__notice">
        {{i18n "admin.ingenic.documentation.inherited_notice"}}
        <strong>{{@page.inherited_from_label}}</strong>
      </p>
      <button
        type="button"
        class="btn btn-primary"
        disabled={{@busy}}
        {{on "click" (fn @onOverride @page)}}
      >
        {{i18n "admin.ingenic.documentation.override"}}
      </button>
    {{else}}
      <form class="ingenic-admin-form" {{on "submit" this.save}}>
        <label>
          <span>{{i18n "admin.ingenic.documentation.page_title"}}</span>
          <input name="title" value={{@page.title}} required />
        </label>
        <label>
          <span>{{i18n "admin.ingenic.documentation.page_kind"}}</span>
          <select name="kind" {{on "change" this.pickKind}}>
            <option value="page" selected={{eq this.kind "page"}}>
              {{i18n "admin.ingenic.documentation.kind_page"}}
            </option>
            <option value="folder" selected={{eq this.kind "folder"}}>
              {{i18n "admin.ingenic.documentation.kind_folder"}}
            </option>
          </select>
        </label>
        <label>
          <span>{{i18n "admin.ingenic.documentation.page_slug"}}</span>
          <input name="slug" value={{@page.slug}} required />
        </label>
        <label>
          <span>{{i18n "admin.ingenic.documentation.parent_page"}}</span>
          <select name="parent_id">
            <option value="" selected={{eq @page.parent_slug null}}>
              {{i18n "admin.ingenic.documentation.parent_none"}}
            </option>
            {{#each this.parentOptions as |entry|}}
              <option value={{entry.id}} selected={{eq entry.slug @page.parent_slug}}>
                {{#if (eq entry.kind "folder")}}📁 {{/if}}{{entry.title}}
              </option>
            {{/each}}
          </select>
        </label>
        <label>
          <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
          <select name="locale" required>
            {{#each this.localeOptions as |locale|}}
              <option value={{locale.value}} selected={{eq locale.value @page.locale}}>
                {{locale.name}}
              </option>
            {{/each}}
          </select>
        </label>
        <label class="checkbox-label">
          <input type="checkbox" name="published" checked={{@page.published}} />
          <span>{{i18n "admin.ingenic.documentation.published"}}</span>
        </label>

        {{#if this.folder}}
          <p class="ingenic-admin-form__notice">
            {{i18n "admin.ingenic.documentation.folder_hint"}}
          </p>
        {{else}}
          <label class="ingenic-admin-form__wide">
            <span>{{i18n "admin.ingenic.documentation.page_body"}}</span>
            <textarea name="body" rows="14">{{@page.body}}</textarea>
          </label>
        {{/if}}

        <button type="submit" disabled={{@busy}}>{{i18n "admin.ingenic.save"}}</button>
      </form>

      <div class="ingenic-admin-form__actions">
        <button type="button" class="btn" disabled={{@busy}} {{on "click" (fn @onRevert @page)}}>
          {{i18n "admin.ingenic.documentation.revert"}}
        </button>
        <button type="button" class="btn btn-danger" disabled={{@busy}} {{on "click" (fn @onDestroy @page)}}>
          {{i18n "admin.ingenic.documentation.delete_page"}}
        </button>
      </div>
    {{/if}}
  </template>
}
