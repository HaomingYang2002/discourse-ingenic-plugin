import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class IngenicPermissionList extends Component {
  @tracked permissions = this.args.permissions;
  @tracked error = null;

  @action
  async revoke(permission, event) {
    event.preventDefault();
    this.error = null;

    try {
      await ajax(`/admin/plugins/discourse-ingenic/permissions/${permission.id}`, {
        type: "DELETE",
      });
      this.permissions = this.permissions.filter((item) => item.id !== permission.id);
    } catch {
      this.error = i18n("admin.ingenic.save_failed");
    }
  }

  <template>
    {{#if this.error}}<p class="admin-config-area__message">{{this.error}}</p>{{/if}}
    <div class="admin-config-list">
      {{#each this.permissions as |permission|}}
        <section class="admin-config-list__row">
          <div>
            <strong>{{permission.resource_type}} #{{permission.resource_id}}</strong>
            <div class="admin-config-list__meta">
              {{permission.permission}} ·
              {{#if permission.user_id}}User {{permission.user_id}}{{else}}Group {{permission.group_id}}{{/if}}
            </div>
          </div>
          <button class="btn btn-danger" type="button" {{on "click" (fn this.revoke permission)}}>
            {{i18n "admin.ingenic.revoke"}}
          </button>
        </section>
      {{else}}
        <p>{{i18n "admin.ingenic.permissions.empty"}}</p>
      {{/each}}
    </div>
  </template>
}
