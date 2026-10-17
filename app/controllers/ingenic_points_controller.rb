# frozen_string_literal: true

# The member's own points page: what they have, how they got it, and what the
# forum pays for.
#
# Their own ledger and nobody else's. The leaderboard is not here on purpose —
# a forum that ranks its members by post count invites posts written to be
# counted, and the numbers an account needs in order to understand its own
# standing are its own.
class IngenicPointsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  skip_before_action :check_xhr, only: %i[show]

  def show
    return render_app_shell unless request.format.json?

    render_json_dump(
      signed_in: current_user.present?,
      enabled: Ingenic::Points.enabled?,
      balance: Ingenic::Points.total_for(current_user),
      # What the forum pays for, so "how do I get points" has an answer on the
      # page that shows the number. Retired rules are left out: a member cannot
      # act on a rule that no longer pays.
      rules: IngenicPointRule.published.ordered.map { |rule| rule_json(rule) },
      entries: entries.map { |entry| entry_json(entry) },
    )
  end

  private

  # Newest first, and capped. This is a page that answers "where did these come
  # from", and the first hundred answers it.
  def entries
    return [] if current_user.nil?

    Ingenic::Points.entries_for(current_user, limit: 100)
  end

  def rule_json(rule)
    { "event" => rule.event, "label" => rule.label, "points" => rule.points }
  end

  def entry_json(entry)
    {
      "id" => entry.id,
      "created_at" => entry.created_at.iso8601,
      "points" => entry.points,
      "event" => entry.event,
      "reason" => entry.reason,
    }
  end
end
