import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowBoardsShow extends DiscourseRoute {
  async model(params) {
    return ajax(`/admin/plugins/discourse-ingenic/boards/${params.id}`);
  }
}
