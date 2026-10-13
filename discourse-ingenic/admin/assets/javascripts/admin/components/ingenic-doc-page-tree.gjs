import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * The resolved page list for one version.
 *
 * The API already returns it depth-first with a depth per row, so the tree is
 * rendered as an indented list rather than nested markup — that keeps a page
 * whose parent lives in an earlier version in the right place.
 */
export default class IngenicDocPageTree extends Component {
  <template>
    <div class="ingenic-admin-tree">
      {{#each @pages as |page|}}
        <button
          type="button"
          class="ingenic-admin-tree__row ingenic-admin-tree__row--depth-{{page.depth}} {{if (eq page.slug @selectedSlug) 'is-selected'}}"
          {{on "click" (fn @onSelect page)}}
        >
          <span class="ingenic-admin-tree__title">{{page.title}}</span>
          {{#if page.inherited}}
            <span class="ingenic-admin-tree__badge">
              {{i18n "admin.ingenic.documentation.inherited_from"}} {{page.inherited_from_label}}
            </span>
          {{/if}}
        </button>
      {{else}}
        <p class="ingenic-admin-tree__empty">{{i18n "admin.ingenic.documentation.no_pages"}}</p>
      {{/each}}
    </div>
  </template>
}
