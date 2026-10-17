# frozen_string_literal: true

# The weekly contribution leaderboard on the home page.
#
# It counts what the ledger says members earned this week — opening topics,
# answering, being liked, having an answer accepted — and deliberately not what
# they spent. A ranking that moved when somebody unlocked a download would rank
# spending rather than contributing.
#
# Administrators' manual adjustments and the return of a bounty escrow are left
# out for the same reason: neither is something a member did this week.
class IngenicLeaderboardController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  skip_before_action :check_xhr

  def index
    render_json_dump(
      enabled: Ingenic::Points.enabled?,
      week_start: week_start.iso8601,
      entries: entries,
    )
  end

  private

  def week_start
    @week_start ||= Time.zone.now.beginning_of_week
  end

  def entries
    return [] if !Ingenic::Points.enabled?

    rows =
      IngenicPointEntry
        .where(created_at: week_start..)
        .where("points > 0")
        .where.not(
          event: [
            IngenicPointEntry::MANUAL,
            IngenicPointEntry::BOUNTY_REFUND,
            IngenicPointEntry::REVERSAL,
            IngenicPointEntry::DOWNLOAD,
          ],
        )
        .where.not(user_id: nil)
        .group(:user_id)
        .order(Arel.sql("SUM(points) DESC"))
        .limit(10)
        .pluck(:user_id, Arel.sql("SUM(points)"))

    users = User.where(id: rows.map(&:first)).index_by(&:id)

    rows.filter_map.with_index(1) do |(user_id, points), rank|
      user = users[user_id]
      # A deleted account takes its rows with it, but a row whose account cannot
      # be drawn is not a rank: skipping it is better than an empty avatar.
      next if user.nil?

      {
        "rank" => rank,
        "username" => user.username,
        "name" => user.name.presence || user.username,
        "avatar_template" => user.avatar_template,
        "points" => points.to_i,
      }
    end
  end
end
