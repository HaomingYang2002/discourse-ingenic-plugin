# frozen_string_literal: true

# 高分悬赏: the board, and the two things a member does on it.
#
# Only two, because accepting an answer is not one of them. A bounty is paid when
# Discourse's own accepted answer is marked — the ✓ the topic author already has
# — so there is no second way to say "this is the answer" for the forum to keep
# in step. What is here is opening an offer on one's own topic and withdrawing
# one, which are the two things discourse-solved has no opinion about.
#
# The money is Ingenic::Bounties' business; this is the reading of a request into
# it and an answer back out.
class IngenicBountiesController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  skip_before_action :check_xhr, only: %i[show]

  before_action :ensure_logged_in, only: %i[create cancel]
  before_action :find_bounty, only: %i[cancel]

  def show
    return render_app_shell unless request.format.json?

    render_json_dump(
      enabled: Ingenic::Bounties.enabled?,
      # Whether the forum *could* pay one at all, which is a different question
      # from whether this member may open one: the page says "not available here"
      # rather than offering a button that will be refused.
      available: Ingenic::Bounties.available?,
      signed_in: current_user.present?,
      min_points: Ingenic::Bounties.min_points,
      max_points: Ingenic::Bounties.max_points,
      expiry_days: Ingenic::Bounties.expiry_days,
      # What the viewer has, so the page can say whether they can afford the
      # offer they are about to make without a second request.
      balance: Ingenic::Points.total_for(current_user),
      bounties: board.map { |bounty| json_for(bounty) },
    )
  end

  def create
    topic = Topic.find_by(id: params[:topic_id])

    return render_json_error(I18n.t("ingenic.bounties.no_topic"), status: 404) if topic.nil?

    unless guardian.can_open_ingenic_bounty?(topic)
      return render_json_error(I18n.t("ingenic.bounties.not_allowed"), status: 403)
    end

    outcome = Ingenic::Bounties.open!(topic: topic, user: current_user, points: params[:points])

    # `open!` answers with the bounty it created or with the reason it did not,
    # and every reason is a sentence to show rather than an error page — which is
    # the shape the download centre already uses for its refusals.
    return render_json_error(refusal(outcome), status: 422) unless outcome.is_a?(IngenicBounty)

    render_json_dump(bounty: json_for(outcome), balance: Ingenic::Points.total_for(current_user))
  end

  def cancel
    unless guardian.can_cancel_ingenic_bounty?(@bounty)
      return render_json_error(I18n.t("ingenic.bounties.not_allowed"), status: 403)
    end

    outcome = Ingenic::Bounties.cancel!(bounty: @bounty, by: current_user)

    # `:not_open` is what a second click on a withdrawal gets, and the member
    # whose first click worked does not need to be told off for the second.
    if outcome != :refunded
      return render_json_error(refusal(outcome), status: 422) unless outcome == :already
    end

    render_json_dump(
      bounty: json_for(@bounty.reload),
      balance: Ingenic::Points.total_for(current_user),
      notice: I18n.t("ingenic.bounties.cancelled"),
    )
  end

  private

  def find_bounty
    @bounty = IngenicBounty.find_by(id: params[:id])
    raise Discourse::NotFound if @bounty.nil?
  end

  # Read through the guardian, because a bounty names a topic and a topic can be
  # in a category the viewer has no business knowing about.
  def board
    Ingenic::Bounties.board(guardian: guardian, limit: board_limit)
  end

  def board_limit
    limit = params[:limit].to_i
    limit.positive? ? [limit, 50].min : 20
  end

  def json_for(bounty)
    IngenicBountySerializer.new(bounty, scope: guardian, root: false).as_json
  end

  def refusal(outcome)
    case outcome
    when :unavailable then I18n.t("ingenic.bounties.unavailable")
    when :too_small then I18n.t("ingenic.bounties.too_small", min: Ingenic::Bounties.min_points)
    when :too_large then I18n.t("ingenic.bounties.too_large", max: Ingenic::Bounties.max_points)
    when :taken then I18n.t("ingenic.bounties.taken")
    when :insufficient then I18n.t("ingenic.bounties.insufficient")
    when :already then I18n.t("ingenic.bounties.already")
    else I18n.t("ingenic.bounties.not_open")
    end
  end
end
