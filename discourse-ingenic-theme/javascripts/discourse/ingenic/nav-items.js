import { themePrefix } from "virtual:theme";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

// Shipped so the navigation is not empty before the Ingenic team fills in the
// plugin's setting. Anything configured on the plugin side replaces this list
// wholesale rather than merging with it, so order and labels have one owner.
//
// `section` is which of the three groups an entry belongs to:
//
//   forum      the plain list at the top — the forum itself, no heading
//   resources  the titled group below it
//   member     the plain list under that — what a member has earned or set
//              aside, which is not a developer resource and does not belong
//              under one
//
// `href` is used as written; `category` resolves to `/c/<slug>`, which is how an
// entry points at a forum section without the theme having to know category ids.
// The two lists without a heading have no other separator, so an entry's section
// is what keeps it out of the group above it.
const DEFAULT_ITEMS = [
  // The forum.
  {
    key: "new-post",
    icon: "plus",
    labelKey: "ingenic.nav.new_post",
    // Discourse's own route for "start writing": it opens the composer in
    // place, and asks a signed-out visitor to sign in first. A plain link is
    // enough because that is a real route, not a modal with no address.
    href: "/new-topic",
    section: "forum",
  },
  { key: "home", icon: "house", labelKey: "ingenic.nav.home", href: "/", section: "forum" },
  {
    key: "announcements",
    icon: "bullhorn",
    labelKey: "ingenic.nav.announcements",
    category: "official-announcements",
    section: "forum",
  },
  {
    key: "discussions",
    icon: "comments",
    labelKey: "ingenic.nav.discussions",
    category: "technical-discussions",
    section: "forum",
  },

  // The developer resources.
  { key: "docs", icon: "book", labelKey: "ingenic.nav.docs", href: "/ingenic/docs", section: "resources" },
  {
    key: "open-source",
    icon: "code",
    labelKey: "ingenic.nav.open_source",
    category: "open-source",
    section: "resources",
  },
  {
    key: "downloads",
    icon: "download",
    labelKey: "ingenic.nav.downloads",
    href: "/ingenic/downloads",
    section: "resources",
  },
  {
    key: "boards",
    icon: "microchip",
    labelKey: "ingenic.nav.boards",
    href: "/ingenic/boards",
    section: "resources",
  },

  // What the member has.
  {
    key: "bounties",
    icon: "gift",
    labelKey: "ingenic.nav.bounties",
    href: "/ingenic/bounties",
    section: "member",
  },
  { key: "points", icon: "star", labelKey: "ingenic.nav.points", href: "/ingenic/points", section: "member" },
];

// What an entry with no `section` belongs to. Unstated is the plain list at the
// top, which is where a list that says nothing about groups reads as being.
// The server normalises this on its side too, so a configured entry arrives
// carrying all three names; this is what the shipped defaults fall back to.
const DEFAULT_SECTION = "forum";

function isExternal(href) {
  return /^https?:\/\//i.test(href) || href.startsWith("//");
}

function hrefFor(item) {
  if (item.href) {
    return item.href;
  }

  return item.category ? `/c/${item.category}` : "";
}

/**
 * Turns the configured navigation into the shape the sidebar link needs.
 *
 * Entries come from the plugin's `ingenic_nav_items` site setting, which the
 * site serializer exposes so the Ingenic team can relabel, reorder or hide an
 * entry from the admin UI. The server has already resolved `category` entries
 * into hrefs and dropped entries that could not render a link; this only fills
 * in the same two things for the shipped defaults, which never went through it.
 *
 * @param {object} site the site model, carrying `ingenic_nav_items`
 * @param {string} section which group to return
 */
export function resolveNavItems(site, section) {
  const configured = site?.ingenic_nav_items;
  const items =
    Array.isArray(configured) && configured.length > 0
      ? configured
      : DEFAULT_ITEMS.map((item) => ({
          key: item.key,
          icon: item.icon,
          label: i18n(themePrefix(item.labelKey)),
          href: hrefFor(item),
          section: item.section,
        }));

  return items
    .filter((item) => item && (item.section ?? DEFAULT_SECTION) === section)
    .map((item) => ({
      key: item.key,
      label: item.label,
      icon: item.icon || "circle",
      // Kept unprefixed: it is matched against router.currentURL to decide
      // whether the link is active, and `url` is what goes in the href.
      href: item.href,
      url: getURL(item.href),
      external: item.external === true || isExternal(item.href),
    }))
    .filter((item) => item.key && item.label && item.href);
}
