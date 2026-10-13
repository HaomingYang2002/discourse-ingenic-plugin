import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowDocumentationShow extends DiscourseRoute {
  async model(params) {
    return ajax(`/admin/plugins/discourse-ingenic/documentation/products/${params.id}`);
  }
}
