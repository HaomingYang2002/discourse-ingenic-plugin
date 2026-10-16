import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import IngenicBlockCategories from "./ingenic-block-categories";
import IngenicBlockTopics from "./ingenic-block-topics";
import IngenicBlockDownloads from "./ingenic-block-downloads";
import IngenicBlockBoards from "./ingenic-block-boards";
import IngenicBlockBounties from "./ingenic-block-bounties";
import IngenicPromotions from "./ingenic-promotions";
import { i18n } from "discourse-i18n";

// Search is deliberately absent: the header already carries the forum's own
// search, and a second box on the homepage that ran the same query was one
// place too many to type it.
const BLOCK_COMPONENTS = {
  categories: IngenicBlockCategories,
  promotions: IngenicPromotions,
  announcements: IngenicBlockTopics,
  discussions: IngenicBlockTopics,
  downloads: IngenicBlockDownloads,
  boards: IngenicBlockBoards,
  bounties: IngenicBlockBounties,
};

// What the page shows before anyone has configured it. A front page made of
// nothing but a banner is not a front page, and the sections grid is the one
// block that needs no decision from an editor to be worth reading. Configured
// blocks replace this list wholesale, the way the navigation setting does.
//
// The bounty panel is here because it draws nothing while nothing is on offer:
// it is a default that costs a forum with no bounties nothing, and the one
// front-page block whose content the members produce themselves.
const DEFAULT_BLOCKS = [
  { type: "categories", position: 0 },
  { type: "bounties", position: 1 },
];

/**
 * The home page.
 *
 * This is a page of its own, mounted at `/` through Discourse's homepage
 * setting, and no longer an outlet on the discovery route — which is what it
 * used to be, and why choosing "Latest" used to take the front page away with
 * it. Nothing here has to ask whether it is on the home page: it is only ever
 * rendered there.
 */
export default class IngenicHomepage extends Component {
  @service site;

  get blocks() {
    const configured = this.site.ingenic_homepage_blocks ?? [];
    const blocks = configured.length ? configured : DEFAULT_BLOCKS;

    return blocks
      .map((block) => ({ block, Component: BLOCK_COMPONENTS[block.type] }))
      .filter((entry) => entry.Component);
  }

  get heroTitle() {
    return settings.ingenic_hero_title || i18n(themePrefix("ingenic.home.title"));
  }

  get heroSubtitle() {
    return settings.ingenic_hero_subtitle || i18n(themePrefix("ingenic.home.subtitle"));
  }

  <template>
    <div class="ingenic-homepage">
      <section class="ingenic-homepage__hero">
        <div>
          <p class="ingenic-homepage__eyebrow">{{i18n (themePrefix "ingenic.home.eyebrow")}}</p>
          <h1>{{this.heroTitle}}</h1>
          <p>{{this.heroSubtitle}}</p>
        </div>
        <div class="ingenic-homepage__hero-actions">
          <a class="btn btn-primary" href="/ingenic/docs">{{i18n (themePrefix "ingenic.nav.docs")}}</a>
          <a class="btn" href="/latest">{{i18n (themePrefix "ingenic.nav.discussions")}}</a>
        </div>
      </section>

      <nav class="ingenic-homepage__quick-links" aria-label={{i18n (themePrefix "ingenic.home.quick_links")}}>
        <a href="/ingenic/docs">{{dIcon "book"}}{{i18n (themePrefix "ingenic.nav.docs")}}</a>
        <a href="/ingenic/downloads">{{dIcon "download"}}{{i18n (themePrefix "ingenic.nav.downloads")}}</a>
        <a href="/ingenic/boards">{{dIcon "microchip"}}{{i18n (themePrefix "ingenic.nav.boards")}}</a>
        <a href="/ingenic/bounties">{{dIcon "gift"}}{{i18n (themePrefix "ingenic.nav.bounties")}}</a>
        <a href="/ingenic/points">{{dIcon "star"}}{{i18n (themePrefix "ingenic.nav.points")}}</a>
      </nav>

      <div class="ingenic-homepage__blocks">
        {{#each this.blocks as |entry|}}
          <entry.Component @block={{entry.block}} />
        {{/each}}
      </div>
    </div>
  </template>
}
