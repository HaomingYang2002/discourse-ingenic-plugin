/**
 * Applies the layout theme settings.
 *
 * The sidebar is core's own element, so moving it is a matter of pointing the
 * existing grid at a different area rather than building a second navigation
 * column. The classes set here are the hooks the stylesheet reads; the width
 * needs no JavaScript because theme settings are also compiled into SCSS.
 */
export function applyIngenicLayout() {
  const root = document.documentElement;

  root.classList.toggle(
    "ingenic-sidebar-right",
    settings.ingenic_sidebar_position === "right",
  );
  root.classList.toggle("ingenic-nav-first", settings.ingenic_nav_order === "first");
}
