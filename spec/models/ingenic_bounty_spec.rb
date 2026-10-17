# frozen_string_literal: true

require "rails_helper"

describe IngenicBounty do
  fab!(:user) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: user) }

  def make_bounty(attributes = {})
    described_class.create!(
      { topic_id: topic.id, user_id: user.id, points: 100, expires_at: 14.days.from_now }.merge(
        attributes,
      ),
    )
  end

  describe "validations" do
    it "takes an offer with points and a deadline" do
      expect(make_bounty).to be_persisted
    end

    it "refuses an offer of nothing" do
      expect { make_bounty(points: 0) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses an offer of negative points" do
      expect { make_bounty(points: -1) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses a state that is not one of the four" do
      expect { make_bounty(state: "somewhere_else") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses an offer with no deadline" do
      expect { make_bounty(expires_at: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # The friendly mirror of the partial index. The database is what guarantees
    # it, and this is what turns the second open bounty on one topic into a
    # message rather than a raised exception.
    it "refuses a second standing offer on the same topic" do
      make_bounty

      expect { make_bounty }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # The index is partial, so the rule above is about the *open* one and only
    # the open one: a topic whose offer expired can have another.
    it "allows a second one once the first has settled" do
      first = make_bounty
      first.update!(state: described_class::CANCELLED, settled_at: Time.zone.now)

      expect(make_bounty).to be_persisted
    end
  end

  describe "scopes" do
    it "separates the standing offers from the settled ones" do
      open_bounty = make_bounty
      settled = described_class.create!(
        topic_id: Fabricate(:topic, user: user).id,
        user_id: user.id,
        points: 100,
        expires_at: 1.day.from_now,
        state: described_class::EXPIRED,
        settled_at: Time.zone.now,
      )

      expect(described_class.live).to contain_exactly(open_bounty)
      expect(described_class.settled).to contain_exactly(settled)
    end

    it "orders the board richest first, and by age within a price" do
      old = make_bounty
      rich = described_class.create!(
        topic_id: Fabricate(:topic, user: user).id,
        user_id: user.id,
        points: 500,
        expires_at: 1.day.from_now,
      )
      new_same_price = described_class.create!(
        topic_id: Fabricate(:topic, user: user).id,
        user_id: user.id,
        points: 100,
        expires_at: 1.day.from_now,
      )

      expect(described_class.by_value.to_a).to eq([rich, old, new_same_price])
    end
  end

  describe "#open?" do
    it "is true while the offer stands" do
      expect(make_bounty).to be_open
    end

    it "is false once it has settled" do
      bounty = make_bounty
      bounty.update!(state: described_class::ACCEPTED, settled_at: Time.zone.now)

      expect(bounty).not_to be_open
      expect(bounty).to be_settled
    end
  end

  # The hour between a deadline passing and the expiry job running: the offer is
  # still open and already owed back, and both the board and the topic page have
  # to have an answer for it.
  describe "#due?" do
    it "is false for an offer with time left" do
      expect(make_bounty).not_to be_due
    end

    it "is true once the deadline has passed" do
      expect(make_bounty(expires_at: 1.minute.ago)).to be_due
    end

    it "is false for one that has already been dealt with" do
      bounty = make_bounty(expires_at: 1.minute.ago)
      bounty.update!(state: described_class::EXPIRED, settled_at: Time.zone.now)

      expect(bounty).not_to be_due
    end
  end
end
