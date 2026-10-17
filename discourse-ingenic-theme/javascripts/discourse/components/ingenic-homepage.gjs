import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import IngenicBlockCategories from "./ingenic-block-categories";
import IngenicBlockTopics from "./ingenic-block-topics";
import IngenicBlockFeed from "./ingenic-block-feed";
import IngenicBlockDownloads from "./ingenic-block-downloads";
import IngenicBlockBoards from "./ingenic-block-boards";
import IngenicBlockBounties from "./ingenic-block-bounties";
import IngenicPromotions from "./ingenic-promotions";
import { i18n } from "discourse-i18n";

const BLOCK_COMPONENTS = {
  categories: IngenicBlockCategories,
  promotions: IngenicPromotions,
  announcements: IngenicBlockTopics,
  discussions: IngenicBlockTopics,
  latest: IngenicBlockFeed,
  hot: IngenicBlockFeed,
  downloads: IngenicBlockDownloads,
  boards: IngenicBlockBoards,
  bounties: IngenicBlockBounties,
};

// Where a block sits on the page. The front page follows meta.discourse.org's
// shape — the sections across the top, the discussion feed down the left, the
// shorter lists in a rail on the right — without freezing that shape: an
// editor can move a block between the full width, the main column and the rail
// from the admin screen.
const BLOCK_LAYOUTS = {
  categories: "full",
  bounties: "side",
  downloads: "full",
  boards: "main",
  announcements: "main",
  discussions: "main",
  latest: "main",
  promotions: "side",
  hot: "side",
};

// What the page shows before anyone has configured it. The order is meta's:
// sections first, then the discussion feed down the left, with the activity
// slots, the bounty board and the hot list stacked down the right. All three
// rail cards are above the fold together — that is why the bounty panel no
// longer spans the page under everything else.
const DEFAULT_BLOCKS = [
  { type: "categories", position: 0, limit: 3 },
  { type: "latest", position: 1, limit: 8 },
  { type: "promotions", position: 2, limit: 3 },
  { type: "bounties", position: 3, limit: 4 },
  { type: "hot", position: 4, limit: 5 },
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
      .map((block) => ({
        block,
        layout: block.layout || BLOCK_LAYOUTS[block.type] || "main",
        Component: BLOCK_COMPONENTS[block.type],
      }))
      .filter((entry) => entry.Component);
  }

  get hasRail() {
    return this.blocks.some((entry) => entry.layout === "side");
  }

  // How many cards the rail holds, so the main column can span the same number
  // of rows instead of leaving a gap once a third card is added.
  get railCards() {
    return Math.max(this.blocks.filter((entry) => entry.layout === "side").length, 1);
  }

  get heroTitle() {
    return settings.ingenic_hero_title || i18n(themePrefix("ingenic.home.title"));
  }

  get heroSubtitle() {
    return (
      settings.ingenic_hero_subtitle ||
      i18n(themePrefix("ingenic.home.subtitle"))
    );
  }

  <template>
    <div class="ingenic-homepage">
      <section class="ingenic-homepage__hero">
        <p class="ingenic-homepage__eyebrow">
          {{i18n (themePrefix "ingenic.home.eyebrow")}}
        </p>
        <h1>{{this.heroTitle}}</h1>
        <p>{{this.heroSubtitle}}</p>

        <form
          class="ingenic-homepage__search"
          action={{getURL "/search"}}
          method="get"
          role="search"
        >
          <input
            type="search"
            name="q"
            class="ingenic-homepage__search-input"
            placeholder={{i18n (themePrefix "ingenic.home.search_placeholder")}}
            aria-label={{i18n (themePrefix "ingenic.home.search_placeholder")}}
          />
          <button class="btn btn-primary" type="submit">
            {{i18n (themePrefix "ingenic.home.search")}}
          </button>
        </form>
      </section>

      <div
        class="ingenic-homepage__blocks {{if this.hasRail 'ingenic-homepage__blocks--with-rail'}}"
        style="--ingenic-rail-cards: {{this.railCards}}"
      >
        {{#each this.blocks as |entry|}}
          <div class="ingenic-homepage__block ingenic-homepage__block--{{entry.layout}}">
            <entry.Component @block={{entry.block}} />
          </div>
        {{/each}}
      </div>
    </div>
  </template>
}
