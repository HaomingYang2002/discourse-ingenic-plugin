import { apiInitializer } from "discourse/lib/api";
import IngenicHomepage from "../components/ingenic-homepage";
import { applyIngenicLayout } from "../ingenic/layout";
import { registerIngenicSidebarSection } from "../ingenic/sidebar-section";

/**
 * Wires the Ingenic layout into Discourse.
 *
 * The navigation is registered as a sidebar section rather than drawn into an
 * outlet, and the homepage blocks render above the topic list on the discovery
 * route. Both read their content from admin-editable settings, so neither
 * reordering the navigation nor rearranging the homepage needs a theme update.
 */
export default apiInitializer((api) => {
  applyIngenicLayout();
  registerIngenicSidebarSection(api);

  api.renderInOutlet("before-topic-list", IngenicHomepage);
});
