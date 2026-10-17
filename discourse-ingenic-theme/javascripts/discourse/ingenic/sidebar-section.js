import { themePrefix } from "virtual:theme";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import { hrefFor, resolveNavItems } from "./nav-items";

/**
 * Registers the Ingenic navigation as first-class Discourse sidebar sections.
 *
 * Three of them, because the navigation is three things: the forum itself at
 * the top, the developer resources under their own heading, and what a member
 * has earned or set aside at the bottom. Only the middle one is drawn with a
 * heading — one over the topic list would be a label on the forum, and one over
 * 高分悬赏 and Points would file them under the resources above them, which is
 * exactly where they do not belong.
 *
 * Rendering a bare <nav> into a plugin outlet looks similar but is not the same
 * thing: it would sit beside Discourse's own sidebar rather than inside it, so
 * it would miss the mobile drawer, the section filter, the collapse state and
 * the active-link handling that core already implements. Going through the
 * public API keeps all of that and leaves no private surface to maintain.
 *
 * Sections draw in the order they were registered, and core draws its own
 * sections around ours (categories, tags, the user's own sections, the filter
 * box). Where this block sits relative to those is therefore the stylesheet's
 * decision, not a matter of registration order — see `ingenic_nav_order`.
 *
 * A section with `hideSectionHeader` is always drawn expanded: core returns
 * true from `displaySectionContent` for it, whatever the collapse state says.
 */

// The groups, in the order they are read. `text` is the heading for the one
// group that has one; for the others it is only what the sidebar's filter
// matches, since nothing is drawn.
const GROUPS = [
  {
    name: "ingenic-forum",
    section: "forum",
    titled: false,
    textKey: "ingenic.nav.sections.forum",
  },
  {
    name: "ingenic-resources",
    section: "resources",
    titled: true,
    // An administrator's own words for the group, falling back to the theme's.
    textKey: "ingenic.nav.title",
    textSetting: "ingenic_nav_title",
  },
  {
    name: "ingenic-member",
    section: "member",
    titled: false,
    textKey: "ingenic.nav.sections.member",
  },
  // Site Feedback and All categories used to be drawn by core's Categories
  // section. That section repeated the forum's name above the same three links
  // and pushed the lists below it down, so it is hidden and the two links are
  // drawn directly under Topics instead — same order, no heading. Core offers
  // no API for removing a link from its own section, hence the stylesheet.
  {
    name: "ingenic-topic-links",
    section: "topic-links",
    titled: false,
    textKey: "ingenic.nav.sections.topics",
  },
];

/**
 * One row of the navigation. Core hands the base class to each registration
 * callback, so the link class is built from it rather than imported.
 */
function makeLinkClass(BaseCustomSidebarSectionLink) {
  return class IngenicSectionLink extends BaseCustomSidebarSectionLink {
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
    // reading /ingenic/docs/t-series/t33/1.0/overview still sees Documentation
    // highlighted. Core's own comparison is exact, and these links are plain
    // URLs with no route behind them, so the decision is made here instead —
    // `isActiveLink` honours a boolean `currentWhen` first. Reading
    // router.currentURL is what keeps this tracked, so it updates as you move.
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
  };
}

export function registerIngenicSidebarSections(api) {
  for (const group of GROUPS) {
    api.addSidebarSection(
      (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
        const IngenicSectionLink = makeLinkClass(BaseCustomSidebarSectionLink);

        return class extends BaseCustomSidebarSection {
          @service router;
          @service site;

          get name() {
            return group.name;
          }

          get title() {
            return this.text;
          }

          get text() {
            const configured = group.textSetting
              ? settings[group.textSetting]
              : null;

            return configured || i18n(themePrefix(group.textKey));
          }

          get hideSectionHeader() {
            return !group.titled;
          }

          get links() {
            if (group.section === "topic-links") {
              return this.topicLinks;
            }

            return resolveNavItems(this.site, group.section).map(
              (item) => new IngenicSectionLink({ item, router: this.router }),
            );
          }

          // Written out here rather than in the navigation defaults because
          // the configured `ingenic_nav_items` setting replaces the shipped
          // list wholesale. These two links are not tools an editor chose to
          // show; they are how the site is browsed, and hiding core's
          // Categories section without them would leave no way to browse it at
          // all. Site Feedback's id is read from the site, the same way an
          // entry naming a category resolves one.
          get topicLinks() {
            const items = [
              {
                key: "site-feedback",
                icon: "comments",
                label: i18n(themePrefix("ingenic.nav.site_feedback")),
                href: hrefFor({ category: "site-feedback" }, this.site),
              },
              {
                key: "all-categories",
                icon: "list",
                label: i18n(themePrefix("ingenic.nav.all_categories")),
                href: "/categories",
              },
            ];

            return items.map(
              (item) =>
                new IngenicSectionLink({
                  item: {
                    ...item,
                    url: getURL(item.href),
                    external: false,
                  },
                  router: this.router,
                }),
            );
          }

          get displaySection() {
            return this.links.length > 0;
          }
        };
      },
    );
  }
}
