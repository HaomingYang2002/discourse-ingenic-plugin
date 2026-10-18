import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowCategoryPermissions extends DiscourseRoute {
  async model() {
    return ajax("/admin/plugins/discourse-ingenic/category-permissions");
  }
}
