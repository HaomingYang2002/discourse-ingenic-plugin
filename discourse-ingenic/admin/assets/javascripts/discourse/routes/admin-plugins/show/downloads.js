import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

const ENDPOINT = "/admin/plugins/discourse-ingenic";

export default class AdminPluginsShowDownloads extends DiscourseRoute {
  async model() {
    const [resources, requests, grants] = await Promise.all([
      ajax(`${ENDPOINT}/downloads`),
      // Deciding an application is an administrator's act, so a scoped content
      // manager is refused here. That is not a failure of the page they did ask
      // for, so the refusal is caught and the tab is simply not offered.
      ajax(`${ENDPOINT}/download-requests`).catch(() => null),
      ajax(`${ENDPOINT}/download-grants`).catch(() => null),
    ]);

    return { resources, requests, grants };
  }
}
