import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicHomepageManager from "../../../../admin/components/ingenic-homepage-manager";
import IngenicPromotionManager from "../../../../admin/components/ingenic-promotion-manager";
import IngenicSocialLinkManager from "../../../../admin/components/ingenic-social-link-manager";
import IngenicFooterManager from "../../../../admin/components/ingenic-footer-manager";
import { i18n } from "discourse-i18n";

/**
 * The parts of the site that are content rather than forum: the promotion slots
 * on the homepage, the partner platforms in the footer strip, and the footer's
 * link columns.
 *
 * They share a screen because they are the same kind of thing — short ordered
 * lists of things with a picture, a label and a destination — and because an
 * editor changing the site's front page is usually changing more than one of
 * them at a time.
 */
export default class AdminPluginsShowSite extends Component {
  // The layout comes first: it decides what the front page is, and the other
  // tabs fill the slots it places.
  @tracked tab = "homepage";

  get isHomepage() {
    return this.tab === "homepage";
  }

  get isPromotions() {
    return this.tab === "promotions";
  }

  get isSocialLinks() {
    return this.tab === "social-links";
  }

  get isFooter() {
    return this.tab === "footer";
  }

  @action
  show(tab, event) {
    event.preventDefault();
    this.tab = tab;
  }

  <template>
    <div class="admin-detail">
      <DPageSubheader
        @titleLabel={{i18n "admin.ingenic.site.title"}}
        @descriptionLabel={{i18n "admin.ingenic.site.description"}}
      />

      <div class="ingenic-admin__tabs">
        <button
          class="btn {{if this.isHomepage 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "homepage")}}
        >
          {{i18n "admin.ingenic.site.tab_homepage"}}
        </button>
        <button
          class="btn {{if this.isPromotions 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "promotions")}}
        >
          {{i18n "admin.ingenic.site.tab_promotions"}}
        </button>
        <button
          class="btn {{if this.isSocialLinks 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "social-links")}}
        >
          {{i18n "admin.ingenic.site.tab_social_links"}}
        </button>
        <button
          class="btn {{if this.isFooter 'btn-primary'}}"
          type="button"
          {{on "click" (fn this.show "footer")}}
        >
          {{i18n "admin.ingenic.site.tab_footer"}}
        </button>
      </div>

      {{#if this.isHomepage}}
        <IngenicHomepageManager @homepageBlocks={{@model.homepage_blocks}} />
      {{else if this.isSocialLinks}}
        <IngenicSocialLinkManager @socialLinks={{@model.social_links}} />
      {{else if this.isFooter}}
        <IngenicFooterManager @footerColumns={{@model.footer_columns}} />
      {{else}}
        <IngenicPromotionManager @promotions={{@model.promotions}} />
      {{/if}}
    </div>
  </template>
}
