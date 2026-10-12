import Component from "@glimmer/component";
import { service } from "@ember/service";
import IngenicBlockSearch from "./ingenic-block-search";
import IngenicBlockTopics from "./ingenic-block-topics";
import IngenicBlockDownloads from "./ingenic-block-downloads";
import IngenicBlockBoards from "./ingenic-block-boards";

const BLOCK_COMPONENTS = {
  search: IngenicBlockSearch,
  announcements: IngenicBlockTopics,
  discussions: IngenicBlockTopics,
  downloads: IngenicBlockDownloads,
  boards: IngenicBlockBoards,
};

/**
 * Custom homepage composed from admin-configured blocks.
 *
 * Order and visibility come from the `ingenic_homepage_blocks` site setting, so
 * the Ingenic team can rearrange the homepage from the admin UI. Unknown block
 * types are ignored rather than rendered as broken sections.
 */
export default class IngenicHomepage extends Component {
  @service site;
  @service router;

  // The outlet this renders into sits above the topic list on every discovery
  // route, but the blocks are a homepage, not a banner — so only show them at
  // the root.
  get onHomepage() {
    return (this.router.currentURL ?? "/").split("?")[0] === "/";
  }

  get blocks() {
    return (this.site.ingenic_homepage_blocks ?? [])
      .map((block) => ({
        block,
        Component: BLOCK_COMPONENTS[block.type],
      }))
      .filter((entry) => entry.Component);
  }

  get heroTitle() {
    return settings.ingenic_hero_title;
  }

  get heroSubtitle() {
    return settings.ingenic_hero_subtitle;
  }

  <template>
    {{#if this.onHomepage}}
      <div class="ingenic-homepage">
        {{#if this.heroTitle}}
          <section class="ingenic-hero">
            <h1 class="ingenic-hero__title">{{this.heroTitle}}</h1>
            {{#if this.heroSubtitle}}
              <p class="ingenic-hero__subtitle">{{this.heroSubtitle}}</p>
            {{/if}}
          </section>
        {{/if}}

        {{#each this.blocks as |entry|}}
          <entry.Component @block={{entry.block}} />
        {{/each}}
      </div>
    {{/if}}
  </template>
}
