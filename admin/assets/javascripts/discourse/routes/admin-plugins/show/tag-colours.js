import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowTagColours extends DiscourseRoute {
  async model() {
    return ajax("/admin/plugins/discourse-ingenic/tag-colours");
  }
}
