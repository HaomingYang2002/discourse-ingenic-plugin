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
  # The plugin is its own repository now, so the spec tree sits directly under
  # it. Walk up to the file that marks the root rather than counting `..`, so
  # the tests do not depend on where the repository happens to be checked out.
  def root
    @root ||= begin
      dir = File.expand_path(__dir__)
      dir = File.dirname(dir) until File.exist?(File.join(dir, "plugin.rb")) || dir == "/"
      dir
    end
  end

  it "names every ruby file it ships" do
    source = File.read(File.join(root, "plugin.rb"))
    required = source.scan(/require_relative\s+"([^"]+)"/).flatten

    shipped =
      %w[app lib]
        .flat_map { |dir| Dir.glob(File.join(root, dir, "**", "*.rb")) }
        .map { |path| path.delete_prefix("#{root}/").delete_suffix(".rb") }

    expect(shipped - required).to be_empty
  end

  it "does not require files that are not there" do
    source = File.read(File.join(root, "plugin.rb"))
    required = source.scan(/require_relative\s+"([^"]+)"/).flatten

    missing = required.reject { |path| File.exist?(File.join(root, "#{path}.rb")) }

    expect(missing).to be_empty
  end

  # A require is not enough on its own: it has to come before whatever names the
  # constant *while the file is being loaded*. A `serializer:` in a `has_one`
  # line, a superclass, and an `include` at class level are all read as the class
  # body runs, so a file required after the one that names it is a `NameError`
  # during boot rather than a missing method at runtime — which is how
  # `IngenicBountySerializer` naming `IngenicBountyTopicSerializer` one line too
  # early took the whole application down before it could serve a page.
  #
  # Everything else in these files names constants from inside a method body,
  # where the lookup happens on the call rather than on the load and the order
  # does not matter. This test is deliberately limited to the class-body forms
  # for that reason.
  it "requires a file before whatever names its constants in a class body" do
    required =
      File
        .read(File.join(root, "plugin.rb"))
        .scan(/require_relative\s+"([^"]+)"/)
        .flatten
        .map { |path| "#{path}.rb" }

    definers = {}
    required.each do |path|
      File
        .read(File.join(root, path))
        .scan(/^\s*(?:class|module)\s+([A-Z][A-Za-z0-9_]*)/)
        .flatten
        .each { |name| definers[name] ||= path }
    end

    position = required.each_with_index.to_h

    named_in_class_body = lambda do |source|
      source
        .scan(
          /(?:serializer|each_serializer):\s*([A-Z][A-Za-z0-9_:]*)|
           ^\s*class\s+\S+\s*<\s*([A-Z][A-Za-z0-9_:]*)|
           ^\s*(?:include|extend|prepend)\s+([A-Z][A-Za-z0-9_:]*)/x,
        )
        .flatten
        .compact
        .map { |name| name.split("::").last }
    end

    early = required.flat_map do |path|
      named_in_class_body
        .call(File.read(File.join(root, path)))
        .filter_map do |name|
          definer = definers[name]
          next if definer.nil? || definer == path
          next if position[definer] < position[path]

          "#{path} names #{name}, which #{definer} defines and plugin.rb requires after it"
        end
    end

    expect(early).to be_empty
  end
end
