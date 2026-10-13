import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import { loadSiteContent } from "../ingenic/site-content";

/**
 * The site footer: the partner platform strip, and the footer's link columns.
 *
 * Both are lists the Ingenic team edits, which is the point — a partner platform
 * is a GitHub icon one month and a WeChat code the next, and neither should need
 * a theme release to add.
 *
 * A platform is one of two shapes. A link opens somewhere; a QR code opens a
 * panel over the page showing the image, because a code that navigates is a
 * worse experience than a code that is looked at.
 */
export default class IngenicFooter extends Component {
  @tracked socialLinks = [];
  @tracked columns = [];
  @tracked openQr = null;

  // Loaded from here rather than from a `did-insert` on the footer, because the
  // footer is what the load decides to draw: a modifier inside the conditional
  // would be waiting for the element that is waiting for the modifier.
  //
  // The component is built again on every route change, and the request itself
  // is shared, so the repeats cost nothing and the footer is there immediately
  // on the pages after the first.
  constructor(owner, args) {
    super(owner, args);
    this.#load();
  }

  // The outlet the footer sits in is the site's footer, so it follows the site's
  // own decision about whether a footer is being shown at all.
  get showFooter() {
    return this.args.outletArgs?.showFooter !== false;
  }

  get hasContent() {
    return this.socialLinks.length > 0 || this.columns.length > 0;
  }

  get visible() {
    return this.showFooter && this.hasContent;
  }

  async #load() {
    const payload = await loadSiteContent();
    this.socialLinks = payload.social_links ?? [];
    this.columns = payload.footer_columns ?? [];
  }

  @action
  toggleQr(link, event) {
    event.preventDefault();
    this.openQr = this.openQr === link.id ? null : link.id;
  }

  @action
  closeQr() {
    this.openQr = null;
  }

  <template>
    {{#if this.visible}}
      <footer class="ingenic-footer">
        <div class="ingenic-footer__inner">
          {{#if this.socialLinks.length}}
            <section class="ingenic-footer__platforms">
              <h2 class="ingenic-footer__heading">
                {{i18n (themePrefix "ingenic.footer.platforms")}}
              </h2>

              <ul class="ingenic-footer__strip">
                {{#each this.socialLinks as |link|}}
                  <li class="ingenic-footer__platform">
                    {{#if (eq link.kind "qr")}}
                      <button
                        class="ingenic-footer__link"
                        type="button"
                        aria-expanded={{if (eq this.openQr link.id) "true" "false"}}
                        {{on "click" (fn this.toggleQr link)}}
                      >
                        {{#if link.image_url}}
                          <img
                            class="ingenic-footer__icon"
                            src={{link.image_url}}
                            alt=""
                            loading="lazy"
                          />
                        {{/if}}
                        <span>{{link.label}}</span>
                      </button>

                      {{#if (eq this.openQr link.id)}}
                        <div class="ingenic-footer__qr">
                          {{#if link.qr_image_url}}
                            <img src={{link.qr_image_url}} alt={{link.label}} />
                          {{/if}}
                          {{#if link.qr_caption}}
                            <p>{{link.qr_caption}}</p>
                          {{/if}}
                          <button
                            class="btn btn-small"
                            type="button"
                            {{on "click" this.closeQr}}
                          >
                            {{i18n (themePrefix "ingenic.footer.close")}}
                          </button>
                        </div>
                      {{/if}}
                    {{else}}
                      <a
                        class="ingenic-footer__link"
                        href={{link.href}}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        {{#if link.image_url}}
                          <img
                            class="ingenic-footer__icon"
                            src={{link.image_url}}
                            alt=""
                            loading="lazy"
                          />
                        {{/if}}
                        <span>{{link.label}}</span>
                      </a>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            </section>
          {{/if}}

          {{#if this.columns.length}}
            <nav class="ingenic-footer__columns">
              {{#each this.columns as |column|}}
                <section class="ingenic-footer__column">
                  <h2 class="ingenic-footer__heading">{{column.title}}</h2>
                  <ul>
                    {{#each column.links as |link|}}
                      <li>
                        {{#if link.external}}
                          <a
                            href={{link.href}}
                            target="_blank"
                            rel="noopener noreferrer"
                          >{{link.label}}</a>
                        {{else}}
                          <a href={{link.href}}>{{link.label}}</a>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                </section>
              {{/each}}
            </nav>
          {{/if}}
        </div>
      </footer>
    {{/if}}
  </template>
}
