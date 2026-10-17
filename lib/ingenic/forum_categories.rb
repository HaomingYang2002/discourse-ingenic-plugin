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
      SPECS.filter_map { |spec| seed_one(spec, permissions: permissions) }
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
        category.save!
        return {
          slug: spec[:slug],
          action: :repermissioned,
          detail: permission_words(spec[:permissions]),
        }
      end

      current = category.permissions_params
      wanted = normalized(spec[:permissions])

      {
        slug: spec[:slug],
        action: :kept,
        detail: current == wanted ? nil : "permissions are #{permission_words(current)}, not #{permission_words(wanted)}",
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
      localize(category, spec)
      category.save!
      category
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
