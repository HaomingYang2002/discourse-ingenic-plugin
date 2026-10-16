# frozen_string_literal: true

require "rails_helper"

describe Ingenic::Bounties do
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

    # The asker's own points, put there the way an administrator would. Every
    # test about escrow needs a balance to escrow from.
    Ingenic::Points.adjust(user: asker, points: 500, note: "seed", by: asker)
  end

  def balance_of(user)
    IngenicPointBalance.total_for(user)
  end

  # An answer on a topic — post number 2, which is what the first reply is.
  def answer_on(topic)
    Fabricate(:post, topic: topic, user: answerer)
  end

  describe ".available?" do
    it "is on for a forum that has points and the solved plugin" do
      expect(described_class.available?).to eq(true)
    end

    it "is off when the forum is not taking bounties" do
      SiteSetting.ingenic_bounties_enabled = false
      expect(described_class.available?).to eq(false)
    end

    # An escrow is a movement in the ledger, and a forum that has stopped handing
    # points out has nothing to set aside.
    it "is off when points are switched off" do
      SiteSetting.ingenic_points_enabled = false
      expect(described_class.available?).to eq(false)
    end
  end

  describe ".open!" do
    it "sets the points aside and records the escrow" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(bounty).to be_a(IngenicBounty)
      expect(bounty.state).to eq(IngenicBounty::OPEN)
      expect(bounty.points).to eq(100)
      expect(balance_of(asker)).to eq(400)

      entry = IngenicPointEntry.find_by(event: IngenicPointEntry::BOUNTY)
      expect(entry.points).to eq(-100)
      expect(entry.user_id).to eq(asker.id)
      expect(entry.subject).to eq(bounty)
    end

    it "sets an end to the offer" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(bounty.expires_at).to be_within(1.minute).of(14.days.from_now)
    end

    it "takes the days from the setting" do
      SiteSetting.ingenic_bounty_expiry_days = 3
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(bounty.expires_at).to be_within(1.minute).of(3.days.from_now)
    end

    it "says so and writes nothing when the balance is short" do
      expect(described_class.open!(topic: topic, user: asker, points: 900)).to eq(:insufficient)
      expect(balance_of(asker)).to eq(500)
      expect(IngenicBounty.count).to eq(0)
      expect(IngenicPointEntry.where(event: IngenicPointEntry::BOUNTY)).to be_empty
    end

    it "refuses an offer below the floor" do
      expect(described_class.open!(topic: topic, user: asker, points: 9)).to eq(:too_small)
      expect(IngenicBounty.count).to eq(0)
    end

    it "refuses an offer above the ceiling" do
      expect(described_class.open!(topic: topic, user: asker, points: 1_001)).to eq(:too_large)
      expect(IngenicBounty.count).to eq(0)
    end

    # Even with the floor configured down to nothing: a bounty of nothing is not
    # a bounty, and the model would refuse the row anyway.
    it "refuses an offer of nothing" do
      SiteSetting.ingenic_bounty_min_points = 0

      expect(described_class.open!(topic: topic, user: asker, points: 0)).to eq(:too_small)
      expect(IngenicBounty.count).to eq(0)
    end

    it "refuses a second offer on a topic that already has one" do
      described_class.open!(topic: topic, user: asker, points: 100)

      expect(described_class.open!(topic: topic, user: asker, points: 100)).to eq(:taken)
      expect(balance_of(asker)).to eq(400)
    end

    it "allows one on another topic" do
      described_class.open!(topic: topic, user: asker, points: 100)

      expect(described_class.open!(topic: other_topic, user: asker, points: 100)).to be_a(
        IngenicBounty,
      )
      expect(balance_of(asker)).to eq(300)
    end

    it "refuses while the forum is not taking bounties" do
      SiteSetting.ingenic_bounties_enabled = false

      expect(described_class.open!(topic: topic, user: asker, points: 100)).to eq(:unavailable)
      expect(balance_of(asker)).to eq(500)
    end
  end

  describe ".settle_for" do
    fab!(:answer) { answer_on(topic) }

    before { described_class.open!(topic: topic, user: asker, points: 100) }

    it "pays the answerer what the asker put up, in full" do
      expect(described_class.settle_for(answer)).to eq(:paid)

      expect(balance_of(answerer)).to eq(100)
      expect(IngenicPointEntry.find_by(event: IngenicPointEntry::BOUNTY_AWARD).points).to eq(100)
    end

    # The points left the asker's balance when the offer was opened, so paying
    # the answerer is a transfer rather than a second charge.
    it "does not charge the asker twice" do
      described_class.settle_for(answer)

      expect(balance_of(asker)).to eq(400)
    end

    it "closes the bounty and remembers which answer it was for" do
      described_class.settle_for(answer)

      bounty = IngenicBounty.last
      expect(bounty.state).to eq(IngenicBounty::ACCEPTED)
      expect(bounty.accepted_post_id).to eq(answer.id)
      expect(bounty.settled_at).to be_present
    end

    # Who accepted it is read off discourse-solved's own row, which is its table
    # and not ours to write in a test. That the reading happens at all — through
    # the real solved controller — is in the request spec; what is here is that
    # what comes back is what the bounty keeps.
    it "records who accepted the answer" do
      described_class.stubs(:accepter_of).returns(asker)

      described_class.settle_for(answer)

      expect(IngenicBounty.last.accepted_by_id).to eq(asker.id)
    end

    # What the settled banner on the topic names. It is the author of the answer
    # and not the member who pressed accept, which is why it is read through the
    # post: staff accept on the asker's behalf, and the name that has to be right
    # is the one that was paid.
    it "reads the author of the answer as the member who was paid" do
      described_class.stubs(:accepter_of).returns(Fabricate(:admin))

      described_class.settle_for(answer)

      expect(IngenicBounty.last.answerer).to eq(answerer)
    end

    it "does nothing for a topic with no bounty" do
      expect(described_class.settle_for(answer_on(other_topic))).to be_nil
      expect(balance_of(answerer)).to eq(0)
    end

    # The opening post is not an answer to its own question, and accepting it
    # would be a way of paying oneself.
    it "does nothing for the opening post" do
      described_class.settle_for(topic.first_post)

      expect(balance_of(asker)).to eq(400)
      expect(IngenicBounty.last.state).to eq(IngenicBounty::OPEN)
    end

    it "pays once, however many times an acceptance arrives" do
      described_class.settle_for(answer)
      described_class.settle_for(answer)

      expect(balance_of(answerer)).to eq(100)
      expect(IngenicPointEntry.where(event: IngenicPointEntry::BOUNTY_AWARD).count).to eq(1)
    end

    it "does nothing for a bounty that has been withdrawn" do
      described_class.cancel!(bounty: IngenicBounty.last, by: asker)

      described_class.settle_for(answer)

      expect(balance_of(answerer)).to eq(0)
      expect(balance_of(asker)).to eq(500)
    end

    it "does nothing for a bounty that has expired" do
      described_class.expire!(IngenicBounty.last)

      described_class.settle_for(answer)

      expect(balance_of(answerer)).to eq(0)
    end

    # A bounty is the asker's own points rather than the forum's, so the rule
    # that keeps staff off the leaderboard has nothing to say about it.
    it "pays a member of staff who wrote the accepted answer" do
      SiteSetting.ingenic_points_exclude_staff = true
      staff_answer = Fabricate(:post, topic: topic, user: Fabricate(:admin))

      described_class.settle_for(staff_answer)

      expect(balance_of(staff_answer.user)).to eq(100)
    end

    it "swallows its own failures rather than refusing the acceptance" do
      Ingenic::Points.stubs(:record).raises(StandardError.new("the ledger is having a day off"))

      expect { described_class.settle_for(answer) }.not_to raise_error
    end
  end

  describe ".cancel!" do
    it "gives the points back and closes the offer" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(described_class.cancel!(bounty: bounty, by: asker)).to eq(:refunded)
      expect(balance_of(asker)).to eq(500)
      expect(bounty.reload.state).to eq(IngenicBounty::CANCELLED)
      expect(IngenicPointEntry.find_by(event: IngenicPointEntry::BOUNTY_REFUND).points).to eq(100)
    end

    it "remembers who withdrew it" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      described_class.cancel!(bounty: bounty, by: asker)

      expect(IngenicPointEntry.find_by(event: IngenicPointEntry::BOUNTY_REFUND).awarded_by_id).to eq(
        asker.id,
      )
    end

    it "gives the points back once, however many times it is asked" do
      2.times { described_class.cancel!(bounty: IngenicBounty.last, by: asker) }

      expect(balance_of(asker)).to eq(500)
      expect(IngenicPointEntry.where(event: IngenicPointEntry::BOUNTY_REFUND).count).to eq(1)
    end

    it "allows a new offer afterwards" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      described_class.cancel!(bounty: bounty, by: asker)

      expect(described_class.open!(topic: topic, user: asker, points: 200)).to be_a(IngenicBounty)
    end
  end

  describe ".expire_due!" do
    it "closes the offers whose time is up and returns the points" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      bounty.update!(expires_at: 1.minute.ago)

      expect(described_class.expire_due!).to eq(1)
      expect(balance_of(asker)).to eq(500)
      expect(bounty.reload.state).to eq(IngenicBounty::EXPIRED)
    end

    it "leaves the ones with time left alone" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(described_class.expire_due!).to eq(0)
      expect(bounty.reload.state).to eq(IngenicBounty::OPEN)
      expect(balance_of(asker)).to eq(400)
    end

    it "leaves the settled ones where they are" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      described_class.expire!(bounty)
      bounty.update!(expires_at: 1.minute.ago)

      expect(described_class.expire_due!).to eq(0)
    end

    # The asker's account can be deleted while their offer stands. The offer is
    # still closed on time — it is not theirs to hold open — and the refund is
    # written against nobody, because there is no account left to hold the
    # points. What must not happen is the job stopping here: it closes every due
    # offer in one pass, and an orphan that raised would strand all the others.
    it "closes an offer whose asker has been deleted" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      bounty.update!(expires_at: 1.minute.ago)
      IngenicBounty.where(id: bounty.id).update_all(user_id: nil)
      IngenicPointBalance.where(user_id: asker.id).delete_all

      expect(described_class.expire_due!).to eq(1)

      expect(bounty.reload.state).to eq(IngenicBounty::EXPIRED)
      refund = IngenicPointEntry.find_by(event: IngenicPointEntry::BOUNTY_REFUND, subject_id: bounty.id)
      expect(refund.user_id).to be_nil
      expect(refund.points).to eq(100)
    end
  end

  describe ".for_topic" do
    it "finds the standing offer" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(described_class.for_topic(topic)).to eq(bounty)
    end

    it "finds nothing on a topic without one" do
      expect(described_class.for_topic(other_topic)).to be_nil
    end

    it "finds the offer that was paid, so the topic can say so" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      answer = Fabricate(:post, topic: topic)
      described_class.accept!(bounty: bounty, post: answer, by: asker)

      found = described_class.for_topic(topic)

      expect(found).to eq(bounty)
      expect(found.state).to eq(IngenicBounty::ACCEPTED)
    end

    # A withdrawn offer is still the newest row for the moment between one
    # ending and the next beginning. It is returned, and the topic page draws
    # nothing for it — the alternative would be a banner saying "withdrawn"
    # sitting over a question for the rest of its life.
    it "still finds the newest row once the offer has been withdrawn" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      described_class.cancel!(bounty: bounty, by: asker)

      expect(described_class.for_topic(topic)).to eq(bounty)
    end

    it "finds the standing one rather than the one already paid" do
      settled = described_class.open!(topic: topic, user: asker, points: 100)
      answer = Fabricate(:post, topic: topic)
      described_class.accept!(bounty: settled, post: answer, by: asker)
      standing = described_class.open!(topic: topic, user: asker, points: 200)

      expect(described_class.for_topic(topic)).to eq(standing)
    end

    it "finds nothing for no topic at all" do
      expect(described_class.for_topic(nil)).to be_nil
    end
  end

  describe ".board" do
    it "lists the standing offers, richest first" do
      small = described_class.open!(topic: topic, user: asker, points: 50)
      large = described_class.open!(topic: other_topic, user: asker, points: 300)

      expect(described_class.board(guardian: Guardian.new(asker))).to eq([large, small])
    end

    it "leaves out the ones that have been settled" do
      bounty = described_class.open!(topic: topic, user: asker, points: 50)
      described_class.cancel!(bounty: bounty, by: asker)

      expect(described_class.board(guardian: Guardian.new(asker))).to be_empty
    end

    # A bounty names a topic, and a topic can be somewhere the viewer has no
    # business knowing about — the board must not be the way around that.
    it "leaves out topics the viewer cannot see" do
      group = Fabricate(:group)
      private_category = Fabricate(:private_category, group: group)
      hidden_topic = Fabricate(:topic, user: asker, category: private_category)
      described_class.open!(topic: hidden_topic, user: asker, points: 300)
      described_class.open!(topic: topic, user: asker, points: 50)

      board = described_class.board(guardian: Guardian.new(answerer))

      expect(board.map(&:topic_id)).to eq([topic.id])
    end

    it "leaves out deleted topics" do
      described_class.open!(topic: topic, user: asker, points: 50)
      topic.trash!

      expect(described_class.board(guardian: Guardian.new(asker))).to be_empty
    end

    it "honours the limit" do
      described_class.open!(topic: topic, user: asker, points: 50)
      described_class.open!(topic: other_topic, user: asker, points: 60)

      expect(described_class.board(guardian: Guardian.new(asker), limit: 1).size).to eq(1)
    end

    it "is empty for a viewer with no guardian at all" do
      described_class.open!(topic: topic, user: asker, points: 50)

      expect(described_class.board(guardian: nil)).to be_empty
    end
  end

  describe ".refund_for_topic!" do
    it "gives a standing offer back and closes it" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      expect(described_class.refund_for_topic!(topic)).to eq(1)

      expect(balance_of(asker)).to eq(500)
      expect(bounty.reload.state).to eq(IngenicBounty::CANCELLED)

      refund =
        IngenicPointEntry.find_by(
          event: IngenicPointEntry::BOUNTY_REFUND,
          subject_id: bounty.id,
        )
      expect(refund.points).to eq(100)
      expect(refund.reason).to eq(I18n.t("ingenic.bounties.topic_removed_reason"))
    end

    it "leaves a settled offer alone" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      described_class.accept!(bounty: bounty, post: answer_on(topic), by: asker)

      expect(described_class.refund_for_topic!(topic)).to eq(0)

      expect(bounty.reload.state).to eq(IngenicBounty::ACCEPTED)
      expect(IngenicPointEntry.where(event: IngenicPointEntry::BOUNTY_REFUND)).to be_empty
    end

    it "says so and writes nothing for a topic with no offer" do
      expect(described_class.refund_for_topic!(other_topic)).to eq(0)
      expect(balance_of(asker)).to eq(500)
    end

    it "does nothing without a topic" do
      expect(described_class.refund_for_topic!(nil)).to eq(0)
    end

    # Not held behind the switch, for the same reason the expiry job is not: a
    # setting must never be a way to keep points a member set aside while it was
    # on.
    it "gives the points back while bounties are switched off" do
      described_class.open!(topic: topic, user: asker, points: 100)
      SiteSetting.ingenic_bounties_enabled = false

      expect(described_class.refund_for_topic!(topic)).to eq(1)
      expect(balance_of(asker)).to eq(500)
    end
  end

  describe "a topic being deleted" do
    # The foreign key cascades, so the rows would go with the topic whether or
    # not anything refunded them — and a row that went without a refund would
    # take the only record of points owed with it. This is that the plugin gets
    # there first.
    it "removes the offer and gives the points back" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      topic.destroy!

      expect(IngenicBounty.where(id: bounty.id)).to be_empty
      expect(balance_of(asker)).to eq(500)

      refund =
        IngenicPointEntry.find_by(
          event: IngenicPointEntry::BOUNTY_REFUND,
          subject_id: bounty.id,
        )
      expect(refund.points).to eq(100)
      expect(refund.user_id).to eq(asker.id)
    end

    # What an answer was worth goes with the question it answered. Nobody is paid
    # a second time, and the answerer keeps what they were already paid.
    it "takes a settled offer with it and pays nobody again" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)
      described_class.accept!(bounty: bounty, post: answer_on(topic), by: asker)

      topic.destroy!

      expect(IngenicBounty.where(id: bounty.id)).to be_empty
      expect(IngenicPointEntry.where(event: IngenicPointEntry::BOUNTY_REFUND)).to be_empty
      expect(balance_of(answerer)).to eq(100)
    end

    it "destroys a topic that never had a bounty" do
      expect { other_topic.destroy! }.not_to raise_error

      expect(IngenicPointEntry.where(event: IngenicPointEntry::BOUNTY_REFUND)).to be_empty
    end

    # A topic in the trash is not a deleted topic: the row is still there, the
    # offer is still the asker's, and the board stops drawing it because the
    # topic is not visible. It ends the way every other offer does, at its
    # deadline.
    it "leaves the offer standing when the topic is only trashed" do
      bounty = described_class.open!(topic: topic, user: asker, points: 100)

      topic.trash!(asker)

      expect(bounty.reload.state).to eq(IngenicBounty::OPEN)
      expect(balance_of(asker)).to eq(400)
    end
  end
end
