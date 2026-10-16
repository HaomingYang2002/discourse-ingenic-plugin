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

  desc "Check the settings this plugin and its theme need, and say what is missing"
  task doctor: :environment do
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
        SiteSetting.set_locale_from_cookie,
        "a signed-out reader's choice goes into a cookie the server will not read back",
      ],
      [
        "default_locale",
        SiteSetting.default_locale == "en",
        "a first-time visitor lands in #{SiteSetting.default_locale.inspect} rather than English",
      ],
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
