import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowSite extends DiscourseRoute {
  model() {
    // One request: the three lists are short, and they are drawn on one screen.
    return ajax("/admin/plugins/discourse-ingenic/site");
  }
}
