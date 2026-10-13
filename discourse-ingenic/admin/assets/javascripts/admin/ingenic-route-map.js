export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("documentation", { path: "documentation" }, function () {
      this.route("show", { path: "/:id" });
    });
    this.route("boards", { path: "boards" }, function () {
      this.route("show", { path: "/:id" });
    });
    this.route("permissions", { path: "permissions" });
  },
};
