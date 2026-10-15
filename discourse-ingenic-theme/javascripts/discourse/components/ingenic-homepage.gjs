import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import IngenicBlockTopics from "./ingenic-block-topics";
import IngenicBlockDownloads from "./ingenic-block-downloads";
import IngenicBlockBoards from "./ingenic-block-boards";
import IngenicBlockSearch from "./ingenic-block-search";
import IngenicPromotions from "./ingenic-promotions";
import { i18n } from "discourse-i18n";

const BLOCK_COMPONENTS = {
  search: IngenicBlockSearch,
  promotions: IngenicPromotions,
  announcements: IngenicBlockTopics,
  discussions: IngenicBlockTopics,
  downloads: IngenicBlockDownloads,
  boards: IngenicBlockBoards,
};

export default class IngenicHomepage extends Component {
  @service site;
  @service router;

  get onHomepage() {
    return (this.router.currentURL ?? "/").split("?")[0] === "/";
  }

  get blocks() {
    return (this.site.ingenic_homepage_blocks ?? [])
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
    {{#if this.onHomepage}}
      <div class="ingenic-homepage">
        <section class="ingenic-homepage__hero">
          <div>
            <p class="ingenic-homepage__eyebrow">Ingenic developer community</p>
            <h1>{{this.heroTitle}}</h1>
            <p>{{this.heroSubtitle}}</p>
          </div>
          <div class="ingenic-homepage__hero-actions">
            <a class="btn btn-primary" href="/ingenic/docs">{{i18n (themePrefix "ingenic.nav.docs")}}</a>
            <a class="btn" href="/c/24">{{i18n (themePrefix "ingenic.nav.discussions")}}</a>
          </div>
        </section>

        <nav class="ingenic-homepage__quick-links" aria-label={{i18n (themePrefix "ingenic.home.quick_links")}}>
          <a href="/c/4"><span class="d-icon d-icon-bullhorn"></span>{{i18n (themePrefix "ingenic.nav.announcements")}}</a>
          <a href="/c/24"><span class="d-icon d-icon-comments"></span>{{i18n (themePrefix "ingenic.nav.discussions")}}</a>
          <a href="/ingenic/docs"><span class="d-icon d-icon-book"></span>{{i18n (themePrefix "ingenic.nav.docs")}}</a>
          <a href="/ingenic/downloads"><span class="d-icon d-icon-download"></span>{{i18n (themePrefix "ingenic.nav.downloads")}}</a>
          <a href="/ingenic/boards"><span class="d-icon d-icon-microchip"></span>{{i18n (themePrefix "ingenic.nav.boards")}}</a>
        </nav>

        <div class="ingenic-homepage__blocks">
          {{#each this.blocks as |entry|}}
            <entry.Component @block={{entry.block}} />
          {{/each}}
        </div>
      </div>
    {{/if}}
  </template>
}
