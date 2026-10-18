# frozen_string_literal: true

require "digest"

# Moving this forum's configuration between machines.
#
#   rake ingenic:export_config                      # writes ./ingenic-config.yml
#   rake ingenic:export_config[/tmp/forum.yml]      # or wherever you want it
#   rake ingenic:import_config[/tmp/forum.yml]      # apply it
#   rake ingenic:import_config[/tmp/forum.yml,dry]  # ...and roll back, to see the diff
#
# Run these inside the container, from the Discourse root:
#
#   docker exec -it app bash -lc 'cd /var/www/discourse && rake ingenic:export_config'
#
# What is in the file is the plugin's settings and the content an admin typed
# into its pages. What is not in it is anything a member produced — see the
# comment at the top of lib/ingenic/config_export.rb for why, and take a
# database dump for that instead.

namespace :ingenic do
  def ingenic_report(report)
    puts "  settings: #{report["settings"].inspect}" if report["settings"]

    Ingenic::ConfigExport::SECTIONS.each do |section|
      counts = report[section]
      next if counts.nil?

      print "  #{section}: "
      if counts["created"].zero? && counts["updated"].zero?
        puts "nothing"
      else
        puts "#{counts["created"]} created, #{counts["updated"]} updated"
      end
    end

    untouched = report["untouched"] || {}
    if untouched.any?
      puts
      puts "Left alone (in the forum, not in the file — deleting is your call, not the file's):"
      untouched.each { |section, count| puts "  #{section}: #{count} row(s)" }
    end
  end

  desc "Write this forum's Ingenic configuration to a YAML file"
  task :export_config, [:path] => :environment do |_task, args|
    path = Ingenic::ConfigExport.export(args[:path])
    size = File.size(path)

    puts "Wrote #{path} (#{size} bytes)"
    puts
    puts "This file describes what the forum should contain, not who did what in it:"
    puts "no point balances, no download requests or grants, no developer profiles,"
    puts "no download logs. Take a database dump if you need those."
  end

  desc "Apply an Ingenic configuration file. Second argument 'dry' rolls it back."
  task :import_config, %i[path dry] => :environment do |_task, args|
    path = args[:path]
    if path.blank?
      abort "Usage: rake ingenic:import_config[/path/to/ingenic-config.yml]"
    end

    dry_run = args[:dry].present?

    begin
      report = Ingenic::ConfigExport.import(path, dry_run: dry_run)
    rescue ArgumentError, Ingenic::ConfigExport::ImportError => e
      abort "ingenic:import_config: #{e.message}\n\nNothing was written."
    end

    puts dry_run ? "Dry run — nothing was written. It would have been:" : "Imported #{path}:"
    ingenic_report(report)

    if dry_run
      puts
      puts "Nothing changed. Run it again without the second argument to keep the result."
    end
  end

  desc "Name the site Ingenic, fill an empty logo with a stand-in, choose the Ingenic home page, seed the header buttons and footer links, and drop Discourse's badge"
  task setup: :environment do
    # Three settings that decide what a visitor sees before they read anything:
    # who the forum says it belongs to, whether the front page is the forum's
    # own topic list, and whether the page ends in an advert for the software.
    # All three default to Discourse's answers, none of them produces an error,
    # and all three are the same on every Ingenic install — so they are applied
    # here rather than typed in by hand. Every change is printed, and running
    # the task again changes nothing.
    changes = []

    if SiteSetting.title != "Ingenic"
      changes << "title: #{SiteSetting.title.inspect} → \"Ingenic\""
      SiteSetting.title = "Ingenic"
    end

    # The header draws an uploaded logo ahead of the site title, and a stock
    # Discourse ships with its own wordmark already uploaded. Renaming the site
    # therefore changes the page title and nothing a visitor sees in the corner;
    # the logo has to be an upload too. The wordmark is shipped with the plugin
    # and found by digest so a second run reuses the first upload.
    # The file shipped with the plugin is a stand-in, not this site's own
    # wordmark: an administrator replaces it in Admin → Site settings →
    # Branding, and that upload is what visitors should keep seeing. So the
    # logo is filled in only where it is empty — a value someone chose is not
    # this task's to overwrite, and rerunning it after a deployment must not
    # put the placeholder back.
    logo_file = Rails.root.join("plugins/discourse-ingenic/assets/images/ingenic-logo.png")
    if logo_file.file?
      digest = Digest::SHA1.file(logo_file).hexdigest
      logo =
        Upload.find_by(sha1: digest) ||
          UploadCreator.new(
            File.open(logo_file),
            "ingenic-logo.png",
            type: "site_logo",
            origin: "site_setting",
          ).create_for(Discourse.system_user.id)

      if logo.persisted?
        { logo: "logo", logo_small: "logo_small", mobile_logo: "mobile_logo" }.each do |setting, label|
          current = SiteSetting.public_send(setting)
          next if current.present?
          changes << "#{label}: none → ingenic-logo.png (a stand-in — replace it under Branding)"
          SiteSetting.public_send("#{setting}=", logo)
        end
      else
        puts "Could not install the logo: #{logo.errors.full_messages.to_sentence}"
      end
    end

    if SiteSetting.enable_powered_by_discourse
      changes << "enable_powered_by_discourse: true → false"
      SiteSetting.enable_powered_by_discourse = false
    end

    # The front page is the Ingenic one: a welcome and a search box, the
    # popular sections as cards, the latest discussions, and the rail of
    # activity and hot topics. Meta's shape, the forum's own content. The
    # native latest list is still one click away in the sidebar and at
    # /latest; it is not what `/` is.
    if SiteSetting.default_homepage != "ingenic-home"
      changes << "default_homepage: #{SiteSetting.default_homepage.inspect} → \"ingenic-home\""
      SiteSetting.default_homepage = "ingenic-home"
    end

    # Tags are the forum's vocabulary, not a free-for-all: the three state tags
    # exist in a staff-only group, only administrators create new tags, and any
    # logged-in account may use one that exists. Solved is switched on so the
    # 已解决 tag has something to follow. The method is idempotent and skips the
    # parts that need a plugin this forum does not have.
    Ingenic::TagPolicy.apply!

    layout = Ingenic::ForumCategories.ensure_layout!
    changes << "Open Source section: #{layout.join(", ")}" if layout.any?

    # Both footer lists are content, and the theme hides the footer until there
    # is some: a fresh install would reach the bottom of the page with nothing
    # there. Two destinations every Ingenic deployment has, plus the sections a
    # reader actually needs from the bottom of a page. Seeded only when the
    # lists are empty — a forum that has chosen its own partners is not
    # overridden, and both are edited in Admin → Plugins → Ingenic → Site
    # content.
    if IngenicSocialLink.count.zero?
      [
        { label: "Ingenic", href: "https://www.ingenic.com" },
        { label: "Ingenic Forum", href: "https://forum.ingenic.com" },
      ].each_with_index do |attrs, index|
        IngenicSocialLink.create!(
          kind: IngenicSocialLink::LINK,
          position: index,
          published: true,
          **attrs,
        )
        changes << "partner platform: #{attrs[:label]} → #{attrs[:href]}"
      end
    end

    if IngenicFooterColumn.count.zero?
      {
        "Developers" => [
          ["Online documentation", "/ingenic/docs"],
          ["SDK & firmware", "/ingenic/downloads"],
          ["Development boards", "/ingenic/boards"],
        ],
        "Community" => [
          ["Latest topics", "/latest"],
          ["All categories", "/categories"],
          ["Bounties", "/ingenic/bounties"],
        ],
      }.each_with_index do |(title, links), index|
        column =
          IngenicFooterColumn.create!(title: title, position: index, published: true)
        links.each_with_index do |(label, href), link_index|
          IngenicFooterLink.create!(
            column: column,
            label: label,
            href: href,
            external: false,
            position: link_index,
            published: true,
          )
        end
        changes << "footer column: #{title} (#{links.size} links)"
      end
    end

    # One welcome slot, because the promotions block draws nothing until there
    # is one and a section that is invisible on a fresh install reads as a
    # feature that was never finished. It points at pages this forum really
    # has, and the same admin screen replaces or removes it.
    if IngenicPromotion.count.zero?
      IngenicPromotion.create!(
        corner_label: "Docs",
        title: "The T Series documentation is online",
        description: "Versioned reference for each chip, beside the SDK and firmware " \
                       "downloads and the boards they run on.",
        button_label: "Browse the documentation",
        button_href: "/ingenic/docs",
        button_external: false,
        locale: "en",
        position: 0,
        published: true,
      )
      changes << "promotion: a welcome slot pointing at /ingenic/docs"
    end

    # Two header buttons, because the empty middle of the header is otherwise
    # the first thing an editor has to go and find out how to fill. They are
    # stand-ins: the official site and a code host, one with its name shown and
    # one as its icon alone, so both shapes of the button are visible. Seeded
    # only when there are none, and every field is edited — or the row removed —
    # in Admin → Plugins → Ingenic → Site content → Header buttons.
    if IngenicHeaderLink.count.zero?
      [
        {
          label: "Ingenic Semiconductor",
          href: "https://www.ingenic.com",
          icon: "globe",
          show_label: true,
          external: true,
        },
        {
          label: "GitHub",
          href: "https://github.com",
          icon: "fab-github",
          show_label: false,
          external: true,
        },
      ].each_with_index do |attrs, index|
        IngenicHeaderLink.create!(position: index, published: true, **attrs)
        changes << "header button: #{attrs[:label]} → #{attrs[:href]}"
      end
    end

    if changes.empty?
      puts "Nothing to change: the site already introduces itself as Ingenic."
    else
      changes.each { |change| puts "  #{change}" }
      puts
      puts "#{changes.size} changed. Reload a page to see them; the server picks up site"
      puts "settings without a restart."
    end
  end

  desc "Check the settings this plugin and its theme need, and say what is missing"
  task doctor: :environment do
    # Whether a signed-out reader's choice of language survives the round trip.
    # Two routes lead there and either will do: `set_locale_from_cookie` is the
    # plain one, and the other is content localization, whose own language
    # switcher writes the same cookie and reads it back. Asking only about the
    # first reported a failure on a site that works.
    #
    # `Discourse.locale_from_cookie` also asks whether the cookie names a locale
    # in `content_localization_locales`, which is not repeated here: that list is
    # the supported ones with the default appended, so the default is in it by
    # construction, and the switcher only ever offers a locale from the list.
    locale_from_cookie =
      SiteSetting.set_locale_from_cookie || ContentLocalization.language_switcher_enabled?

    # Each of these is a setting whose wrong value produces no error anywhere: a
    # switcher that is not there, an upload directory nothing can be written to,
    # a first-time visitor landing in a language nobody chose. That silence is
    # what makes them worth a command rather than a paragraph in a note.
    checks = [
      ["ingenic_enabled", SiteSetting.ingenic_enabled, "the plugin is switched off"],
      [
        "allow_user_locale",
        SiteSetting.allow_user_locale,
        "readers cannot choose a language, and the header's language switcher stays hidden",
      ],
      [
        "set_locale_from_cookie",
        locale_from_cookie,
        "a signed-out reader's choice goes into a cookie the server will not read back — " \
          "set set_locale_from_cookie, or switch on content_localization_enabled and show " \
          "its language switcher",
      ],
      [
        "default_locale",
        SiteSetting.default_locale == "en",
        "a first-time visitor lands in #{SiteSetting.default_locale.inspect} rather than English",
      ],
      [
        "title",
        SiteSetting.title == "Ingenic",
        "the header introduces the forum as #{SiteSetting.title.inspect} — rake ingenic:setup names it Ingenic",
      ],
      [
        "logo",
        SiteSetting.logo.present? && !SiteSetting.logo.url.to_s.include?("discourse-logo-sketch"),
        "the header still wears Discourse's own logo, which overrides the site title — upload your own under Branding; rake ingenic:setup fills an empty logo with a stand-in",
      ],
      [
        "enable_powered_by_discourse",
        !SiteSetting.enable_powered_by_discourse,
        "the page ends in Discourse's own badge — rake ingenic:setup switches it off",
      ],
      [
        "default_homepage",
        SiteSetting.default_homepage == "ingenic-home",
        "the front page is #{SiteSetting.default_homepage.inspect} rather than the Ingenic home page — rake ingenic:setup switches it",
      ],
    ]

    # A category the navigation points at and the forum does not have is a link
    # to a 404 on a page that otherwise looks finished, which is the kind of
    # thing that gets noticed by a visitor rather than by whoever built it.
    absent_categories = Ingenic::ForumCategories.missing
    checks << [
      "forum categories",
      absent_categories.empty?,
      "the navigation links to #{absent_categories.join(", ")}, which the forum does not have — rake ingenic:seed_categories creates them",
    ]

    # Only worth asking when a path is configured: with none, nothing is
    # uploaded to this server and every resource is an external URL.
    if SiteSetting.ingenic_download_storage_path.present?
      checks << [
        "ingenic_download_storage_path",
        Ingenic::DownloadStorage.writable?,
        "#{SiteSetting.ingenic_download_storage_path} cannot be written to, so uploads will be refused",
      ]
    else
      puts "note  ingenic_download_storage_path is empty: no files are stored on this server"
    end

    problems =
      checks.reject { |_name, ok, _why| ok }.map { |name, _ok, why| "#{name}: #{why}" }

    problems.each { |problem| puts "FAIL  #{problem}" }

    puts
    if problems.empty?
      puts "All good."
    else
      puts "#{problems.size} to fix. Site settings live under Admin → Settings; the language"
      puts "switcher's own language list is a theme setting on the theme's settings page."
      puts "Either way, rake ingenic:setup applies the three site defaults this task names."
    end
  end

  desc "Create the forum sections the navigation links to; 'permissions' re-applies their permissions"
  task :seed_categories, [:permissions] => :environment do |_task, args|
    # Three of the navigation's entries name a category, and Discourse creates
    # none of its own, so on a fresh install those three are links to a page that
    # does not exist while everything around them renders. This is what makes
    # them real — and what makes Official Open Source administrators-only rather
    # than another place for anyone to post.
    report = Ingenic::ForumCategories.seed!(permissions: args[:permissions].present?)

    width = report.map { |row| row[:slug].length }.max || 0
    report.each do |row|
      line = "  #{row[:slug].ljust(width)}  #{row[:action]}"
      line += "  — #{row[:detail]}" if row[:detail]
      puts line
    end

    layout = Ingenic::ForumCategories.ensure_layout!
    unless layout.empty?
      puts
      puts "  open-source layout: #{layout.join(", ")}"
      puts "  (sub-forum cards on top, both sub-forums' topics below, About unpinned)"
    end

    created = report.count { |row| row[:action] == :created }
    puts
    if created.zero?
      puts "Nothing to create. Categories already in the forum are left as the forum has them:"
      puts "renaming, re-colouring and reordering them here is not this task's business."
    else
      puts "#{created} created. They are ordinary categories from here on — Admin → Categories"
      puts "renames, re-colours, re-parents and re-permissions them, and this task will not"
      puts "undo any of that."
    end

    unless args[:permissions].present?
      puts
      puts "To set the permissions in the list again (anyone may post in Third-Party Open"
      puts "Source, only administrators in Official Open Source, staff in Announcements):"
      puts "  rake ingenic:seed_categories[permissions]"
    end
  end

  desc "Show what an Ingenic configuration file holds, without touching the database"
  task :show_config, [:path] => :environment do |_task, args|
    path = args[:path] || Ingenic::ConfigExport.default_path
    data = Ingenic::ConfigExport.load_file(path)

    puts "#{path}"
    puts "  version: #{data["version"]}   exported at: #{data["exported_at"]}"

    settings = data["site_settings"] || {}
    puts "  site settings: #{settings.size}"
    settings.each { |key, value| puts "    #{key} = #{value.inspect}" }

    puts "  content:"
    Ingenic::ConfigExport::SECTIONS.each do |section|
      rows = data.dig("content", section) || []
      puts "    #{section}: #{rows.size}"
    end
  end
end
