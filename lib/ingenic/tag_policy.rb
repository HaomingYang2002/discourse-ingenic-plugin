# frozen_string_literal: true

module Ingenic
  # The tag vocabulary the forum keeps for itself, and the settings that decide
  # who may add a tag to a topic.
  #
  # Tags here are not navigation. A topic's section is its category and the
  # category badge is what a reader clicks to go there; a tag says what the
  # topic is about (linux, camera, sdk) or what state it is in (公告, 已解决,
  # 高赞). That is why the three state tags live in a group only staff may
  # apply: a member choosing a technical tag is labelling their own question,
  # but a member marking their own question solved or popular is answering a
  # question about the forum that is not theirs to answer.
  #
  # Creating a tag is an administrator's, because an open vocabulary of
  # one-off spellings is not a vocabulary. Using one that exists is not.
  #
  # `apply!` is idempotent. It is called by a migration so a deployment gets
  # the policy without anybody remembering to run a task, and by
  # `rake ingenic:setup` so a forum that has drifted can be put back.
  module TagPolicy
    GROUP_NAME = "官方状态"

    STATUS_TAGS = {
      "公告" => "announcement",
      "已解决" => "resolved",
      "高赞" => "hot",
    }.freeze

    module_function

    def apply!
      group = TagGroup.find_or_create_by!(name: GROUP_NAME)
      staff_only(group)

      STATUS_TAGS.each_key do |name|
        tag = Tag.find_or_create_by!(name: name)
        TagGroupMembership.find_or_create_by!(tag_group_id: group.id, tag_id: tag.id)
      end

      SiteSetting.create_tag_allowed_groups = "1" if SiteSetting.respond_to?(:create_tag_allowed_groups)

      # Every logged-in account can put an existing technical tag on a topic,
      # including a new member's. Group 10 is trust_level_0, which everybody is
      # in; 1 and 2 are administrators and moderators.
      if SiteSetting.respond_to?(:tag_topic_allowed_groups)
        SiteSetting.tag_topic_allowed_groups = "1|2|10"
      end

      enable_solved!
      true
    end

    # The group is visible to everyone — a reader has to see 已解决 beside a
    # title for it to mean anything — but only staff may apply one of its tags.
    def staff_only(group)
      permissions = { everyone: :readonly, staff: :full }

      permissions.each do |name, level|
        principal = Group.find_by(name: name.to_s)
        next if principal.nil?

        permission =
          TagGroupPermission.find_or_initialize_by(tag_group_id: group.id, group_id: principal.id)
        permission.permission_type = TagGroupPermission.permission_types[level]
        permission.save!
      end
    end

    # Solved is the forum's answer to "has this been answered", and the tag
    # beside the title is its visible half. The topic author accepting an answer
    # is the ordinary path; staff can accept on their behalf when they have to.
    # All of this is skipped when discourse-solved is not installed: the events
    # simply never fire and the tag is never applied.
    def enable_solved!
      return unless SiteSetting.respond_to?(:solved_enabled)

      SiteSetting.solved_enabled = true
      if SiteSetting.respond_to?(:allow_solved_on_all_topics)
        SiteSetting.allow_solved_on_all_topics = true
      end
      if SiteSetting.respond_to?(:accept_solutions_topic_author)
        SiteSetting.accept_solutions_topic_author = true
      end
    end
  end
end
