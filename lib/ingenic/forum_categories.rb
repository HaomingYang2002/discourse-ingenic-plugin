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
  # Technical Discussions is three levels deep: the section holds the series,
  # and a series holds its chips. It is the same shape the documentation's
  # product picker and the download filters use, so a reader can go from a chip
  # to its discussions without meeting a different taxonomy.
  #
  # Open Source sits beside Technical Discussions at the top level, after it in
  # the navigation, and holds two sub-forums. Which of them a project belongs in
  # is a question of who is publishing it: Third-Party Open Source takes
  # anyone's project, Official Open Source is the company's own and only an
  # administrator can start a topic there. The section takes no topics itself,
  # which is what its read-only permission says.
  #
  # Creating is not the same as owning. A second run leaves a category that is
  # already there as the forum has it, renaming and re-colouring included.
  # Parentage is the part the list owns: a category found at an address other
  # than the one above is re-parented, because the tree is the list's shape.
  # Permissions are the other thing a re-run will touch, and only when it is
  # asked to.
  module ForumCategories
    # The forum's own tree. Technical Discussions is three levels deep: it holds
    # a series, and a series holds its chips. `max_category_nesting` has to be 3
    # for the last level to be allowed, which `seed!` sets. Open Source is a
    # top-level section beside it.
    SPECS = [
      {
        slug: "official-announcements",
        name: "Official Announcements",
        zh_name: "官方公告",
        zh_description: "君正团队发布的版本、路线图和公告。",
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
        zh_description: "关于君正芯片的问题、解答与实践经验。",
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
        zh_description: "基于君正芯片的开源项目，包括官方与第三方。",
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
        zh_description: "社区发布的开源项目，注册用户都可以发布。",
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
        zh_description: "君正官方发布的开源项目，只有管理员可以发布。",
        position: 1,
        color: "29A3E0",
        text_color: "FFFFFF",
        description: "Projects published by Ingenic. Only administrators can post here.",
        permissions: {
          everyone: :readonly,
          admins: :full,
        },
      },
      {
        slug: "t-series",
        parent: "technical-discussions",
        name: "T Series",
        zh_name: "T 系列",
        zh_description: "T 系列视觉处理器：按型号提问与交流。",
        position: 1,
        color: "1B8FD4",
        text_color: "FFFFFF",
        description: "T-series vision processors: questions and experience by chip.",
        permissions: {
          everyone: :readonly,
        },
      },
      {
        slug: "t33",
        parent: "t-series",
        name: "T33",
        zh_name: "T33",
        zh_description: "关于 T33 的问题与解答。",
        position: 0,
        color: "1B8FD4",
        text_color: "FFFFFF",
        description: "Questions and answers about the T33.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "t32pro",
        parent: "t-series",
        name: "T32Pro",
        zh_name: "T32Pro",
        zh_description: "关于 T32Pro 的问题与解答。",
        position: 1,
        color: "1B8FD4",
        text_color: "FFFFFF",
        description: "Questions and answers about the T32Pro.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "t41",
        parent: "t-series",
        name: "T41",
        zh_name: "T41",
        zh_description: "关于 T41 的问题与解答。",
        position: 2,
        color: "1B8FD4",
        text_color: "FFFFFF",
        description: "Questions and answers about the T41.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "c-series",
        parent: "technical-discussions",
        name: "C Series",
        zh_name: "C 系列",
        zh_description: "C 系列连接芯片：按型号提问与交流。",
        position: 2,
        color: "2F9E63",
        text_color: "FFFFFF",
        description: "C-series connectivity chips: questions and experience by chip.",
        permissions: {
          everyone: :readonly,
        },
      },
      {
        slug: "cw020",
        parent: "c-series",
        name: "CW020",
        zh_name: "CW020",
        zh_description: "关于 CW020 的问题与解答。",
        position: 0,
        color: "2F9E63",
        text_color: "FFFFFF",
        description: "Questions and answers about the CW020.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "cw080",
        parent: "c-series",
        name: "CW080",
        zh_name: "CW080",
        zh_description: "关于 CW080 的问题与解答。",
        position: 1,
        color: "2F9E63",
        text_color: "FFFFFF",
        description: "Questions and answers about the CW080.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "x-series",
        parent: "technical-discussions",
        name: "X Series",
        zh_name: "X 系列",
        zh_description: "X 系列应用处理器：按型号提问与交流。",
        position: 3,
        color: "8A5CC2",
        text_color: "FFFFFF",
        description: "X-series application processors: questions and experience by chip.",
        permissions: {
          everyone: :readonly,
        },
      },
      {
        slug: "x2600",
        parent: "x-series",
        name: "X2600",
        zh_name: "X2600",
        zh_description: "关于 X2600 的问题与解答。",
        position: 0,
        color: "8A5CC2",
        text_color: "FFFFFF",
        description: "Questions and answers about the X2600.",
        permissions: {
          everyone: :full,
        },
        solved: true,
      },
      {
        slug: "mcu-series",
        parent: "technical-discussions",
        name: "MCU Series",
        zh_name: "MCU 系列",
        zh_description: "MCU 系列：按型号提问与交流。",
        position: 4,
        color: "C2761B",
        text_color: "FFFFFF",
        description: "MCU questions and experience by chip.",
        permissions: {
          everyone: :readonly,
        },
      },
      {
        slug: "g32s10",
        parent: "mcu-series",
        name: "G32S10",
        zh_name: "G32S10",
        zh_description: "关于 G32S10 的问题与解答。",
        position: 0,
        color: "C2761B",
        text_color: "FFFFFF",
        description: "Questions and answers about the G32S10.",
        permissions: {
          everyone: :full,
        },
        solved: true,
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

    # Slugs this list is responsible for and the forum does not have. Worth
    # asking about separately from seeding, because the symptom is a
    # navigation that leads into a tree whose middle or leaf is missing.
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
      ensure_nesting!
      rows = SPECS.filter_map { |spec| seed_one(spec, permissions: permissions) }
      ensure_layout!
      rows
    end

    # The tree has a chip under a series under a section. Discourse refuses to
    # save the last level while `max_category_nesting` is the default 2, and
    # the failure arrives as a validation error on a category the task is
    # halfway through creating. The setting is hidden from the admin UI, so it
    # is set here rather than left as a step somebody has to know about.
    def ensure_nesting!
      return if SiteSetting.max_category_nesting.to_i >= 3

      SiteSetting.max_category_nesting = 3
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
      moved = false

      # A section that is already in the forum at another address — including
      # the top level, which is where an Open Source seeded by an earlier
      # version of this list may still sit. The tree is this list's shape, and
      # leaving the row there while creating a second one would give the
      # navigation two open-source pages. Slugs are unique across the forum, so
      # the row found here is the same section, not a second one with the same
      # name.
      if category.nil?
        category = Category.find_by(slug: spec[:slug])
        if category
          category.parent_category_id = parent&.id
          category.position = spec[:position] if spec[:position]
          category.save!
          moved = true
        end
      end

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
        localize(category, spec)
        category.save!
        return {
          slug: spec[:slug],
          action: :repermissioned,
          detail: permission_words(spec[:permissions]),
        }
      end

      # A category that was seeded before content localization was switched on
      # has neither its own language nor the Chinese name. Seeding again adds
      # them without touching anything the forum has changed since.
      changed = apply_flags(category, spec)
      changed = localize(category, spec) || changed
      category.save! if changed

      current = normalized(category.permissions_params)
      # An empty set is not "nobody": Discourse stores everyone-full by storing
      # no rows at all.
      current = { "everyone" => "full" } if current.empty?
      wanted = normalized(spec[:permissions])

      detail =
        if moved
          parent ? "moved under #{parent.name}" : "moved to the top level"
        elsif current != wanted
          "permissions are #{permission_words(current)}, not #{permission_words(wanted)}"
        end

      {
        slug: spec[:slug],
        action: moved ? :moved : :kept,
        detail: detail,
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
    # it only when content localization is switched on — and only for a
    # category that says which language its own name is written in. Building the
    # rows while the feature is off would leave names nothing consults; skipping
    # them while it is on would leave a Chinese reader in a Chinese sidebar
    # looking at English category names. Both the language and the translation
    # are written here, so a second run repairs a category seeded before the
    # feature was enabled.
    def localize(category, spec)
      return false unless SiteSetting.content_localization_enabled
      return false if spec[:zh_name].blank?
      return false if SiteSetting.content_localization_supported_locales.to_s.split("|").exclude?("zh_CN")

      changed = false

      if category.locale.blank?
        category.locale = "en"
        changed = true
      end

      localization =
        if category.new_record?
          category.category_localizations.detect { |row| row.locale == "zh_CN" } ||
            category.category_localizations.build(locale: "zh_CN")
        else
          category.category_localizations.find_or_initialize_by(locale: "zh_CN")
        end

      # Fill in a name or description that is not there; do not overwrite one
      # an administrator has edited. A re-run repairs what is missing, it does
      # not reset the forum to this list. The description matters because the
      # section cards draw it directly under the name: a translated name over an
      # English description reads as a half-finished page.
      if localization.new_record? || localization.name.blank?
        localization.name = spec[:zh_name]
        changed = true
      end

      if spec[:zh_description].present? &&
           (localization.new_record? || localization.description.blank?)
        localization.description = spec[:zh_description]
        changed = true
      end

      # A new row is written by the category's own save. An existing one is
      # not: the association has no autosave, so a translation added to a
      # category that was seeded before this list carried descriptions would
      # otherwise be assigned and then dropped.
      localization.save! if localization.persisted? && localization.changed?

      changed
    end

    # Group names as strings and permission levels as names, so what a category
    # has and what the list asks for can be compared without either of them
    # being in a particular shape.
    def normalized(permissions)
      permissions.to_h do |group, level|
        name = level.is_a?(Integer) ? CategoryGroup.permission_types[level] : level
        # A stored permission is a string and the list above writes symbols;
        # comparing the two without this made a matching set look different.
        [group.to_s, name.to_s]
      end
    end

    def permission_words(permissions)
      normalized(permissions).map { |group, level| "#{group}: #{level}" }.sort.join(", ")
    end
  end
end
