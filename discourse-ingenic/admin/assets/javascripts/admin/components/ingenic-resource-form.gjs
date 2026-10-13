import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class IngenicResourceForm extends Component {
  @tracked busy = false;
  @tracked message = null;

  get fields() {
    if (this.args.resource === "board") {
      return [
        ["name", "Name"],
        ["slug", "Slug"],
        ["locale", "Locale"],
        ["chip", "Chip"],
        ["application_url", "Application URL"],
        ["documentation_url", "Documentation URL"],
        ["image_url", "Image URL"],
        ["description", "Description"],
      ];
    }

    return [
      ["name", "Product name"],
      ["slug", "Product slug"],
      ["locale", "Locale"],
      ["description", "Description"],
    ];
  }

  @action
  async save(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    const values = Object.fromEntries(new FormData(event.target));
    const endpoint = this.args.resource === "board" ? "boards" : "documentation/products";

    try {
      await ajax(`/admin/plugins/discourse-ingenic/${endpoint}/${this.args.record.id}`, {
        type: "PUT",
        data: values,
      });
      this.message = i18n("admin.ingenic.saved");
    } catch (error) {
      this.message = error.jqXHR?.responseJSON?.errors?.join(", ") || i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    <form class="ingenic-admin-form" {{on "submit" this.save}}>
      {{#each this.fields as |field|}}
        <label>
          <span>{{field.[1]}}</span>
          <input name={{field.[0]}} value={{get @record field.[0]}} />
        </label>
      {{/each}}
      <label class="checkbox-label">
        <input type="checkbox" name="published" checked={{@record.published}} />
        <span>Published</span>
      </label>
      <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.save"}}</button>
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}
    </form>
  </template>
}
