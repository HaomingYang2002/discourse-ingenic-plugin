import { apiInitializer } from "discourse/lib/api";
import IngenicHomepage from "../components/ingenic-homepage";
import IngenicFooter from "../components/ingenic-footer";
import { applyIngenicLayout } from "../ingenic/layout";
import { registerIngenicSidebarSection } from "../ingenic/sidebar-section";

/**
 * Wires the Ingenic layout into Discourse.
 *
 * The navigation is registered as a sidebar section rather than drawn into an
 * outlet, and the homepage blocks render above the topic list on the discovery
 * route. Both read their content from admin-editable settings, so neither
 * reordering the navigation nor rearranging the homepage needs a theme update.
 *
 * The footer goes into above-footer, which is where the site's own footer
 * content lands, so it sits where a footer is expected and disappears with the
 * rest of the footer on the pages that hide one.
 */
export default apiInitializer((api) => {
  applyIngenicLayout();
  registerIngenicSidebarSection(api);

  api.renderInOutlet("before-topic-list", IngenicHomepage);
  api.renderInOutlet("above-footer", IngenicFooter);
});
