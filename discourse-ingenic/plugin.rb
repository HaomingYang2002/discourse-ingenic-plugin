# frozen_string_literal: true

# name: discourse-ingenic
# about: Ingenic community extension. Chip-scoped documentation with version selection, download center, and development board links.
# version: 0.1.0
# authors: Ingenic
# url: https://forum.ingenic.com

enabled_site_setting :ingenic_enabled

# Only the management screens. The public pages are drawn entirely by the
# companion theme's components, so their styles live with those components and
# there is no second copy here to fight over load order.
register_asset "stylesheets/common/ingenic-admin.scss"

module ::DiscourseIngenic
  PLUGIN_NAME = "discourse-ingenic"
end

require_relative "lib/discourse_ingenic/config_parser"
require_relative "lib/discourse_ingenic/app_shell"
require_relative "lib/discourse_ingenic/guardian_extensions"
require_relative "lib/discourse_ingenic/management_constraint"
require_relative "lib/ingenic/permission_resolver"
require_relative "lib/ingenic/resolved_page"
require_relative "lib/ingenic/documentation_resolver"
require_relative "lib/ingenic/developer_form"
require_relative "lib/ingenic/download_access"
require_relative "lib/ingenic/download_storage"

# A plugin's `app/` tree is not autoloaded. Discourse either namespaces it
# behind a Rails::Engine or expects the plugin to require each file, and this
# one uses flat top-level constants, so every file has to be named here. A
# missing line is not a subtle bug: the constant is simply undefined the first
# time a route or a job reaches for it. `spec/plugin_requires_spec.rb` fails if
# a file under app/ stops being listed.
require_relative "app/models/ingenic_doc_product"
require_relative "app/models/ingenic_doc_version"
require_relative "app/models/ingenic_doc_page"
require_relative "app/models/ingenic_download_category"
require_relative "app/models/ingenic_download"
require_relative "app/models/ingenic_download_request"
require_relative "app/models/ingenic_download_grant"
require_relative "app/models/ingenic_download_log"
require_relative "app/models/ingenic_developer_profile"
require_relative "app/models/ingenic_board"
require_relative "app/models/ingenic_permission"
require_relative "app/models/ingenic_promotion"
require_relative "app/models/ingenic_social_link"
require_relative "app/models/ingenic_footer_column"
require_relative "app/models/ingenic_footer_link"

require_relative "app/serializers/ingenic_product_serializer"
require_relative "app/serializers/ingenic_version_serializer"
require_relative "app/serializers/ingenic_page_serializer"
require_relative "app/serializers/ingenic_page_list_serializer"
require_relative "app/serializers/ingenic_board_serializer"

require_relative "app/mailers/ingenic_download_mailer"
require_relative "app/jobs/regular/ingenic_download_request_email"
require_relative "app/jobs/regular/ingenic_download_decision_email"

require_relative "app/controllers/admin/ingenic/base_controller"
require_relative "app/controllers/admin/ingenic_controller"
require_relative "app/controllers/ingenic_docs_controller"
require_relative "app/controllers/ingenic_downloads_controller"
require_relative "app/controllers/ingenic_boards_controller"

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
      get "/documentation/versions/:id/tree" => "admin/ingenic#version_tree", format: false
      post "/documentation/versions/:version_id/pages/:slug/override" => "admin/ingenic#override_page", format: false
      delete "/documentation/versions/:version_id/pages/:slug" => "admin/ingenic#revert_page", format: false
      post "/documentation/pages" => "admin/ingenic#create_page", format: false
      put "/documentation/pages/:id" => "admin/ingenic#update_page", format: false
      delete "/documentation/pages/:id" => "admin/ingenic#destroy_page", format: false
      get "/boards" => "admin/ingenic#board_list", format: false
      post "/boards" => "admin/ingenic#create_board", format: false
      put "/boards/:id" => "admin/ingenic#update_board", format: false
      delete "/boards/:id" => "admin/ingenic#destroy_board", format: false
      get "/permissions" => "admin/ingenic#permissions", format: false
      post "/permissions" => "admin/ingenic#create_permission", format: false
      delete "/permissions/:id" => "admin/ingenic#destroy_permission", format: false

      get "/downloads" => "admin/ingenic#download_list", format: false
      post "/downloads" => "admin/ingenic#create_download", format: false
      put "/downloads/:id" => "admin/ingenic#update_download", format: false
      delete "/downloads/:id" => "admin/ingenic#destroy_download", format: false
      get "/download-requests" => "admin/ingenic#download_requests", format: false
      put "/download-requests/:id/approve" => "admin/ingenic#approve_request", format: false
      put "/download-requests/:id/reject" => "admin/ingenic#reject_request", format: false
      get "/download-grants" => "admin/ingenic#download_grants", format: false
      delete "/download-grants/:id" => "admin/ingenic#revoke_grant", format: false
    end

    get "/ingenic/docs", to: "ingenic_docs#show", as: :ingenic_documentation_root
    get "/ingenic/docs/*path", to: "ingenic_docs#show", as: :ingenic_documentation

    # A sibling of the documentation glob rather than a path inside it: a route
    # like /ingenic/docs/search would be swallowed by the glob above, and
    # reordering to avoid that would make a chip called "search" unusable.
    get "/ingenic/docs-search", to: "ingenic_docs#search", as: :ingenic_documentation_search
    get "/ingenic/downloads", to: "ingenic_downloads#index", as: :ingenic_downloads

    # The developer information is a sibling of the listing rather than a path
    # under a resource: it belongs to the account, and one copy of it serves
    # every gated resource.
    post "/ingenic/downloads/profile", to: "ingenic_downloads#save_profile", as: :ingenic_download_profile
    post "/ingenic/downloads/:id/request", to: "ingenic_downloads#request_access", as: :ingenic_download_request
    get "/ingenic/downloads/:id/file", to: "ingenic_downloads#deliver", as: :ingenic_download_file

    get "/ingenic/boards", to: "ingenic_boards#index", as: :ingenic_boards
  end
end
