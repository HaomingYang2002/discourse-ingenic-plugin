# frozen_string_literal: true

require "rails_helper"

# The three ways a plugin's migrations can be wrong in a way nothing else
# notices: they are the only files in the plugin that are never loaded by the
# spec suite, so a mistake in one of them is discovered by an install that
# cannot complete rather than by a test run.
#
# All three happened here, one install attempt apart:
#
#   * `20261018…` is a day ahead of the clock, and ActiveRecord refuses the
#     whole set — not just that file — with `InvalidMigrationTimestampError`.
#     `rake db:migrate`, `./launcher rebuild app` and every rake task that loads
#     the environment stop before they start.
#   * `IngenicBountySerializer` naming a constant one require too early is the
#     same kind of failure and has its own test in `spec/plugin_requires_spec.rb`.
#   * `add_ingenic_download_categories` dropped a column inline. Discourse
#     patches migrations so that a drop outside `db/post_migrate` raises, because
#     a running application server may still be reading the column — so the
#     migration aborted there and nothing after it ran.
RSpec.describe "migrations" do
  ROOT = File.expand_path("../..", __dir__)
  REGULAR = File.join(ROOT, "db/migrate")
  POST = File.join(ROOT, "db/post_migrate")

  # What Discourse's safe-migrate patch refuses outside a post-deploy migration.
  # It matches the SQL rather than the method, so this is every schema method
  # that produces a `DROP TABLE`, a `DROP CONSTRAINT` or a `RENAME`: dropping a
  # column, a foreign key, a check constraint or a whole table.
  DESTRUCTIVE =
    /\b(?:remove_column|remove_columns|rename_column|remove_foreign_key|
          remove_check_constraint|remove_unique_constraint|remove_reference|
          drop_table)\b/x

  def files_in(dir)
    Dir.glob(File.join(dir, "*.rb")).sort
  end

  def all_files
    files_in(REGULAR) + files_in(POST)
  end

  it "ships migrations" do
    expect(files_in(REGULAR)).not_to be_empty
  end

  it "names every migration for a moment ActiveRecord will accept" do
    # The bound as ActiveRecord computes it, so this fails for the reason the
    # framework would rather than for a rule invented here. It allows a day of
    # slack ahead of now, so a file written today in a timezone ahead of UTC is
    # legitimate and must not be failed.
    limit = (Time.now.utc + 1.day).strftime("%Y%m%d%H%M%S")

    wrong =
      all_files.filter_map do |path|
        version = File.basename(path)[/\A\d+/]

        if version.nil? || version.length != 14
          "#{File.basename(path)}: #{version || "no"} timestamp, not YYYYMMDDHHMMSS"
        elsif version >= limit
          "#{File.basename(path)}: #{version} is ahead of #{limit}"
        end
      end

    expect(wrong).to be_empty
  end

  it "gives each migration its own timestamp, across both directories" do
    # Post-deploy migrations are read from a second path but share one version
    # namespace with the regular ones: the same number in both is a duplicate.
    duplicates =
      all_files
        .map { |path| File.basename(path)[/\A\d+/] }
        .tally
        .select { |_, count| count > 1 }
        .keys

    expect(duplicates).to be_empty
  end

  it "names the class inside the file the way the file is named" do
    # `MigrationProxy` constantizes the file's name, so a mismatch is a
    # `NameError` at the same moment the timestamp would have failed.
    mismatched =
      all_files.filter_map do |path|
        expected = File.basename(path).sub(/\A\d+_/, "").delete_suffix(".rb").camelize
        found = File.read(path)[/^\s*class\s+([A-Z][A-Za-z0-9_]*)\s*</, 1]

        if found != expected
          "#{File.basename(path)}: names #{found || "no class"}, not #{expected}"
        end
      end

    expect(mismatched).to be_empty
  end

  it "drops or renames a column only from a post-deploy migration" do
    # `down` is exempt, and is the only method that is: rolling back is already
    # the administrator saying the new code is not running.
    offenders =
      files_in(REGULAR).filter_map do |path|
        source = File.read(path)

        # The body of each `def`, so that `down` can be told from the rest.
        bodies = source.scan(/^\s*def\s+(\w+)(.*?)^\s*end\b/m)
        named = bodies.select { |name, _| name != "down" }.map { |_, body| body }
        # Anything outside a method is the class body, which runs on the way up.
        loose = source.gsub(/^\s*def\s+\w+.*?^\s*end\b/m, "")

        hit = (named + [loose]).find { |body| body.match?(DESTRUCTIVE) }
        next if hit.nil?

        "#{File.basename(path)}: #{hit[DESTRUCTIVE]} outside `down` — " \
          "Discourse refuses it in a regular migration"
      end

    expect(offenders).to be_empty
  end
end
