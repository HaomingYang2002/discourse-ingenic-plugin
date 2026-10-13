import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class IngenicPermissionForm extends Component {
  @tracked busy = false;
  @tracked message = null;

  @action
  async save(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    const values = Object.fromEntries(new FormData(event.target));
    if (!values.user_id) {
      delete values.user_id;
    }
    if (!values.group_id) {
      delete values.group_id;
    }
    values.permission = "manage";

    try {
      await ajax("/admin/plugins/discourse-ingenic/permissions", {
        type: "POST",
        data: values,
      });
      event.target.reset();
      this.message = i18n("admin.ingenic.saved");
    } catch (error) {
      this.message = error.jqXHR?.responseJSON?.errors?.join(", ") || i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    <form class="ingenic-admin-form ingenic-admin-form--permissions" {{on "submit" this.save}}>
      <label>
        <span>User ID (or leave blank)</span>
        <input name="user_id" inputmode="numeric" />
      </label>
      <label>
        <span>Group ID (or leave blank)</span>
        <input name="group_id" inputmode="numeric" />
      </label>
      <label>
        <span>Resource type</span>
        <select name="resource_type">
          <option value="IngenicDocProduct">Documentation product</option>
          <option value="IngenicDocPage">Documentation page</option>
          <option value="IngenicBoard">Development board</option>
        </select>
      </label>
      <label>
        <span>Resource ID</span>
        <input name="resource_id" inputmode="numeric" required />
      </label>
      <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.assign"}}</button>
      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}
    </form>
  </template>
}
