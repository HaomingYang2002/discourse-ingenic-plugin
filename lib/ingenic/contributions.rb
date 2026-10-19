# frozen_string_literal: true

module Ingenic
  # The contribution score: a ranking of who took part, not a wallet.
  #
  # Points (Ingenic::Points) are money — earned, spent on downloads, escrowed
  # for a bounty. This is a separate number with a separate table, and nothing
  # here ever touches a balance. That is what lets the forum weight a technical
  # answer or an open-source release without giving the author more purchasing
  # power, and what keeps a 250-point bounty from swallowing the weekly board.
  #
  # What earns, and how much:
  #
  #   topic_created      5   opening a discussion
  #   post_created       2   answering in one
  #   like_received      1   a post of yours being liked (capped per day)
  #   solution_accepted 15   your answer being accepted
  #   daily_visit        1   turning up (once a day, capped per week)
  #
  # A topic or an answer in Technical Discussions is worth 3 more, and one in
  # Open Source 5 more. The bonus is paid once per contribution, not per like:
  # a post that is liked ten times should not pay its category ten times.
  #
  # Nothing here is allowed to fail a forum action, for the same reason as the
  # points ledger: a reply must not be refused because a ranking table is
  # having a bad day.
  module Contributions
    # Strings rather than IngenicPointRule's constants: this file is required
    # before the plugin's models are (they load in `after_initialize`), and a
    # constant that does not exist yet is an exception at boot rather than at
    # the first award.
    EVENT_POINTS = {
      "topic_created" => 5,
      "post_created" => 2,
      "like_received" => 1,
      "solution_accepted" => 15,
      "daily_visit" => 1,
    }.freeze

    # Category slug → extra contribution for a topic or an answer written there.
    CATEGORY_BONUS = {
      "technical-discussions" => 3,
      "open-source" => 5,
    }.freeze

    # Ten likes a day is a contribution; a hundred is a campaign.
    LIKE_DAILY_CAP = 10
    # Five visits a week rewards turning up without ranking idleness.
    VISIT_WEEKLY_CAP = 5

    module_function

    def enabled?
      SiteSetting.ingenic_contributions_enabled
    end

    # Records one award. Returns the row, or nil when there was nothing to
    # record — no account, a bot, the feature switched off, a duplicate, or a
    # limit reached.
    def award(user:, event:, subject: nil, at: Time.zone.now)
      event = event.to_s
      base = EVENT_POINTS[event]
      return if base.nil? || !earns?(user)
      return if event == IngenicPointRule::LIKE_RECEIVED && like_cap_reached?(user, at)

      insert(user: user, event: event, points: base + bonus_for(event, subject), subject: subject, at: at)
    rescue StandardError => e
      warn(:award, e)
    end

    # A day's visit, if this is its first and the week has room.
    def visit(user, at: Time.zone.now)
      return unless earns?(user)
      return if IngenicContribution.where(user_id: user.id, event: "daily_visit", on_date: at.to_date).exists?

      week_start = at.beginning_of_week
      this_week =
        IngenicContribution
          .where(user_id: user.id, event: "daily_visit", created_at: week_start..at)
          .count
      return if this_week >= VISIT_WEEKLY_CAP

      insert(user: user, event: "daily_visit", points: EVENT_POINTS["daily_visit"], subject: nil, at: at)
    rescue StandardError => e
      warn(:visit, e)
    end

    # Everything one subject ever contributed, taken back. Used when the post
    # or the topic behind an award goes away: a deleted answer should not keep
    # its author on the board.
    def remove_subject(subject, event: nil)
      return if subject.nil?

      scope = IngenicContribution.where(
        subject_type: subject.class.base_class.name,
        subject_id: subject.id,
      )
      scope = scope.where(event: event.to_s) if event
      scope.delete_all

      # A post's likes are separate rows naming the PostAction, so they do not
      # go with the post unless they are asked for by name.
      if subject.is_a?(Post)
        action_ids = PostAction.where(post_id: subject.id).pluck(:id)
        if action_ids.any?
          IngenicContribution
            .where(subject_type: "PostAction", subject_id: action_ids)
            .then { |rows| event ? rows.where(event: event.to_s) : rows }
            .delete_all
        end
      end
    end

    # The week's ranking, richest first. One query, because the homepage asks
    # on every visit and a per-member read would be ten of them.
    def weekly(limit: 10, at: Time.zone.now)
      IngenicContribution
        .since(at.beginning_of_week)
        .where.not(user_id: nil)
        .group(:user_id)
        .order(Arel.sql("SUM(points) DESC, MIN(created_at) ASC"))
        .limit(limit)
        .pluck(:user_id, Arel.sql("SUM(points)"))
    end

    def total_for(user)
      return 0 if user.nil?

      IngenicContribution.where(user_id: user.id).sum(:points)
    end

    def weekly_for(user, at: Time.zone.now)
      return 0 if user.nil?

      IngenicContribution.since(at.beginning_of_week).where(user_id: user.id).sum(:points)
    end

    def insert(user:, event:, points:, subject:, at:)
      IngenicContribution.create!(
        user_id: user.id,
        event: event,
        points: points,
        subject: subject,
        on_date: at.to_date,
        created_at: at,
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def earns?(user)
      return false if user.nil? || user.bot?
      return false if SiteSetting.ingenic_points_exclude_staff && user.staff?

      enabled?
    end

    def like_cap_reached?(user, at)
      IngenicContribution
        .where(user_id: user.id, event: IngenicPointRule::LIKE_RECEIVED, created_at: at.beginning_of_day..at)
        .count >= LIKE_DAILY_CAP
    end

    # Only writing something earns the category bonus. A like on an
    # open-source post is still one like.
    def bonus_for(event, subject)
      return 0 if event == IngenicPointRule::LIKE_RECEIVED

      post = subject.is_a?(Post) ? subject : subject.try(:post)
      slug = post&.topic&.category&.slug
      CATEGORY_BONUS[slug].to_i
    rescue StandardError
      0
    end

    def warn(event, error)
      Rails.logger.warn(
        "Ingenic: contribution handler #{event} failed: #{error.class} #{error.message}",
      )
      nil
    end
  end
end
