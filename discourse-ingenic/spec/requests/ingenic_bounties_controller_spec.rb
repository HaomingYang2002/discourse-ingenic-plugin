# frozen_string_literal: true

require "rails_helper"

describe IngenicBountiesController do
  fab!(:asker) { Fabricate(:user) }
  fab!(:answerer) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: asker) }
  fab!(:other_topic) { Fabricate(:topic, user: asker) }

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_points_enabled = true
    SiteSetting.ingenic_bounties_enabled = true
    SiteSetting.ingenic_bounty_min_points = 10
    SiteSetting.ingenic_bounty_max_points = 1_000
    SiteSetting.solved_enabled = true
    SiteSetting.allow_solved_on_all_topics = true

    Ingenic::Points.adjust(user: asker, points: 500, note: "seed", by: asker)
  end

  def balance_of(user)
    IngenicPointBalance.total_for(user)
  end

  def standing_bounty
    IngenicBounty.live.last
  end

  describe "GET /ingenic/bounties" do
    it "serves the board to a signed-out visitor" do
      Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)

      get "/ingenic/bounties.json"

      expect(response.status).to eq(200)
      json = response.parsed_body

      expect(json["bounties"].size).to eq(1)
      expect(json["bounties"].first["points"]).to eq(100)
      expect(json["bounties"].first["topic"]["title"]).to eq(topic.title)
      expect(json["min_points"]).to eq(10)
      expect(json["expiry_days"]).to eq(14)
      expect(json["signed_in"]).to eq(false)
    end

    it "serves the app shell to a browser navigation" do
      get "/ingenic/bounties"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    it "says what the viewer has, so the page can say what they can afford" do
      sign_in(asker)

      get "/ingenic/bounties.json"

      expect(response.parsed_body["balance"]).to eq(500)
    end

    it "names the standing offers in the order of what they are worth" do
      Ingenic::Bounties.open!(topic: topic, user: asker, points: 50)
      Ingenic::Bounties.open!(topic: other_topic, user: asker, points: 300)

      get "/ingenic/bounties.json"

      expect(response.parsed_body["bounties"].map { |b| b["points"] }).to eq([300, 50])
    end

    # The board must not be a way round a private category.
    it "leaves out offers on topics the viewer cannot see" do
      group = Fabricate(:group)
      hidden = Fabricate(:topic, user: asker, category: Fabricate(:private_category, group: group))
      Ingenic::Bounties.open!(topic: hidden, user: asker, points: 300)

      get "/ingenic/bounties.json"

      expect(response.parsed_body["bounties"]).to be_empty
    end
  end

  describe "POST /ingenic/bounties" do
    it "sets the points aside and records the escrow" do
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 100 }

      expect(response.status).to eq(200)
      expect(response.parsed_body["balance"]).to eq(400)

      bounty = standing_bounty
      expect(bounty.points).to eq(100)
      expect(bounty.topic_id).to eq(topic.id)
      expect(IngenicPointEntry.find_by(event: IngenicPointEntry::BOUNTY).points).to eq(-100)
    end

    it "refuses a visitor with no account" do
      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 100 }

      expect(response.status).to eq(403)
      expect(IngenicBounty.count).to eq(0)
    end

    # The person who asked the question decides what an answer is worth, and the
    # person who pays is the person who asked.
    it "refuses somebody else's topic" do
      sign_in(answerer)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 100 }

      expect(response.status).to eq(403)
      expect(IngenicBounty.count).to eq(0)
    end

    it "refuses an offer below the floor, with the floor in the message" do
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 5 }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include("10")
    end

    it "refuses an offer above the ceiling" do
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 5_000 }

      expect(response.status).to eq(422)
    end

    it "refuses more than the account has, and writes nothing" do
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 900 }

      expect(response.status).to eq(422)
      expect(balance_of(asker)).to eq(500)
      expect(IngenicBounty.count).to eq(0)
    end

    it "refuses a second offer on a topic that already has one" do
      Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 100 }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.bounties.taken"),
      )
    end

    it "answers with not-found for a topic that does not exist" do
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: 0, points: 100 }

      expect(response.status).to eq(404)
    end

    it "refuses while the forum is not taking bounties" do
      SiteSetting.ingenic_bounties_enabled = false
      sign_in(asker)

      post "/ingenic/bounties.json", params: { topic_id: topic.id, points: 100 }

      expect(response.status).to eq(403)
      expect(balance_of(asker)).to eq(500)
    end
  end

  describe "POST /ingenic/bounties/:id/cancel" do
    it "gives the points back and closes the offer" do
      bounty = Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      sign_in(asker)

      post "/ingenic/bounties/#{bounty.id}/cancel.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["balance"]).to eq(500)
      expect(bounty.reload.state).to eq(IngenicBounty::CANCELLED)
    end

    it "refuses somebody who is neither the asker nor staff" do
      bounty = Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      sign_in(answerer)

      post "/ingenic/bounties/#{bounty.id}/cancel.json"

      expect(response.status).to eq(403)
      expect(bounty.reload.state).to eq(IngenicBounty::OPEN)
      expect(balance_of(asker)).to eq(400)
    end

    # A bounty can turn out to have been opened where it should not have been,
    # and the alternative to letting staff close it is editing the database.
    it "lets staff close one down" do
      bounty = Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      sign_in(Fabricate(:admin))

      post "/ingenic/bounties/#{bounty.id}/cancel.json"

      expect(response.status).to eq(200)
      expect(balance_of(asker)).to eq(500)
    end

    it "answers with not-found for a bounty that does not exist" do
      sign_in(asker)

      post "/ingenic/bounties/0/cancel.json"

      expect(response.status).to eq(404)
    end
  end

  # The whole feature end to end, through discourse-solved's own controller.
  # There is no endpoint here for accepting an answer — the author's ✓ is the
  # only way to say which answer won — so this is what proves the wiring.
  describe "accepting an answer" do
    # The forum's own award for an accepted answer is a separate payment for a
    # separate reason, and it would be in the way of reading the balances here.
    before { IngenicPointRule.for(IngenicPointRule::SOLUTION_ACCEPTED).update!(points: 0) }

    it "pays the answerer what the asker put up, and closes the offer" do
      answer = Fabricate(:post, topic: topic, user: answerer)
      bounty = Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      sign_in(asker)

      post "/solution/accept.json", params: { id: answer.id }

      expect(response.status).to eq(200)
      expect(balance_of(answerer)).to eq(100)
      expect(balance_of(asker)).to eq(400)

      bounty.reload
      expect(bounty.state).to eq(IngenicBounty::ACCEPTED)
      expect(bounty.accepted_post_id).to eq(answer.id)
      expect(bounty.accepted_by_id).to eq(asker.id)
    end

    it "leaves a topic without a bounty on it alone" do
      answer = Fabricate(:post, topic: other_topic, user: answerer)
      other_topic.update!(user_id: asker.id)
      sign_in(asker)

      post "/solution/accept.json", params: { id: answer.id }

      expect(response.status).to eq(200)
      expect(balance_of(answerer)).to eq(0)
    end
  end

  # What the topic page reads, so its banner costs no second request.
  describe "the topic page's own copy" do
    it "carries the standing offer and the control that opens one" do
      Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      sign_in(asker)

      get "/t/#{topic.id}.json"

      json = response.parsed_body
      expect(json["ingenic_bounty"]["points"]).to eq(100)
      expect(json["ingenic_bounty"]["state"]).to eq(IngenicBounty::OPEN)
      expect(json["can_open_ingenic_bounty"]).to eq(true)
    end

    # A paid bounty stays on the topic as the record of what an answer was
    # worth, so the page has to carry it — and the name it carries is the
    # answerer's, not the member who pressed accept. Here that is staff, which
    # is what tells the two apart.
    it "carries the paid offer and names the member who was paid" do
      answer = Fabricate(:post, topic: topic, user: answerer)
      bounty = Ingenic::Bounties.open!(topic: topic, user: asker, points: 100)
      Ingenic::Bounties.accept!(bounty: bounty, post: answer, by: Fabricate(:admin))
      sign_in(asker)

      get "/t/#{topic.id}.json"

      json = response.parsed_body
      expect(json["ingenic_bounty"]["state"]).to eq(IngenicBounty::ACCEPTED)
      expect(json["ingenic_bounty"]["answerer"]["username"]).to eq(answerer.username)
    end

    it "is null on a topic without one" do
      sign_in(asker)

      get "/t/#{topic.id}.json"

      expect(response.parsed_body["ingenic_bounty"]).to be_nil
    end

    it "offers the control to nobody but the author" do
      sign_in(answerer)

      get "/t/#{topic.id}.json"

      expect(response.parsed_body["can_open_ingenic_bounty"]).to eq(false)
    end

    it "says nothing about bounties while the feature is off" do
      sign_in(asker)
      SiteSetting.ingenic_bounties_enabled = false

      get "/t/#{topic.id}.json"

      expect(response.parsed_body).not_to have_key("ingenic_bounty")
    end
  end
end
