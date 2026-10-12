import DiscourseRoute from "discourse/routes/discourse";

/**
 * Landing route for `/ingenic/docs` with no product chosen.
 *
 * It carries no model: the component asks the plugin which product to start
 * from and then replaces the address with that product's canonical path, so
 * this route is only ever the first paint of a shared bookmark.
 */
export default class IngenicDocsIndexRoute extends DiscourseRoute {}
