import { themePrefix } from "virtual:theme";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

// Shipped so the navigation is not empty before the Ingenic team fills in the
// plugin's setting. Anything configured on the plugin side replaces this list
// wholesale rather than merging with it, so order and labels have one owner.
//
// These are the three entries of the Developer Center group. Discourse's own
// Topics and Categories sections sit above this one and are left alone.
const DEFAULT_ITEMS = [
  { key: "docs", icon: "book", labelKey: "ingenic.nav.docs", href: "/ingenic/docs" },
  {
    key: "downloads",
    icon: "download",
    labelKey: "ingenic.nav.downloads",
    href: "/ingenic/downloads",
  },
  {
    key: "boards",
    icon: "microchip",
    labelKey: "ingenic.nav.boards",
    href: "/ingenic/boards",
  },
];

function isExternal(href) {
  return /^https?:\/\//i.test(href) || href.startsWith("//");
}

/**
 * Turns the configured navigation into the shape the sidebar link needs.
 *
 * Entries come from the plugin's `ingenic_nav_items` site setting, which the
 * site serializer exposes so the Ingenic team can relabel, reorder or hide an
 * entry from the admin UI. A malformed value is already filtered out server
 * side; this only drops entries that could not render a usable link.
 */
export function resolveNavItems(site) {
  const configured = site?.ingenic_nav_items;
  const items =
    Array.isArray(configured) && configured.length > 0
      ? configured
      : DEFAULT_ITEMS.map((item) => ({
          key: item.key,
          icon: item.icon,
          label: i18n(themePrefix(item.labelKey)),
          href: item.href,
        }));

  return items
    .filter((item) => item && item.href && item.label)
    .map((item, index) => ({
      key: item.key || `item-${index}`,
      label: item.label,
      icon: item.icon || "circle",
      // Kept unprefixed: it is matched against router.currentURL to decide
      // whether the link is active, and `url` is what goes in the href.
      href: item.href,
      url: getURL(item.href),
      external: item.external === true || isExternal(item.href),
    }));
}
