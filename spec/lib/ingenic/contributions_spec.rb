# frozen_string_literal: true

require "rails_helper"

describe Ingenic::Contributions do
  fab!(:user) { Fabricate(:user) }
  fab!(:other) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:post) { Fabricate(:post, topic: topic, user: user, post_number: 1) }

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_contributions_enabled = true
    SiteSetting.ingenic_points_exclude_staff = true
  end

  describe "#award" do
    it "prices a topic and an answer" do
      expect(
        described_class.award(user: user, event: "topic_created", subject: post),
      ).to be_present
      reply = Fabricate(:post, topic: topic, user: user)

      described_class.award(user: user, event: "post_created", subject: reply)

      expect(described_class.weekly_for(user)).to eq(7)
    end

    it "adds the category bonus once, on what was written" do
      technical = Fabricate(:category, slug: "technical-discussions")
      topic = Fabricate(:topic, user: user, category: technical)
      post = Fabricate(:post, topic: topic, user: user, post_number: 1)

      described_class.award(
        user: user,
        event: "topic_created",
        subject: post,
      )

      expect(described_class.weekly_for(user)).to eq(8)
    end

    it "does not pay the category bonus per like" do
      open_source = Fabricate(:category, slug: "open-source")
      post = Fabricate(:post, user: user, topic: Fabricate(:topic, category: open_source))
      action =
        PostAction.create!(
          post: post,
          user: other,
          post_action_type_id: PostActionType.types[:like],
        )

      described_class.award(user: user, event: "like_received", subject: action)

      expect(described_class.weekly_for(user)).to eq(1)
    end

    it "writes the same award once" do
      described_class.award(user: user, event: "topic_created", subject: post)
      described_class.award(user: user, event: "topic_created", subject: post)

      expect(IngenicContribution.where(user: user).count).to eq(1)
    end

    it "stops paying likes after the daily cap" do
      12.times do
        reply = Fabricate(:post, user: user)
        action =
          PostAction.create!(
            post: reply,
            user: other,
            post_action_type_id: PostActionType.types[:like],
          )
        described_class.award(user: user, event: "like_received", subject: action)
      end

      expect(
        IngenicContribution.where(user: user, event: "like_received").count,
      ).to eq(described_class::LIKE_DAILY_CAP)
    end

    it "leaves staff out while the setting says so" do
      admin = Fabricate(:admin)

      expect(
        described_class.award(user: admin, event: "topic_created", subject: post),
      ).to be_nil
      expect(IngenicContribution.where(user: admin)).to be_empty
    end

    it "records nothing while the score is switched off" do
      SiteSetting.ingenic_contributions_enabled = false

      expect(
        described_class.award(user: user, event: "topic_created", subject: post),
      ).to be_nil
    end
  end

  describe "#visit" do
    it "pays once a day" do
      described_class.visit(user)
      described_class.visit(user)

      expect(IngenicContribution.where(user: user, event: "daily_visit").count).to eq(1)
    end

    it "stops after the weekly cap" do
      monday = Time.zone.now.beginning_of_week + 9.hours

      # All seven days of one week: the cap, not the calendar, is what stops it.
      7.times do |day|
        described_class.visit(user, at: monday + day.days)
      end

      expect(
        IngenicContribution.where(user: user, event: "daily_visit").count,
      ).to eq(described_class::VISIT_WEEKLY_CAP)
    end
  end

  describe "#remove_subject" do
    it "takes back a post's award and the likes on it" do
      described_class.award(user: user, event: "topic_created", subject: post)
      action =
        PostAction.create!(
          post: post,
          user: other,
          post_action_type_id: PostActionType.types[:like],
        )
      described_class.award(user: user, event: "like_received", subject: action)

      described_class.remove_subject(post)

      expect(IngenicContribution.where(user: user)).to be_empty
    end

    it "can take back one event and leave the others" do
      described_class.award(user: user, event: "post_created", subject: post)
      described_class.award(user: user, event: "solution_accepted", subject: post)

      described_class.remove_subject(post, event: "solution_accepted")

      expect(IngenicContribution.where(user: user).pluck(:event)).to eq(["post_created"])
    end
  end
end
