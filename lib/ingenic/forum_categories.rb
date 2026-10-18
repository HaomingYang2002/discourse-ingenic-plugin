# frozen_string_literal: true

module Ingenic
  # The forum's own sections, as rows rather than as a paragraph of instructions
  # for somebody to follow by hand.
  #
  # Three of the navigation's entries name a category: Official Announcements,
  # Technical Discussions and Open Source. A fresh Discourse install creates no
  # categories of its own, so without this the three of them are links to a 404
  # on a front page that otherwise renders perfectly. The tree is here and
  # `rake ingenic:seed_categories` builds it.
  #
  # Open Source is a section rather than a place to post. It holds two
  # sub-forums, and which of them a project belongs in is a question of who is
  # publishing it: Third-Party Open Source takes anyone's project, Official Open
  # Source is the company's own and only an administrator can start a topic
  # there. The parent takes no topics itself, which is what its read-only
  # permission says — a section with two sub-forums has nowhere of its own for a
  # topic to be filed.
  #
  # Creating is not the same as owning. A second run leaves a category that is
  # already there exactly as the forum has it, renaming and re-colouring
  # included. Permissions are the one thing a re-run will touch, and only when
  # it is asked to.
  module ForumCategories
    SPECS = [
      {
        slug: "official-announcements",
        name: "Official Announcements",
        zh_name: "官方公告",
        position: 0,
        color: "0CBBFF",
        text_color: "FFFFFF",
        description: "Releases, roadmaps and notices from the Ingenic team.",
        permissions: {
          everyone: :readonly,
          staff: :full,
        },
      },
      {
        slug: "technical-discussions",
        name: "Technical Discussions",
        zh_name: "技术讨论",
        position: 1,
        color: "1B8FD4",
        text_color: "FFFFFF",
        description: "Questions, answers and hard-won experience with Ingenic chips.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "open-source",
        name: "Open Source",
        zh_name: "开源版块",
        position: 2,
        color: "4FC3F7",
        text_color: "0B3C5D",
        description: "Open-source projects built on Ingenic chips, official and third-party.",
        permissions: {
          everyone: :readonly,
        },
      },
      {
        slug: "third-party",
        parent: "open-source",
        name: "Third-Party Open Source",
        zh_name: "三方开源",
        position: 0,
        color: "7ED6F5",
        text_color: "0B3C5D",
        description: "Projects published by the community. Anyone with an account can post one.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "official",
        parent: "open-source",
        name: "Official Open Source",
        zh_name: "官方开源",
        position: 1,
        color: "29A3E0",
        text_color: "FFFFFF",
        description: "Projects published by Ingenic. Only administrators can post here.",
        permissions: {
          everyone: :readonly,
          admins: :full,
        },
      },
    ].freeze

    # How the Open Source section draws itself. Two sub-forums and a merged
    # topic list: the cards at the top are the way into each sub-forum, and
    # below them every topic from both, so a reader who does not care which one
    # a project belongs to can read the section as one place. Discourse builds
    # this natively — `show_subcategory_list` plus a category-scoped list with
    # `default_list_filter` of "all" — which is why there is no custom page for
    # it here.
    #
    # The About topic stays as the category definition (it is what the section
    # description is read from) but is unpinned: a definition is not an
    # announcement, and a pinned one pushes the first real topic down.
    OPEN_SOURCE = "open-source"
    OPEN_SOURCE_LAYOUT = {
      show_subcategory_list: true,
      subcategory_list_style: "boxes",
      default_list_filter: "all",
    }.freeze

    module_function

    def slugs
      SPECS.map { |spec| spec[:slug] }
    end

    # Slugs the navigation links to and the forum does not have. Worth asking
    # about separately from seeding, because the symptom is a working page with
    # a link on it that goes nowhere.
    def missing
      slugs - Category.where(slug: slugs).pluck(:slug)
    end

    # Creates what is absent and reports what it did — one row per category, as
    # `{ slug:, action:, detail: }` with an action of `:created`, `:kept` or
    # `:skipped`. Nothing is ever deleted, and nothing already there is renamed.
    #
    # `permissions: true` re-applies the permissions above to categories that
    # are already there. That is the whole reason for a second run: a category
    # created before this list was settled keeps whatever it was created with,
    # and the difference is invisible until somebody cannot post where they
    # should be able to.
    def seed!(permissions: false)
      rows = SPECS.filter_map { |spec| seed_one(spec, permissions: permissions) }
      ensure_layout!
      rows
    end

    # Applies the section's display settings to a category that already exists.
    # Safe to run on every boot-time setup: it writes only what differs, and
    # returns the list of what changed so a task can print it.
    def ensure_layout!
      category = Category.find_by(slug: OPEN_SOURCE)
      return [] if category.nil?

      changes = []
      OPEN_SOURCE_LAYOUT.each do |attribute, wanted|
        next if category.public_send(attribute) == wanted

        changes << "#{attribute}=#{wanted.inspect}"
        category.public_send("#{attribute}=", wanted)
      end

      category.save! if changes.any?
      unpin_about(category)

      changes
    end

    def unpin_about(category)
      topic = Topic.find_by(id: category.topic_id)
      return if topic.nil?

      attributes = {}
      attributes[:pinned_at] = nil if topic.pinned_at
      attributes[:pinned_globally] = false if topic.pinned_globally
      topic.update_columns(attributes) if attributes.any?
    end

    def seed_one(spec, permissions:)
      parent = spec[:parent] && Category.find_by(slug: spec[:parent])

      if spec[:parent] && parent.nil?
        return {
          slug: spec[:slug],
          action: :skipped,
          detail: "#{spec[:parent]} is not there, and a sub-forum without its section is not a place",
        }
      end

      category = Category.find_by(slug: spec[:slug], parent_category_id: parent&.id)

      if category.nil?
        create(spec, parent)
        return {
          slug: spec[:slug],
          action: :created,
          detail: permission_words(spec[:permissions]),
        }
      end

      if permissions
        category.set_permissions(spec[:permissions])
        apply_flags(category, spec)
        category.save!
        return {
          slug: spec[:slug],
          action: :repermissioned,
          detail: permission_words(spec[:permissions]),
        }
      end

      solved_changed = apply_flags(category, spec)
      category.save! if solved_changed

      current = normalized(category.permissions_params)
      # An empty set is not "nobody": Discourse stores everyone-full by storing
      # no rows at all.
      current = { "everyone" => "full" } if current.empty?
      wanted = normalized(spec[:permissions])

      {
        slug: spec[:slug],
        action: :kept,
        detail:
          current == wanted ? nil : "permissions are #{permission_words(current)}, not #{permission_words(wanted)}",
      }
    end

    def create(spec, parent)
      category =
        Category.new(
          name: spec[:name],
          slug: spec[:slug],
          description: spec[:description],
          color: spec[:color],
          text_color: spec[:text_color],
          position: spec[:position],
          parent_category_id: parent&.id,
          # The "About" topic the category is created with is written by the
          # system account: seeding is not somebody's post.
          user_id: Discourse::SYSTEM_USER_ID,
        )

      # Before the save, because a category cannot be saved without a security
      # setting and because a sub-forum's permissions are validated against its
      # section's on the way in.
      category.set_permissions(spec[:permissions])
      apply_flags(category, spec)
      localize(category, spec)
      category.save!
      category
    end

    # Accepted answers are a discourse-solved column. A forum without the
    # plugin simply has nowhere to put the flag, which is not an error: the
    # status tag then only ever appears where staff put it by hand.
    def apply_flags(category, spec)
      return false unless spec[:solved]
      return false unless category.respond_to?(:enable_accepted_answers=)
      return false if category.respond_to?(:enable_accepted_answers?) && category.enable_accepted_answers?

      category.enable_accepted_answers = true
      true
    end

    # Discourse keeps a category's name per language in its own table and reads
    # it only when content localization is switched on. Building the rows while
    # it is off would leave names nothing consults; skipping them while it is on
    # would leave a Chinese reader in a Chinese sidebar looking at English
    # category names.
    def localize(category, spec)
      return unless SiteSetting.content_localization_enabled
      return if spec[:zh_name].blank?
      return if SiteSetting.content_localization_supported_locales.to_s.split("|").exclude?("zh_CN")

      category.category_localizations.build(locale: "zh_CN", name: spec[:zh_name])
    end

    # Group names as strings and permission levels as names, so what a category
    # has and what the list asks for can be compared without either of them
    # being in a particular shape.
    def normalized(permissions)
      permissions.to_h do |group, level|
        [group.to_s, level.is_a?(Integer) ? CategoryGroup.permission_types[level] : level]
      end
    end

    def permission_words(permissions)
      normalized(permissions).map { |group, level| "#{group}: #{level}" }.sort.join(", ")
    end
  end
end
