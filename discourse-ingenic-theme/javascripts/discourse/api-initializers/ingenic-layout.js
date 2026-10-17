import { apiInitializer } from "discourse/lib/api";
import IngenicBounty from "../components/ingenic-bounty";
import IngenicFooter from "../components/ingenic-footer";
import IngenicHeaderLinks from "../components/ingenic-header-links";
import IngenicLocaleSwitcher from "../components/ingenic-locale-switcher";
import { applyIngenicLayout } from "../ingenic/layout";
import { registerIngenicSidebarSections } from "../ingenic/sidebar-section";

/**
 * Wires the Ingenic layout into Discourse.
 *
 * The navigation is registered as sidebar sections rather than drawn into an
 * outlet — three of them, so that the developer resources can carry a heading
 * while the forum above and the member's own entries below it do not. The home
 * page is not drawn here at all: it is a registered homepage, mounted by the
 * plugin at `/`, so it renders on its own route.
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
 *
 * The 高分悬赏 banner goes above the posts, which is the top of the question
 * itself: what an answer here is worth is part of reading the question, and it
 * belongs where somebody decides to answer rather than at the foot of the page.
 * Like the footer, it decides what to draw from the outlet's own payload.
 */
export default apiInitializer((api) => {
  applyIngenicLayout();
  registerIngenicSidebarSections(api);

  api.headerIcons.add("ingenic-locale", IngenicLocaleSwitcher, {
    before: "user-menu",
  });

  // The header's own buttons go in the space between the logo and the right
  // cluster, which is where the empty middle of the header is. The wrapper
  // around this outlet is a plain flex child; the stylesheet gives it the room
  // and centres what is drawn in it.
  api.renderInOutlet("before-header-panel", IngenicHeaderLinks);

  api.renderInOutlet("topic-above-posts", IngenicBounty);
  api.renderInOutlet("above-footer", IngenicFooter);
});
