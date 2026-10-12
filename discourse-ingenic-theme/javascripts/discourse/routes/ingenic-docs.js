import DiscourseRoute from "discourse/routes/discourse";

/**
 * Documentation route.
 *
 * The model is the raw path below `/ingenic/docs`, which makes the URL the
 * single source of truth for which page is displayed: the version picker and
 * the page tree only ever transition, and the component refetches when the
 * path changes. That keeps back/forward and shared links working without any
 * extra state to reconcile.
 */
export default class IngenicDocsRoute extends DiscourseRoute {
  model(params) {
    return params.path;
  }
}
