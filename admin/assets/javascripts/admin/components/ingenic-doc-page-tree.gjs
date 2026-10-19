import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

// How many indentation steps the plugin's stylesheet defines, so a page nested
// deeper than the last one keeps the last one's indentation rather than
// falling back to none.
const MAX_INDENT = 8;

/**
 * The resolved page list for one version.
 *
 * The API already returns it depth-first with a depth per row, so the tree is
 * rendered as an indented list rather than nested markup — that keeps a page
 * whose parent lives in an earlier version in the right place.
 *
 * Folders and articles share the list and differ only by their badge. Rows
 * this version owns carry move buttons; an inherited row is ordered by the
 * version that holds it, so moving it here would edit that version instead.
 */
export default class IngenicDocPageTree extends Component {
  get rows() {
    return this.args.pages.map((page) => ({
      ...page,
      folder: page.kind === "folder",
      indent: Math.min(page.depth ?? 0, MAX_INDENT),
    }));
  }

  <template>
    <div class="ingenic-admin-tree">
      {{#each this.rows as |page|}}
        <div
          class="ingenic-admin-tree__row ingenic-admin-tree__row--indent-{{page.indent}} {{if (eq page.slug @selectedSlug) 'is-selected'}}"
        >
          <button type="button" class="ingenic-admin-tree__select" {{on "click" (fn @onSelect page)}}>
            <span class="ingenic-admin-tree__title">
              {{#if page.folder}}
                <span class="ingenic-admin-tree__kind" aria-hidden="true">📁</span>
              {{/if}}
              {{page.title}}
            </span>
            {{#if page.inherited}}
              <span class="ingenic-admin-tree__badge">
                {{i18n "admin.ingenic.documentation.inherited_from"}} {{page.inherited_from_label}}
              </span>
            {{/if}}
          </button>

          {{#unless page.inherited}}
            <span class="ingenic-admin-tree__tools">
              <button
                type="button"
                title={{i18n "admin.ingenic.documentation.move_up"}}
                {{on "click" (fn @onMove page -1)}}
              >↑</button>
              <button
                type="button"
                title={{i18n "admin.ingenic.documentation.move_down"}}
                {{on "click" (fn @onMove page 1)}}
              >↓</button>
            </span>
          {{/unless}}
        </div>
      {{else}}
        <p class="ingenic-admin-tree__empty">{{i18n "admin.ingenic.documentation.no_pages"}}</p>
      {{/each}}
    </div>
  </template>
}
