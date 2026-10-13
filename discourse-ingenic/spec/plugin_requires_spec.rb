# frozen_string_literal: true

require "rails_helper"

# A plugin's `app/` tree is not autoloaded, so every Ruby file the plugin ships
# has to be named by a `require_relative` in plugin.rb.
#
# Nothing else catches a missing line. The file parses, the suite boots, the
# routes load — the constant is only discovered to be undefined when a request
# or a job reaches for it. That makes it exactly the kind of mistake a passing
# test suite would hide, which is why it gets its own test.
RSpec.describe "plugin requires" do
  it "names every ruby file it ships" do
    root = File.expand_path("..", __dir__)
    source = File.read(File.join(root, "plugin.rb"))
    required = source.scan(/require_relative\s+"([^"]+)"/).flatten

    shipped =
      %w[app lib]
        .flat_map { |dir| Dir.glob(File.join(root, dir, "**", "*.rb")) }
        .map { |path| path.delete_prefix("#{root}/").delete_suffix(".rb") }

    expect(shipped - required).to be_empty
  end

  it "does not require files that are not there" do
    root = File.expand_path("..", __dir__)
    source = File.read(File.join(root, "plugin.rb"))
    required = source.scan(/require_relative\s+"([^"]+)"/).flatten

    missing = required.reject { |path| File.exist?(File.join(root, "#{path}.rb")) }

    expect(missing).to be_empty
  end
end
