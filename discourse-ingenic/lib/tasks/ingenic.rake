# frozen_string_literal: true

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

  desc "Name the site Ingenic, use the native latest home page, and drop Discourse's badge"
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

    if SiteSetting.enable_powered_by_discourse
      changes << "enable_powered_by_discourse: true → false"
      SiteSetting.enable_powered_by_discourse = false
    end

    # Meta's front page is Discourse's own latest list, and this forum is meant
    # to read like it: the topic table with its category, replies, views and
    # activity columns, not a page of cards. `ingenic-home` stays available as
    # a choice for a deployment that wants the announcement blocks, but it is
    # not what a fresh install lands on.
    if SiteSetting.default_homepage != "latest"
      changes << "default_homepage: #{SiteSetting.default_homepage.inspect} → \"latest\""
      SiteSetting.default_homepage = "latest"
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
        "enable_powered_by_discourse",
        !SiteSetting.enable_powered_by_discourse,
        "the page ends in Discourse's own badge — rake ingenic:setup switches it off",
      ],
      [
        "default_homepage",
        SiteSetting.default_homepage == "latest",
        "the front page is #{SiteSetting.default_homepage.inspect} rather than the topic list meta.discourse.org shows — rake ingenic:setup switches it",
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
