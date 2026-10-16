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
require_relative "lib/ingenic/official_flair"
require_relative "lib/ingenic/points"
require_relative "lib/ingenic/point_events"
require_relative "lib/ingenic/bounties"
require_relative "lib/ingenic/config_export"

# A plugin's `app/` tree is not autoloaded. Discourse either namespaces it
# behind a Rails::Engine or expects the plugin to require each file, and this
# one uses flat top-level constants, so every file has to be named here. A
# missing line is not a subtle bug: the constant is simply undefined the first
# time a route or a job reaches for it. `spec/plugin_requires_spec.rb` fails if
# a file under app/ stops being listed.
after_initialize do
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
require_relative "app/models/ingenic_point_rule"
require_relative "app/models/ingenic_point_entry"
require_relative "app/models/ingenic_point_balance"
require_relative "app/models/ingenic_bounty"

require_relative "app/serializers/ingenic_version_serializer"
require_relative "app/serializers/ingenic_product_serializer"
require_relative "app/serializers/ingenic_page_serializer"
require_relative "app/serializers/ingenic_page_list_serializer"
require_relative "app/serializers/ingenic_board_serializer"
require_relative "app/serializers/ingenic_bounty_serializer"
require_relative "app/serializers/ingenic_bounty_topic_serializer"

require_relative "app/mailers/ingenic_download_mailer"
require_relative "app/jobs/regular/ingenic_download_request_email"
require_relative "app/jobs/regular/ingenic_download_decision_email"
require_relative "app/jobs/regular/ingenic_official_flair_sync"
require_relative "app/jobs/scheduled/ingenic_bounty_expiry"

require_relative "app/controllers/admin/ingenic/base_controller"
require_relative "app/controllers/admin/ingenic_controller"
require_relative "app/controllers/ingenic_docs_controller"
require_relative "app/controllers/ingenic_downloads_controller"
require_relative "app/controllers/ingenic_boards_controller"
require_relative "app/controllers/ingenic_site_controller"
require_relative "app/controllers/ingenic_points_controller"
require_relative "app/controllers/ingenic_home_controller"
require_relative "app/controllers/ingenic_bounties_controller"
end

add_admin_route "admin.ingenic.documentation.title", "discourse-ingenic", use_new_show_route: true

# The icons the theme ships with when `ingenic_nav_items` is left empty, plus
# the ones its own pages draw.
#
# Icons an administrator names in that setting are collected for the sprite
# automatically — it is an object list with an icon field, and the sprite is
# built from the settings as well as from code. A list that lives in the
# theme's source is not, so the ones the theme falls back to are named here or
# they render as nothing. `book`, `download`, `star` and `circle` are already
# in Discourse's own subset; `microchip` is not, and the Development Boards
# entry is the one that would go missing.
register_svg_icon "book"
register_svg_icon "download"
register_svg_icon "microchip"
register_svg_icon "star"
register_svg_icon "circle"

