# frozen_string_literal: true

module Ingenic
  # What notices the forum happening, and turns it into contribution.
  #
  # The counterpart to Ingenic::PointEvents, and deliberately a separate reader
  # of the same events: points are money and this is a ranking, so the two can
  # be switched on, priced and taken back independently.
  #
  # The rules about what counts and who earns are the same, because the question
  # is the same — a private message nobody can read is not a contribution to the
  # community, and a bot is not a member. What differs is only what happens to
  # the number: it is never spent, so nothing here has a balance to protect.
  #
  # Every method swallows its own failures. A ranking is a record of the forum,
  # not a condition of using it.
  module ContributionEvents
    module_function

    def post_created(post)
      return unless awardable_post?(post)

      event =
        post.is_first_post? ? IngenicPointRule::TOPIC_CREATED : IngenicPointRule::POST_CREATED

      Ingenic::Contributions.award(user: post.user, event: event, subject: post)
    rescue StandardError => e
      complain(:post_created, e)
    end

    # A deleted post takes its contribution with it, likes included: a member
    # cannot rank by writing and removing.
    def post_destroyed(post)
      return if post.nil?

      Ingenic::Contributions.remove_subject(post)
    rescue StandardError => e
      complain(:post_destroyed, e)
    end

    def like_created(post_action)
      post = post_action&.post
      return unless awardable_post?(post)

      Ingenic::Contributions.award(
        user: post.user,
        event: IngenicPointRule::LIKE_RECEIVED,
        subject: post_action,
      )
    rescue StandardError => e
      complain(:like_created, e)
    end

    def like_destroyed(post_action)
      return if post_action.nil?

      Ingenic::Contributions.remove_subject(post_action)
    rescue StandardError => e
      complain(:like_destroyed, e)
    end

    def solution_accepted(post)
      return unless awardable_post?(post)

      Ingenic::Contributions.award(
        user: post.user,
        event: IngenicPointRule::SOLUTION_ACCEPTED,
        subject: post,
      )
    rescue StandardError => e
      complain(:solution_accepted, e)
    end

    # The acceptance can be taken back, so the contribution it paid can be too —
    # unlike a bounty, which has already changed hands. The row is removed
    # rather than reversed, because accepting again should pay it again.
    def solution_unaccepted(post)
      return if post.nil?

      Ingenic::Contributions.remove_subject(post, event: IngenicPointRule::SOLUTION_ACCEPTED)
    rescue StandardError => e
      complain(:solution_unaccepted, e)
    end

    # Someone opened the forum. The day's award is settled by the table's own
    # uniqueness, so this can be called as often as Discourse likes.
    def user_seen(user, _previous_seen_at = nil)
      Ingenic::Contributions.visit(user)
    rescue StandardError => e
      complain(:user_seen, e)
    end

    def awardable_post?(post)
      return false if post.nil? || post.user.nil?
      return false if post.whisper?

      topic = post.topic
      return false if topic.nil? || topic.private_message?

      Ingenic::Contributions.earns?(post.user)
    end

    def complain(event, error)
      Rails.logger.warn(
        "Ingenic: contribution handler #{event} failed: #{error.class} #{error.message}",
      )
      nil
    end
  end
end
