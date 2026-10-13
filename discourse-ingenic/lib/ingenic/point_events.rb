# frozen_string_literal: true

module Ingenic
  # What notices the forum happening, and turns it into points.
  #
  # The arithmetic is in Ingenic::Points; this is only the reading of Discourse's
  # own events into the ledger's vocabulary. Two things are decided here and
  # nowhere else:
  #
  # * What counts. A contribution to the public forum does. A private message
  #   nobody else can read does not, a whisper only staff can read does not, and
  #   a bot's post is not a member's work.
  # * Who earns. The person who wrote the post, never the person who liked it —
  #   points are for what was written, and paying the liker would be paying for
  #   a click.
  #
  # Every method here is a Discourse event handler reached from an action
  # somebody is in the middle of. Points are a record of the forum, not a
  # condition of using it, so each one swallows its own failures and writes them
  # to the log: a reply must not be refused because the points table is having a
  # bad day.
  #
  # Deletion is taken back and restoring is not. A post that earned points and
  # then went away is reversed, which is what stops points being farmed by
  # posting and deleting; a post brought back afterwards does not earn them
  # again, and an administrator who wants to make that good can say so on the
  # account. Rewarding a restoration would mean deciding, every time, whether a
  # reversal still stood, and the ledger would stop being a record of what
  # happened.
  module PointEvents
    module_function

    # The first post of a topic and a reply to one are the same event to
    # Discourse — `post_created` fires for both, and `topic_created` fires
    # alongside it for the first. One entry per post, priced as whichever of the
    # two it is, is what keeps the opening post of every topic from being paid
    # for twice.
    def post_created(post)
      return unless awardable_post?(post)

      event =
        post.is_first_post? ? IngenicPointRule::TOPIC_CREATED : IngenicPointRule::POST_CREATED

      Ingenic::Points.award(user: post.user, event: event, subject: post)
    rescue StandardError => e
      complain(:post_created, e)
    end

    def post_destroyed(post)
      return if post.nil?

      Ingenic::Points.reverse_subject(post, reason: I18n.t("ingenic.points.reversed_post"))
    rescue StandardError => e
      complain(:post_destroyed, e)
    end

    def like_created(post_action)
      post = post_action&.post
      return unless awardable_post?(post)

      Ingenic::Points.award(
        user: post.user,
        event: IngenicPointRule::LIKE_RECEIVED,
        subject: post_action,
      )
    rescue StandardError => e
      complain(:like_created, e)
    end

    def like_destroyed(post_action)
      return if post_action.nil?

      Ingenic::Points.reverse_subject(post_action, reason: I18n.t("ingenic.points.reversed_like"))
    rescue StandardError => e
      complain(:like_destroyed, e)
    end

    def solution_accepted(post)
      return unless awardable_post?(post)

      Ingenic::Points.award(
        user: post.user,
        event: IngenicPointRule::SOLUTION_ACCEPTED,
        subject: post,
      )
    rescue StandardError => e
      complain(:solution_accepted, e)
    end

    # Only fires when discourse-solved is in play. Registering it costs nothing
    # when it is not, which is why the plugin does not have to know.
    def solution_unaccepted(post)
      return if post.nil?

      Ingenic::Points.reverse_subject(
        post,
        reason: I18n.t("ingenic.points.reversed_solution"),
      )
    rescue StandardError => e
      complain(:solution_unaccepted, e)
    end

    # A post worth points, and an author who can hold them.
    def awardable_post?(post)
      return false if post.nil? || post.user.nil?
      return false if post.whisper?

      topic = post.topic
      return false if topic.nil? || topic.private_message?

      earns?(post.user)
    end

    # Whether this account earns at all.
    #
    # Staff are left out by default. Answering here is their job rather than
    # their contribution, and a leaderboard of the community that the community
    # cannot reach the top of is not a leaderboard. It is a setting because it
    # is a judgement, and because a forum may want its moderators on it.
    def earns?(user)
      return false if user.nil? || user.bot?
      return false if SiteSetting.ingenic_points_exclude_staff && user.staff?

      true
    end

    def complain(event, error)
      Rails.logger.warn(
        "Ingenic: points handler #{event} failed: #{error.class} #{error.message}",
      )
      nil
    end
  end
end
