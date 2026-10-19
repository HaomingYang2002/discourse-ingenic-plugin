# frozen_string_literal: true

require "rails_helper"

describe IngenicLeaderboardController do
  fab!(:alice) { Fabricate(:user) }
  fab!(:bob) { Fabricate(:user) }
  fab!(:carol) { Fabricate(:user) }

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_contributions_enabled = true
  end

  def contribution(user, points, event, created_at: Time.zone.now)
    IngenicContribution.create!(
      user: user,
      points: points,
      event: event,
      on_date: created_at.to_date,
      created_at: created_at,
    )
  end

  it "ranks this week's contribution and ignores both last week and the points ledger" do
    contribution(alice, 5, "topic_created")
    contribution(alice, 2, "post_created")
    contribution(bob, 15, "solution_accepted")
    contribution(carol, 4, "daily_visit")
    contribution(carol, 100, "topic_created", created_at: 10.days.ago)

    # A bounty payout is points, not contribution, and must not leak onto the
    # board the way it did when both were read from the same table.
    IngenicPointEntry.create!(
      user: carol,
      points: 500,
      event: IngenicPointEntry::BOUNTY_AWARD,
      reason: "bounty",
      created_at: Time.zone.now,
    )

    get "/ingenic/leaderboard.json"

    expect(response.status).to eq(200)
    json = response.parsed_body

    expect(json["entries"].map { |row| row["username"] }).to eq(
      [bob.username, alice.username, carol.username],
    )
    expect(json["entries"].map { |row| row["points"] }).to eq([15, 7, 4])
    expect(json["entries"].map { |row| row["rank"] }).to eq([1, 2, 3])
    expect(json["week_start"]).to be_present
  end

  it "honours the limit the card asks for" do
    contribution(alice, 5, "topic_created")

    get "/ingenic/leaderboard.json", params: { limit: 1 }

    expect(response.status).to eq(200)
    expect(response.parsed_body["entries"].length).to eq(1)
  end

  it "serves an empty board when contribution is switched off" do
    SiteSetting.ingenic_contributions_enabled = false
    contribution(alice, 5, "topic_created")

    get "/ingenic/leaderboard.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["entries"]).to eq([])
    expect(response.parsed_body["enabled"]).to eq(false)
  end

  it "tells a signed-in viewer what they have this week" do
    contribution(alice, 5, "topic_created")
    sign_in(alice)

    get "/ingenic/leaderboard.json"

    expect(response.parsed_body.dig("viewer", "username")).to eq(alice.username)
    # The request itself counts as the viewer's visit for the day, so the
    # number is whatever the score says rather than a fixed 5.
    expect(response.parsed_body.dig("viewer", "points")).to eq(
      Ingenic::Contributions.weekly_for(alice),
    )
  end

  it "answers a browser navigation with the app shell" do
    get "/ingenic/leaderboard"

    expect(response.status).to eq(200)
    expect(response.body).to include("<!DOCTYPE html>")
  end
end
