export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("documentation", { path: "documentation" });
    this.route("boards", { path: "boards" });
    this.route("permissions", { path: "permissions" });
    this.route("downloads", { path: "downloads" });
    this.route("points", { path: "points" });
    this.route("site", { path: "site" });
  },
};