after_initialize do
  reloadable_patch do
    Guardian.prepend DiscourseIngenic::GuardianExtensions
  end

  # The official identity badge.
  #
  # Discourse already draws a group's flair beside a member's username; what it
  # does not do is hand that flair out on membership, because its own route to
  # it runs through the group being the member's primary group, which decides
  # rather more than a badge. These four events are every way a member and a
  # listing can come apart: joining, leaving, the group's own flair changing,
  # and the list of official groups changing. The rules and the reasons are in
  # Ingenic::OfficialFlair; what is here is only what notices.
  #
  # Each is guarded on the extension being on. The handlers outlive the setting
  # — Rails has already loaded this file — and a forum that has switched the
  # extension off should not go on handing out badges in the background.
  on(:user_added_to_group) do |user, _group, **_opts|
    Ingenic::OfficialFlair.sync_user(user) if SiteSetting.ingenic_enabled
  end

  on(:user_removed_from_group) do |user, _group|
    Ingenic::OfficialFlair.sync_user(user) if SiteSetting.ingenic_enabled
  end

  on(:group_updated) do |group|
    Ingenic::OfficialFlair.after_group_change(group) if SiteSetting.ingenic_enabled
  end

  on(:site_setting_changed) do |name, old_value, _new_value|
    if SiteSetting.ingenic_enabled && name.to_s == "ingenic_official_groups"
      Ingenic::OfficialFlair.after_list_change(old_value)
    end
  end

  # The points ledger.
  #
  # Six events, and between them every way points are earned or taken back:
  # something is written, something is liked, an answer is accepted, and the
  # three ways any of those goes away. What counts and who earns is in
  # Ingenic::PointEvents; this is only the subscribing.
  #
  # `discourse-solved` owns the two solution events and may not be enabled. A
  # handler for an event nothing fires costs nothing, which is why these are
  # registered unconditionally rather than behind a check for a plugin this one
  # does not otherwise depend on.
  on(:post_created) { |post, _opts, _user| Ingenic::PointEvents.post_created(post) }
  on(:post_destroyed) { |post, _opts, _user| Ingenic::PointEvents.post_destroyed(post) }
  on(:like_created) { |post_action, _creator| Ingenic::PointEvents.like_created(post_action) }
  on(:like_destroyed) { |post_action, _creator| Ingenic::PointEvents.like_destroyed(post_action) }
  on(:accepted_solution) { |post| Ingenic::PointEvents.solution_accepted(post) }
  on(:unaccepted_solution) { |post| Ingenic::PointEvents.solution_unaccepted(post) }

  # Deleting a topic takes its 高分悬赏 with it, and the points behind a standing
  # one come back on the way out.
  #
  # The foreign key cascades, because a bounty is read through its topic — the
  # topic page asks what stands on it, the board reaches offers by way of the
  # topics the viewer may see, accepting an answer looks one up by the post's
  # topic — so an offer standing on nothing is not a record of anything. That is
  # only safe alongside this handler: the points behind a standing offer are
  # escrowed, off the asker's balance since the offer was opened, so a row
  # removed without being closed takes the only thing that would ever have moved
  # them back with it. The refund runs inside the deletion's own transaction, so
  # the topic, the bounty rows and the movements that close them either all
  # happen or none of them do.
  #
  # `before_destroy` rather than the `:topic_destroyed` event, because of when
  # that event fires: `PostDestroyer` destroys the topic row inside its own
  # transaction and triggers the event afterwards, by which time the row is gone
  # — and it fires for a topic that was only moved to the trash as well, which is
  # not a deletion the offer cares about.
  #
  # Asked of the database only while a topic is being destroyed, and answered by
  # one indexed lookup that finds nothing for all but a handful of topics. Two
  # ways past it, both worth knowing: a `delete_all` runs no callbacks at all,
  # and `add_model_callback` stands aside while the whole plugin is switched off
  # — in either case the cascade removes the rows without giving anything back.
  # The escrow entry stays in the ledger, so what was lost is still visible, but
  # it has stopped being recoverable. `DEPLOY.md` says so where administrators
  # are told what they may do with a topic.
  add_model_callback(Topic, :before_destroy) { Ingenic::Bounties.refund_for_topic!(self) }

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

  # The 高分悬赏 on this topic — standing or settled — so the topic page can
  # draw its banner without a second request. One lookup against the index on
  # `topic_id`, and null — rather than absent — for the overwhelming majority of
  # topics, which have no bounty and never will. The front end checks for the
  # value; the attribute is always there when bounties are switched on, so the
  # browser never has to tell "no bounty" from "the server did not say".
  #
  # Serialized here rather than returned as the row, so the page gets the shape
  # `IngenicBountiesController` sends and not whatever the table happens to hold.
  #
  # The `include_condition` asks only about bounties: whether this plugin is on
  # at all is already part of `add_to_serializer`, which leaves the attribute out
  # when it is off.
  add_to_serializer(
    :topic_view,
    :ingenic_bounty,
    include_condition: -> { SiteSetting.ingenic_bounties_enabled },
  ) do
    bounty = Ingenic::Bounties.for_topic(object.topic)
    bounty && IngenicBountySerializer.new(bounty, scope: scope, root: false).as_json
  end

  # Whether to offer the viewer the control that opens one. Answered here rather
  # than worked out in the browser, which would be a guess about permissions the
  # server has not granted yet.
  add_to_serializer(
    :topic_view,
    :can_open_ingenic_bounty,
    include_condition: -> { SiteSetting.ingenic_bounties_enabled },
  ) { scope.can_open_ingenic_bounty?(object.topic) }

  # The front page, offered to Discourse's own `default_homepage` setting.
  #
  # Discourse resolves `/` from that setting, and a plugin can put a page of its
  # own there instead of one of the built-in topic lists. That is what makes
  # this a front page rather than a panel on somebody else's: `/` is the Ingenic
  # home and nothing else, with no topic list under it and no filter bar above
  # it, while the topic lists keep the addresses they always had — /latest,
  # /top — and the sidebar keeps them one click away.
  #
  # The theme used to draw this page into the discovery route's
  # `before-topic-list` outlet instead. An outlet is a guest on another route's
  # page, which is why picking "Latest" took the home page away with it.
  #
  # `enabled` rather than nothing: with the plugin switched off the setting
  # falls back to the top menu homepage instead of offering a page that is not
  # there. Anonymous visitors get it too — a forum whose front page needs an
  # account has no front page.
  register_homepage(
    "ingenic-home",
    name: "ingenic.homepage_option",
    path: "/ingenic/home",
    route: "ingenic_home#index",
    anonymous: true,
    enabled: -> { SiteSetting.ingenic_enabled },
  )

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

      get "/download-logs" => "admin/ingenic#download_logs", format: false

      # Points. Reading is administrator-only too: the ledger names accounts,
      # and an adjustment moves a member's standing.
      get "/points" => "admin/ingenic#points", format: false
      put "/points/rules/:id" => "admin/ingenic#update_point_rule", format: false
      post "/points/adjust" => "admin/ingenic#adjust_points", format: false
      post "/points/rebuild" => "admin/ingenic#rebuild_points", format: false
      get "/point-entries" => "admin/ingenic#point_entries", format: false

      post "/download-categories" => "admin/ingenic#create_download_category", format: false
      put "/download-categories/:id" => "admin/ingenic#update_download_category", format: false
      delete "/download-categories/:id" => "admin/ingenic#destroy_download_category", format: false

      # The homepage and footer lists. One path returns all three because they
      # are drawn on one screen; the writes are separate because each list has
      # its own fields.
      get "/site" => "admin/ingenic#site", format: false

      post "/promotions" => "admin/ingenic#create_promotion", format: false
      put "/promotions/:id" => "admin/ingenic#update_promotion", format: false
      delete "/promotions/:id" => "admin/ingenic#destroy_promotion", format: false

      post "/social-links" => "admin/ingenic#create_social_link", format: false
      put "/social-links/:id" => "admin/ingenic#update_social_link", format: false
      delete "/social-links/:id" => "admin/ingenic#destroy_social_link", format: false

      post "/footer-columns" => "admin/ingenic#create_footer_column", format: false
      put "/footer-columns/:id" => "admin/ingenic#update_footer_column", format: false
      delete "/footer-columns/:id" => "admin/ingenic#destroy_footer_column", format: false

      post "/footer-links" => "admin/ingenic#create_footer_link", format: false
      put "/footer-links/:id" => "admin/ingenic#update_footer_link", format: false
      delete "/footer-links/:id" => "admin/ingenic#destroy_footer_link", format: false
    end

    # The front page at its canonical address. Discourse mounts the page chosen
    # in `default_homepage` at `/` itself; this is the same page under a path of
    # its own, which is what the client route and every link to the home page
    # use, and what makes the address survive a refresh.
    get "/ingenic/home", to: "ingenic_home#index", as: :ingenic_home

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

    # The homepage slots, the footer's partner strip and the footer's link
    # columns. One address because the theme asks for them together, and there is
    # no page here: every one of them is drawn inside a layout the theme already
    # owns.
    get "/ingenic/site", to: "ingenic_site#show", as: :ingenic_site

    # The member's own points. Read-only from the front end: points are earned
    # by contributing and spent on a download, and neither happens through this
    # address.
    get "/ingenic/points", to: "ingenic_points#show", as: :ingenic_points

    # 高分悬赏. Two writes and no third: accepting an answer — which is what pays
    # a bounty — is Discourse's own accepted answer and has no endpoint here, so
    # there is no second way for the forum to be told which answer won.
    #
    # `:id` on the withdrawal is the bounty's, not the topic's: a topic can have
    # a settled bounty and a standing one, and the withdrawal has to name which.
    get "/ingenic/bounties", to: "ingenic_bounties#show", as: :ingenic_bounties
    post "/ingenic/bounties", to: "ingenic_bounties#create", as: :ingenic_bounty_create
    post "/ingenic/bounties/:id/cancel", to: "ingenic_bounties#cancel", as: :ingenic_bounty_cancel
  end
end
