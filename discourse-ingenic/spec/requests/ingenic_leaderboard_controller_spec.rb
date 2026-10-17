# frozen_string_literal: true

require "rails_helper"

describe IngenicLeaderboardController do
  fab!(:alice) { Fabricate(:user) }
  fab!(:bob) { Fabricate(:user) }
  fab!(:carol) { Fabricate(:user) }

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_points_enabled = true
  end

  def entry(user, points, event, created_at: Time.zone.now)
    IngenicPointEntry.create!(
      user: user,
      points: points,
      event: event,
      reason: event,
      created_at: created_at,
    )
  end

  it "ranks what members earned this week and leaves spending out" do
    entry(alice, 5, IngenicPointRule::TOPIC_CREATED)
    entry(alice, 2, IngenicPointRule::POST_CREATED)
    entry(bob, 15, IngenicPointRule::SOLUTION_ACCEPTED)
    entry(carol, 4, IngenicPointEntry::MANUAL)
    entry(carol, 8, IngenicPointEntry::BOUNTY_REFUND)
    entry(bob, 50, IngenicPointEntry::DOWNLOAD)
    entry(carol, 100, IngenicPointRule::TOPIC_CREATED, created_at: 10.days.ago)

    get "/ingenic/leaderboard.json"

    expect(response.status).to eq(200)
    json = response.parsed_body

    expect(json["entries"].map { |row| row["username"] }).to eq([bob.username, alice.username])
    expect(json["entries"].map { |row| row["points"] }).to eq([15, 7])
    expect(json["entries"].map { |row| row["rank"] }).to eq([1, 2])
    expect(json["week_start"]).to be_present
  end

  it "serves an empty board when points are switched off" do
    SiteSetting.ingenic_points_enabled = false
    entry(alice, 5, IngenicPointRule::TOPIC_CREATED)

    get "/ingenic/leaderboard.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body["entries"]).to eq([])
    expect(response.parsed_body["enabled"]).to eq(false)
  end
end
