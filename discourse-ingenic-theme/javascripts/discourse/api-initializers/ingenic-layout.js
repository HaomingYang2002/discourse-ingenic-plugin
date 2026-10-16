import { apiInitializer } from "discourse/lib/api";
import IngenicFooter from "../components/ingenic-footer";
import IngenicLocaleSwitcher from "../components/ingenic-locale-switcher";
import { applyIngenicLayout } from "../ingenic/layout";
import { registerIngenicSidebarSection } from "../ingenic/sidebar-section";

/**
 * Wires the Ingenic layout into Discourse.
 *
 * The navigation is registered as a sidebar section rather than drawn into an
 * outlet. The home page is not drawn here at all: it is a registered homepage,
 * mounted by the plugin at `/`, so it renders on its own route.
 *
 * The footer goes into above-footer, which is where the site's own footer
 * content lands, so it sits where a footer is expected and disappears with the
 * rest of the footer on the pages that hide one.
 *
 * The language switcher goes into the header's icon row. It is registered
 * before the user menu, which is the far right of the header in both states:
 * Discourse's own user menu renders nothing for a signed-out visitor, so the
 * switcher lands after the search and hamburger and beside the login button,
 * and for a signed-in one it sits immediately left of the avatar. It renders
 * nothing at all unless more than one language is configured, so a
 * single-language forum does not carry a control with one option in it.
 */
export default apiInitializer((api) => {
  applyIngenicLayout();
  registerIngenicSidebarSection(api);

  api.headerIcons.add("ingenic-locale", IngenicLocaleSwitcher, {
    before: "user-menu",
  });

  api.renderInOutlet("above-footer", IngenicFooter);
});
