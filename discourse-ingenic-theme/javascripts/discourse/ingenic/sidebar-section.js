import { themePrefix } from "virtual:theme";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import { resolveNavItems } from "./nav-items";

/**
 * Registers the Ingenic navigation as a first-class Discourse sidebar section.
 *
 * Rendering a bare <nav> into a plugin outlet looks similar but is not the same
 * thing: it would sit beside Discourse's own sidebar rather than inside it, so
 * it would miss the mobile drawer, the section filter, the collapse state and
 * the active-link handling that core already implements. Going through the
 * public API keeps all of that and leaves no private surface to maintain.
 */
export function registerIngenicSidebarSection(api) {
  api.addSidebarSection((BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
    class IngenicSectionLink extends BaseCustomSidebarSectionLink {
      constructor({ item, router }) {
        super(...arguments);
        this.item = item;
        this.router = router;
      }

      get name() {
        return this.item.key;
      }

      get classNames() {
        return "ingenic-sidebar-link";
      }

      get text() {
        return this.item.label;
      }

      get title() {
        return this.item.label;
      }

      get href() {
        return this.item.url;
      }

      get prefixType() {
        return "icon";
      }

      get prefixValue() {
        return this.item.icon;
      }

      get keywords() {
        return { navigation: [this.item.label] };
      }

      // A link counts as active for the whole subtree it points at, so someone
      // reading /ingenic/docs/t32pro/2.1.0/overview still sees Documentation
      // highlighted. Core's own comparison is exact-or-route-based, and these
      // links are plain URLs, so the decision is made here instead. Reading
      // router.currentURL keeps this tracked, so it updates on navigation.
      get currentWhen() {
        if (this.item.external) {
          return false;
        }

        const current = (this.router.currentURL ?? "").split("?")[0];
        const target = this.item.href;

        if (target === "/") {
          return current === "/";
        }

        return current === target || current.startsWith(`${target}/`);
      }
    }

    return class IngenicSection extends BaseCustomSidebarSection {
      @service router;
      @service site;

      get name() {
        return "ingenic";
      }

      get title() {
        return this.text;
      }

      get text() {
        return settings.ingenic_nav_title || i18n(themePrefix("ingenic.nav.title"));
      }

      // The header stays. This section sits below Discourse's Topics and
      // Categories groups, which both carry headers, so an unlabelled list of
      // three links underneath them reads as a continuation of Categories
      // rather than as its own group. The setting only renames it.
      get hideSectionHeader() {
        return false;
      }

      get links() {
        return resolveNavItems(this.site).map(
          (item) => new IngenicSectionLink({ item, router: this.router }),
        );
      }

      get displaySection() {
        return this.links.length > 0;
      }
    };
  });
}
