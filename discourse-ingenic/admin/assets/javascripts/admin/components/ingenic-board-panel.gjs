import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

const BASE = "/admin/plugins/discourse-ingenic";

export default class IngenicBoardPanel extends Component {
  @tracked boards = this.args.boards;
  @tracked busy = false;
  @tracked message = null;

  @action
  async create(event) {
    event.preventDefault();
    this.busy = true;
    this.message = null;

    try {
      await ajax(`${BASE}/boards`, {
        type: "POST",
        data: Object.fromEntries(new FormData(event.target)),
      });
      event.target.reset();
      const payload = await ajax(`${BASE}/boards`);
      this.boards = payload.boards;
      this.message = i18n("admin.ingenic.saved");
    } catch (error) {
      this.message =
        error.jqXHR?.responseJSON?.errors?.join(", ") || i18n("admin.ingenic.save_failed");
    } finally {
      this.busy = false;
    }
  }

  <template>
    <div class="ingenic-admin-panel">
      <form class="ingenic-admin-form ingenic-admin-form--inline" {{on "submit" this.create}}>
        <input name="name" placeholder={{i18n "admin.ingenic.boards.name"}} required />
        <input name="slug" placeholder={{i18n "admin.ingenic.boards.slug"}} required />
        <input name="chip" placeholder={{i18n "admin.ingenic.boards.chip"}} />
        <input name="application_url" placeholder={{i18n "admin.ingenic.boards.application_url"}} required />
        <button type="submit" disabled={{this.busy}}>{{i18n "admin.ingenic.create"}}</button>
      </form>

      {{#if this.message}}<p class="ingenic-admin-note">{{this.message}}</p>{{/if}}

      <div class="ingenic-admin-list">
        {{#each this.boards as |board|}}
          <section class="ingenic-admin-list__row">
            <LinkTo @route="adminPlugins.show.boards.show" @model={{board.id}}>{{board.name}}</LinkTo>
            <span>{{if board.published "Published" "Draft"}}</span>
          </section>
        {{else}}
          <p>{{i18n "admin.ingenic.boards.empty"}}</p>
        {{/each}}
      </div>
    </div>
  </template>
}
