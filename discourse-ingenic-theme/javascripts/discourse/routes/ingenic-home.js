import DiscourseRoute from "discourse/routes/discourse";

// The home page is a route of its own rather than a panel on the discovery
// route. Discourse mounts it at `/` when `default_homepage` names it, and this
// is what `/ingenic/home` resolves to on a full page load — see the plugin's
// IngenicHomeController, which serves the shell for exactly this path.
export default class IngenicHomeRoute extends DiscourseRoute {}
