import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * The buttons in the header, beside the logo: the official site, GitHub, and
 * whatever else the Ingenic team adds.
 *
 * The list is content — it arrives in the site payload, so the first paint has
 * it and the header does not grow a row of buttons a moment after the page
 * appears. Each entry is either a name, an icon (built in or an image), or
 * both; an icon-only button keeps its name as its accessible label, so the
 * button is still announced.
 *
 * It draws nothing at all when the list is empty, which is the state a fresh
 * install starts in: a header with a gap where buttons would be is worse than
 * a header without them.
 */
export default class IngenicHeaderLinks extends Component {
  @service site;

  get links() {
    return this.site.ingenic_header_links ?? [];
  }

  get label() {
    return i18n(themePrefix("ingenic.header_links.label"));
  }

  iconFor(link) {
    return link.icon || (link.show_label ? null : "link");
  }

  <template>
    {{#if this.links.length}}
      <nav class="ingenic-header-links" aria-label={{this.label}}>
        {{#each this.links as |link|}}
          <a
            class="ingenic-header-links__link"
            href={{link.href}}
            target={{if link.external "_blank"}}
            rel={{if link.external "noopener noreferrer"}}
            aria-label={{if link.show_label null link.label}}
            title={{if link.show_label null link.label}}
          >
            {{#if link.image_url}}
              <img
                class="ingenic-header-links__image"
                src={{link.image_url}}
                alt=""
                loading="lazy"
              />
            {{else if (this.iconFor link)}}
              {{dIcon (this.iconFor link)}}
            {{/if}}

            {{#if link.show_label}}
              <span>{{link.label}}</span>
            {{/if}}
          </a>
        {{/each}}
      </nav>
    {{/if}}
  </template>
}
