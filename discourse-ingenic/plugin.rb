# frozen_string_literal: true

# name: discourse-ingenic
# about: Ingenic community extension. Chip-scoped documentation with version selection, download center, and development board links.
# version: 0.1.0
# authors: Ingenic
# url: https://forum.ingenic.com

enabled_site_setting :ingenic_enabled

register_asset "stylesheets/common/ingenic.scss"

module ::DiscourseIngenic
  PLUGIN_NAME = "discourse-ingenic"
end

require_relative "lib/discourse_ingenic/config_parser"
require_relative "lib/discourse_ingenic/app_shell"

after_initialize do
  # Navigation and homepage layout are admin-editable, so they are shipped to
  # the client through the site serializer rather than baked into the theme.
  add_to_serializer(:site, :ingenic_nav_items, include_condition: -> { SiteSetting.ingenic_enabled }) do
    DiscourseIngenic::ConfigParser.nav_items
  end

  add_to_serializer(:site, :ingenic_homepage_blocks, include_condition: -> { SiteSetting.ingenic_enabled }) do
    DiscourseIngenic::ConfigParser.homepage_blocks
  end

  # Keep the public surface under /ingenic so the plugin can coexist with
  # Discourse's own routes and be replaced without changing core URLs.
  #
  # Documentation uses one glob rather than three nested routes: the theme
  # registers a single matching client route, and the controller splits the path
  # into product / version / page. Fewer moving parts on both sides, and the same
  # URL shape as the version picker produces.
  #
  # The bare path is declared first because a Rails glob only matches when the
  # slash is present — without this line /ingenic/docs is a 404 at the routing
  # layer, before any controller sees it.
  Discourse::Application.routes.append do
    get "/ingenic/docs", to: "ingenic_docs#show", as: :ingenic_documentation_root
    get "/ingenic/docs/*path", to: "ingenic_docs#show", as: :ingenic_documentation
    get "/ingenic/downloads", to: "ingenic_downloads#index", as: :ingenic_downloads
    get "/ingenic/boards", to: "ingenic_boards#index", as: :ingenic_boards
  end
end
