import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-ingenic";

export default {
  name: "ingenic-admin-plugin-configuration-nav",

  initialize(container) {
    if (!container.lookup("service:current-user")?.can_manage_ingenic_content) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "book");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "admin.ingenic.documentation.title",
          route: "adminPlugins.show.documentation",
        },
        {
          label: "admin.ingenic.boards.title",
          route: "adminPlugins.show.boards",
        },
        {
          label: "admin.ingenic.permissions.title",
          route: "adminPlugins.show.permissions",
        },
      ]);
    });
  },
};
