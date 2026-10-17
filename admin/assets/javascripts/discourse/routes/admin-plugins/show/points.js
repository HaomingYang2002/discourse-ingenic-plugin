import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

const ENDPOINT = "/admin/plugins/discourse-ingenic";

export default class AdminPluginsShowPoints extends DiscourseRoute {
  model() {
    // One request: the rules, the recent movements and the balances are the
    // same screen, and the totals at the top are computed from the ledger the
    // movements come from — fetching them separately could show a total that
    // does not match the rows under it.
    return ajax(`${ENDPOINT}/points`);
  }
}
