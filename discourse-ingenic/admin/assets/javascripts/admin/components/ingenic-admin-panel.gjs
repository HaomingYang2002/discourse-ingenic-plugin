import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { tracked } from "@glimmer/tracking";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class IngenicAdminPanel extends Component {
  @tracked busy = false;
  @tracked message = null;

  get items() {
    return this.args.kind === "boards" ? this.args.model.boards : this.args.model.products;
  }

  @action
  async create(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;
    const values = Object.fromEntries(new FormData(event.target));
    const endpoint = this.args.kind === "boards" ? "boards" : "documentation/products";
    try {
      await ajax(`/admin/plugins/discourse-ingenic/${endpoint}`, {
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
    <div class="ingenic-admin-panel">
      <form class="ingenic-admin-panel__form" {{on "submit" this.create}}>
        {{#if (eq @kind "boards")}}
          <input name="name" placeholder="Name" required />
          <input name="slug" placeholder="Slug" required />
          <input name="chip" placeholder="Chip" />
          <input name="application_url" placeholder="Application or purchase URL" required />
        {{else}}
          <input name="name" placeholder="Product name" required />
          <input name="slug" placeholder="Product slug" required />
          <input name="locale" value="en" placeholder="Locale" required />
          <input name="description" placeholder="Description" />
        {{/if}}
        <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.create"}}</button>
      </form>
      {{#if this.message}}<p class="admin-config-area__message">{{this.message}}</p>{{/if}}
      <div class="admin-config-list">
        {{#each this.items as |item|}}
          <section class="admin-config-list__row">
            {{#if (eq @kind "boards")}}
              <LinkTo @route="adminPlugins.show.boards.show" @model={{item.id}}>{{item.name}}</LinkTo>
            {{else}}
              <LinkTo @route="adminPlugins.show.documentation.show" @model={{item.id}}>{{item.name}}</LinkTo>
            {{/if}}
            <span>{{if item.published "Published" "Draft"}}</span>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
