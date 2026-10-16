import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import cookie from "discourse/lib/cookie";
import getURL from "discourse/lib/get-url";
import DMenu from "discourse/float-kit/components/d-menu";
import DDropdownMenu from "discourse/ui-kit/d-dropdown-menu";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import I18n, { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";

// Discourse keeps a reader's language in two places, and which one the server
// obeys depends on whether they are signed in: for a signed-in reader it reads
// User#effective_locale and ignores the cookie entirely, and for everyone else
// it reads the cookie. So the switch has to write to whichever one will
// actually be consulted, which is the whole reason this component is more than
// a link with a query parameter on it.
//
// Both names below are Discourse's own, not inventions: the cookie is the one
// core's own language switcher writes, and the expiry matches it, so a reader
// who switches in one place keeps the choice in the other.
const LOCALE_COOKIE = "locale";
const LOCALE_COOKIE_EXPIRY = 365;

export default class IngenicLocaleSwitcher extends Component {
  @service siteSettings;
  @service currentUser;

  get currentLocale() {
    return I18n.currentLocale();
  }

  // The languages this forum offers, in the order the setting lists them.
  //
  // Each one is labelled in its own language rather than the current one: the
  // reader who needs this menu is by definition reading a language they would
  // rather not be, so "中文" is more use to them than "Chinese".
  get options() {
    const available = this.siteSettings.available_locales ?? [];

    return this.configured
      .map((code) => code.trim())
      .filter(Boolean)
      .map((value) => ({
        value,
        label: available.find((entry) => entry.value === value)?.native_name || value,
      }));
  }

  get configured() {
    const value = settings.ingenic_locales;

    // A list setting arrives as an array, but a single-entry one can arrive as
    // the bare string, and both spellings mean the same thing here.
    return (Array.isArray(value) ? value.join("|") : (value ?? "")).split("|");
  }

  // One language is not a choice, so the switcher stays out of the header
  // entirely until there is something to switch between.
  get multiple() {
    return this.options.length > 1;
  }

  get currentLabel() {
    return (
      this.options.find((option) => option.value === this.currentLocale)?.label ??
      this.currentLocale
    );
  }

  @action
  onRegisterApi(menu) {
    this.menu = menu;
  }

  @action
  async change(locale) {
    this.menu?.close();

    if (locale === this.currentLocale) {
      return;
    }

    try {
      if (this.currentUser) {
        this.currentUser.set("locale", locale);
        await ajax(`/u/${this.currentUser.username}.json`, {
          type: "PUT",
          data: { locale },
        });
      } else {
        cookie(LOCALE_COOKIE, locale, {
          path: getURL("/"),
          expires: LOCALE_COOKIE_EXPIRY,
        });
      }
    } catch (error) {
      popupAjaxError(error);
      return;
    }

    // A reload rather than a route transition: the interface language is
    // decided while a page is being served, so the new one has to come from a
    // request the server has already answered.
    window.location.reload();
  }

  <template>
    {{#if this.multiple}}
      <li class="header-dropdown-toggle ingenic-locale">
        <DMenu
          class="btn-flat"
          @identifier="ingenic-locale"
          @onRegisterApi={{this.onRegisterApi}}
          @title={{i18n (themePrefix "ingenic.locale.title")}}
        >
          <:trigger>
            <span class="ingenic-locale__current">{{this.currentLabel}}</span>
            {{dIcon "angle-down"}}
          </:trigger>
          <:content>
            <DDropdownMenu as |dropdown|>
              {{#each this.options as |option|}}
                <dropdown.item
                  class="ingenic-locale__option {{if (eq option.value this.currentLocale) '--selected'}}"
                  data-menu-option-id={{option.value}}
                >
                  <DButton
                    @action={{fn this.change option.value}}
                    @translatedLabel={{option.label}}
                  />
                </dropdown.item>
              {{/each}}
            </DDropdownMenu>
          </:content>
        </DMenu>
      </li>
    {{/if}}
  </template>
}
