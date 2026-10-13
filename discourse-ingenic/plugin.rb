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
require_relative "lib/discourse_ingenic/guardian_extensions"
require_relative "lib/discourse_ingenic/management_constraint"
require_relative "lib/ingenic/permission_resolver"

add_admin_route "admin.ingenic.documentation.title", "discourse-ingenic", use_new_show_route: true
register_svg_icon "book"

after_initialize do
  reloadable_patch do
    Guardian.prepend DiscourseIngenic::GuardianExtensions
  end

  # Navigation and homepage layout are admin-editable, so they are shipped to
  # the client through the site serializer rather than baked into the theme.
  add_to_serializer(:site, :ingenic_nav_items, include_condition: -> { SiteSetting.ingenic_enabled }) do
    DiscourseIngenic::ConfigParser.nav_items
  end

  add_to_serializer(:site, :ingenic_homepage_blocks, include_condition: -> { SiteSetting.ingenic_enabled }) do
    DiscourseIngenic::ConfigParser.homepage_blocks
  end

  add_to_serializer(:current_user, :can_manage_ingenic_content) do
    scope.can_manage_ingenic_content?
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
    scope "/admin/plugins/discourse-ingenic", constraints: DiscourseIngenic::ManagementConstraint.new do
      get "/documentation" => "admin/ingenic#documentation", format: false
      get "/documentation/products/:id" => "admin/ingenic#product", format: false
      post "/documentation/products" => "admin/ingenic#create_product", format: false
      put "/documentation/products/:id" => "admin/ingenic#update_product", format: false
      delete "/documentation/products/:id" => "admin/ingenic#destroy_product", format: false
      post "/documentation/versions" => "admin/ingenic#create_version", format: false
      put "/documentation/versions/:id" => "admin/ingenic#update_version", format: false
      delete "/documentation/versions/:id" => "admin/ingenic#destroy_version", format: false
      post "/documentation/pages" => "admin/ingenic#create_page", format: false
      put "/documentation/pages/:id" => "admin/ingenic#update_page", format: false
      delete "/documentation/pages/:id" => "admin/ingenic#destroy_page", format: false
      get "/boards" => "admin/ingenic#board_list", format: false
      get "/boards/:id" => "admin/ingenic#board", format: false
      post "/boards" => "admin/ingenic#create_board", format: false
      put "/boards/:id" => "admin/ingenic#update_board", format: false
      delete "/boards/:id" => "admin/ingenic#destroy_board", format: false
      get "/permissions" => "admin/ingenic#permissions", format: false
      post "/permissions" => "admin/ingenic#create_permission", format: false
      delete "/permissions/:id" => "admin/ingenic#destroy_permission", format: false
    end

    get "/ingenic/docs", to: "ingenic_docs#show", as: :ingenic_documentation_root
    get "/ingenic/docs/*path", to: "ingenic_docs#show", as: :ingenic_documentation
    get "/ingenic/downloads", to: "ingenic_downloads#index", as: :ingenic_downloads
    get "/ingenic/boards", to: "ingenic_boards#index", as: :ingenic_boards
  end
end
