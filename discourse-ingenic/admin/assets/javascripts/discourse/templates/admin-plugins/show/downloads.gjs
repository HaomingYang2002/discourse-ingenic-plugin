import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicDownloadManager from "../../../../admin/components/ingenic-download-manager";
import IngenicDownloadQueue from "../../../../admin/components/ingenic-download-queue";
import IngenicGrantList from "../../../../admin/components/ingenic-grant-list";
import { i18n } from "discourse-i18n";

/**
 * The three surfaces of the download centre on one page.
 *
 * They sit together because they are read together: a resource's access level
 * is the reason its queue exists, and the queue is the reason a grant exists.
 * Switching between them does not refetch, so a decision made in one is visible
 * in the others.
 *
 * A scoped content manager is refused the queue and the grant list — deciding
 * an application is an administrative act rather than a content edit — so those
 * two arrive as null and their tabs are not offered.
 */
export default class AdminPluginsShowDownloads extends Component {
  @tracked tab = "resources";

  get canReview() {
    return Boolean(this.args.model.requests) && Boolean(this.args.model.grants);
  }

  get isResources() {
    return this.tab === "resources" || !this.canReview;
  }

  get isRequests() {
    return this.tab === "requests" && this.canReview;
  }

  get isGrants() {
    return this.tab === "grants" && this.canReview;
  }

  @action
  show(tab, event) {
    event.preventDefault();
    this.tab = tab;
  }

  <template>
    <div class="admin-detail">
      <DPageSubheader
        @titleLabel={{i18n "admin.ingenic.downloads.title"}}
        @descriptionLabel={{i18n "admin.ingenic.downloads.description"}}
      />

      <div class="ingenic-admin__tabs">
        <button
          class="btn {{if this.isResources 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "resources")}}
        >
          {{i18n "admin.ingenic.downloads.tab_resources"}}
        </button>
        {{#if this.canReview}}
          <button
            class="btn {{if this.isRequests 'btn-primary'}}"
            type="button"
            {{on "click" (fn this.show "requests")}}
          >
            {{i18n "admin.ingenic.downloads.tab_requests"}}
          </button>
          <button
            class="btn {{if this.isGrants 'btn-primary'}}"
            type="button"
            {{on "click" (fn this.show "grants")}}
          >
            {{i18n "admin.ingenic.downloads.tab_grants"}}
          </button>
        {{/if}}
      </div>

      {{#if this.isRequests}}
        <IngenicDownloadQueue @requests={{this.args.model.requests.requests}} />
      {{else if this.isGrants}}
        <IngenicGrantList @grants={{this.args.model.grants.grants}} />
      {{else}}
        <IngenicDownloadManager
          @downloads={{this.args.model.resources.downloads}}
          @categories={{this.args.model.resources.categories}}
          @accessLevels={{this.args.model.resources.access_levels}}
          @storageWritable={{this.args.model.resources.storage_writable}}
        />
      {{/if}}
    </div>
  </template>
}
