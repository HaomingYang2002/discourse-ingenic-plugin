# frozen_string_literal: true

module Ingenic
  # The two status tags the forum maintains itself: 已解决 follows Discourse's
  # accepted answer, and 高赞 follows the like count. Neither is a navigation
  # tag; both sit on the topic beside the technical tags so a reader can see at
  # a glance whether the question is answered and whether it is worth reading.
  #
  # They are in a tag group that only staff may apply, so a member cannot label
  # their own question solved or popular. This module is trusted code and writes
  # the rows directly rather than through the tag guardian for that reason.
  module StatusTags
    SOLVED = "已解决"
    HOT = "高赞"
    # The custom field marks a 高赞 tag this plugin applied, so a later drop
    # below the threshold removes that tag and never a tag staff added by hand.
    HOT_FIELD = "ingenic_high_like"

    module_function

    def solved!(topic, solved:)
      set(topic, SOLVED, solved)
    end

    def high_like!(topic, hot:)
      set(topic, HOT, hot)
      if hot
        topic.custom_fields[HOT_FIELD] = true
      else
        topic.custom_fields.delete(HOT_FIELD)
      end
      topic.save_custom_fields
    rescue StandardError => e
      Rails.logger.warn("Ingenic: could not record the 高赞 state: #{e.class} #{e.message}")
    end

    def set(topic, name, on)
      return if topic.nil?

      tag = Tag.find_by(name: name)
      return if tag.nil?

      if on
        topic.tags << tag unless topic.tags.exists?(id: tag.id)
      elsif topic.tags.exists?(id: tag.id)
        topic.tags.delete(tag)
      end
    rescue StandardError => e
      Rails.logger.warn("Ingenic: could not set #{name} on topic #{topic&.id}: #{e.class} #{e.message}")
    end

    # One pass over every topic that is above the line and every topic this job
    # previously tagged. Likes are counted across the topic's posts, deleted
    # posts and private messages left out.
    #
    # Run on a schedule rather than from the like event: a topic crosses the
    # threshold on somebody else's click, and the count that matters is the
    # total, which a single event does not have. A periodic pass also takes the
    # tag back when a post is deleted and the topic drops below the line.
    def refresh_high_like!(threshold:)
      threshold = threshold.to_i
      return 0 if threshold < 1

      counts =
        PostAction
          .where(post_action_type_id: PostActionType.types[:like])
          .joins(:post)
          .where(posts: { deleted_at: nil, post_type: Post.types[:regular] })
          .group("posts.topic_id")
          .count

      qualifying = counts.select { |_topic_id, likes| likes >= threshold }.keys
      visible =
        Topic
          .where(id: qualifying, deleted_at: nil, visible: true)
          .where.not(archetype: Archetype.private_message)
          .pluck(:id)
          .to_set

      hot_ids = TopicTag.joins(:tag).where(tags: { name: HOT }).pluck(:topic_id).to_set
      changed = 0

      Topic
        .where(id: visible.to_a - hot_ids.to_a)
        .find_each do |topic|
          high_like!(topic, hot: true)
          changed += 1
        end

      # Take it back only where this job put it. A staff member may have tagged
      # a topic by hand, and that tag is not the like count's to remove.
      Topic
        .where(id: hot_ids.to_a - visible.to_a)
        .find_each do |topic|
          next unless topic.custom_fields[HOT_FIELD]

          high_like!(topic, hot: false)
          changed += 1
        end

      changed
    end
  end
end
