/**
 * Client routes owned by the Ingenic theme.
 *
 * Discourse's router is not extensible, so it collects route maps from any
 * module whose name ends in `route-map` and applies them after core's own map.
 * The Rails plugin registers matching server routes, which is what lets a
 * visitor open or refresh one of these URLs directly instead of only reaching
 * them through in-app clicks.
 *
 * Documentation is a single splat route: the page splits the path into
 * product / version / page itself, so adding a level later does not mean
 * touching the route map. The bare path is registered ahead of the splat so the
 * splat cannot swallow it — that URL is what a "Documentation" navigation entry
 * points at, and the component replaces it with the canonical product path once
 * the plugin has resolved which product to start from.
 */
export default function () {
  this.route("ingenic-docs-index", { path: "/ingenic/docs" });
  this.route("ingenic-docs", { path: "/ingenic/docs/*path" });
  this.route("ingenic-downloads", { path: "/ingenic/downloads" });
  this.route("ingenic-boards", { path: "/ingenic/boards" });
  this.route("ingenic-points", { path: "/ingenic/points" });
}
