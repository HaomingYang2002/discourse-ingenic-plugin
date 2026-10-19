# frozen_string_literal: true

# The weekly contribution leaderboard, and the page it is shown on.
#
# It ranks by IngenicContribution, never by IngenicPointEntry. The two used to be
# the same table, which meant a member who won a 500-point bounty outranked a
# week of answering — the board was ranking windfalls. Contribution is a separate
# number with no bounty in it, so this is now a reading of what people did.
#
# Public, because a ranking nobody can see encourages nothing, and read-only from
# the front end.
class IngenicLeaderboardController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  skip_before_action :check_xhr, only: %i[index]

  def index
    return render_app_shell unless request.format.json?

    render_json_dump(
      enabled: Ingenic::Contributions.enabled?,
      week_start: week_start.iso8601,
      entries: entries,
      # The viewer's own line, whether or not they made the top ten. A board
      # that only shows the leaders leaves everybody else with no number to
      # watch, and this one is cheap: one indexed sum.
      viewer: viewer,
    )
  end

  private

  def week_start
    @week_start ||= Time.zone.now.beginning_of_week
  end

  def limit
    requested = params[:limit].to_i
    requested.positive? ? [requested, 50].min : 10
  end

  def entries
    return [] if !Ingenic::Contributions.enabled?

    rows = Ingenic::Contributions.weekly(limit: limit, at: week_start)
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

  def viewer
    return nil if current_user.nil? || !Ingenic::Contributions.enabled?

    {
      "username" => current_user.username,
      "points" => Ingenic::Contributions.weekly_for(current_user, at: week_start),
    }
  end
end
