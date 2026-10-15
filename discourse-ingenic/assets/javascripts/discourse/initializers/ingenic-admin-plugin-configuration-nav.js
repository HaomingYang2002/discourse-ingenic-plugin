import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-ingenic";

/**
 * The Ingenic entries in the plugin's own admin navigation.
 *
 * Two kinds of account reach this page. An administrator reaches all of it. A
 * content manager — someone granted a product or a board — reaches the two
 * screens their grant actually covers, and only those are offered to them:
 * everything else here is decided on the server by `authorize_admin_only!`,
 * and a link to a page that answers 404 is worse than no link.
 *
 * The split is not arbitrary. Permissions decides who else may edit content,
 * the download queue decides who may have a file, the points screen names
 * accounts and moves their standing, and the site screen is not filed under any
 * product or board — so there is no scope an administrator could grant over it
 * even if they wanted to.
 */
export default {
  name: "ingenic-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.can_manage_ingenic_content) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "book");

      const entries = [
        {
          label: "admin.ingenic.documentation.title",
          route: "adminPlugins.show.documentation",
          currentWhen: "adminPlugins.show.documentation",
        },
        {
          label: "admin.ingenic.boards.title",
          route: "adminPlugins.show.boards",
          currentWhen: "adminPlugins.show.boards",
        },
      ];

      if (currentUser.admin) {
        entries.push(
          {
            label: "admin.ingenic.permissions.title",
            route: "adminPlugins.show.permissions",
            currentWhen: "adminPlugins.show.permissions",
          },
          {
            label: "admin.ingenic.downloads.title",
            route: "adminPlugins.show.downloads",
            currentWhen: "adminPlugins.show.downloads",
          },
          {
            label: "admin.ingenic.points.title",
            route: "adminPlugins.show.points",
            currentWhen: "adminPlugins.show.points",
          },
          {
            label: "admin.ingenic.site.title",
            route: "adminPlugins.show.site",
            currentWhen: "adminPlugins.show.site",
          },
        );
      }

      api.addAdminPluginConfigurationNav(PLUGIN_ID, entries);
    });
  },
};
