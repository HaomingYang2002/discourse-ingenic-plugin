import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { i18n } from "discourse-i18n";

/**
 * Editor for a single page.
 *
 * An inherited page is read-only until it is materialised into the current
 * version, so the form shows where it came from and offers the override
 * instead of a save button. The reverse action puts it back to inheriting.
 */
export default class IngenicDocPageForm extends Component {
  get inherited() {
    return this.args.page.inherited;
  }

  @action
  save(event) {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.target));
    const parent = this.args.pages.find((page) => page.slug === values.parent_slug);

    this.args.onSave(this.args.page, {
      title: values.title,
      slug: values.slug,
      body: values.body,
      locale: values.locale,
      parent_id: parent ? parent.id : null,
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
          <span>{{i18n "admin.ingenic.documentation.page_slug"}}</span>
          <input name="slug" value={{@page.slug}} required />
        </label>
        <label>
          <span>{{i18n "admin.ingenic.documentation.parent_slug"}}</span>
          <input name="parent_slug" value={{@page.parent_slug}} />
        </label>
        <label>
          <span>{{i18n "admin.ingenic.documentation.locale"}}</span>
          <input name="locale" value={{@page.locale}} required />
        </label>
        <label class="checkbox-label">
          <input type="checkbox" name="published" checked={{@page.published}} />
          <span>{{i18n "admin.ingenic.documentation.published"}}</span>
        </label>
        <label class="ingenic-admin-form__wide">
          <span>{{i18n "admin.ingenic.documentation.page_body"}}</span>
          <textarea name="body" rows="14">{{@page.body}}</textarea>
        </label>
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
