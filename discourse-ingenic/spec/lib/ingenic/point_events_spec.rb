# frozen_string_literal: true

require "rails_helper"

describe Ingenic::PointEvents do
  fab!(:user) { Fabricate(:user) }
  fab!(:liker) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: user, post_number: 1) }

  before { SiteSetting.ingenic_points_enabled = true }

  def balance_for(account)
    IngenicPointBalance.total_for(account)
  end

  def awarded(event)
    IngenicPointEntry.exists?(user_id: user.id, event: event)
  end

  describe ".post_created" do
    it "pays for opening a discussion" do
      described_class.post_created(first_post)

      expect(awarded(IngenicPointRule::TOPIC_CREATED)).to eq(true)
      expect(balance_for(user)).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED))
    end

    it "pays for a reply at the reply rate" do
      reply = Fabricate(:post, topic: topic, user: user, post_number: 2)

      described_class.post_created(reply)

      expect(awarded(IngenicPointRule::POST_CREATED)).to eq(true)
      expect(balance_for(user)).to eq(IngenicPointRule.amount_for(IngenicPointRule::POST_CREATED))
    end

    it "pays once when both topic_created and post_created fire for one post" do
      described_class.post_created(first_post)
      described_class.post_created(first_post)

      expect(balance_for(user)).to eq(IngenicPointRule.amount_for(IngenicPointRule::TOPIC_CREATED))
    end

    it "pays nothing for a private message" do
      post = Fabricate(:private_message_post, user: user)

      described_class.post_created(post)

      expect(balance_for(user)).to eq(0)
    end

    it "pays nothing for a whisper" do
      post = Fabricate(:post, topic: topic, user: user, post_number: 2, post_type: Post.types[:whisper])

      described_class.post_created(post)

      expect(balance_for(user)).to eq(0)
    end

    it "pays nothing for a bot's post" do
      # `User#bot?` is `!human?`, and `human?` asks whether the id is a real
      # one — so a bot is an account with no member behind it, which is what
      # Discourse's own system account is. There is no `human` attribute to
      # fabricate.
      bot = Discourse.system_user
      post = Fabricate(:post, topic: topic, user: bot, post_number: 2)

      described_class.post_created(post)

      expect(balance_for(bot)).to eq(0)
    end

    it "pays nothing for a post with no author to pay" do
      post = Fabricate(:post, topic: topic, user: user, post_number: 2)
      # Stubbed rather than nulled in the database: posts.user_id is not
      # nullable, so the only way a handler meets this is a record built in
      # memory or an association that has gone.
      allow(post).to receive(:user).and_return(nil)

      expect { described_class.post_created(post) }.not_to raise_error
      expect(balance_for(user)).to eq(0)
    end

    context "with staff left out" do
      it "pays nothing to an administrator" do
        admin = Fabricate(:admin)
        post = Fabricate(:post, topic: topic, user: admin, post_number: 2)

        described_class.post_created(post)

        expect(balance_for(admin)).to eq(0)
      end

      it "pays a moderator when the setting is off" do
        SiteSetting.ingenic_points_exclude_staff = false
        moderator = Fabricate(:moderator)
        post = Fabricate(:post, topic: topic, user: moderator, post_number: 2)

        described_class.post_created(post)

        expect(balance_for(moderator)).to eq(
          IngenicPointRule.amount_for(IngenicPointRule::POST_CREATED),
        )
      end
    end
  end

  describe ".post_destroyed" do
    it "takes back what the post earned" do
      described_class.post_created(first_post)
      expect(balance_for(user)).to be > 0

      described_class.post_destroyed(first_post)

      expect(balance_for(user)).to eq(0)
    end

    it "does nothing for a post that never earned anything" do
      post = Fabricate(:post, topic: topic, user: user, post_number: 2)

      expect { described_class.post_destroyed(post) }.not_to raise_error
      expect(balance_for(user)).to eq(0)
    end
  end

  describe ".like_created" do
    fab!(:like) do
      PostAction.create!(
        post: first_post,
        user: liker,
        post_action_type_id: PostActionType.types[:like],
      )
    end

    it "pays the author of the post, not the account that liked it" do
      described_class.like_created(like)

      expect(balance_for(user)).to eq(IngenicPointRule.amount_for(IngenicPointRule::LIKE_RECEIVED))
      expect(balance_for(liker)).to eq(0)
    end

    it "pays the author when the like came from a member of staff" do
      from_staff =
        PostAction.create!(
          post: first_post,
          user: Fabricate(:moderator),
          post_action_type_id: PostActionType.types[:like],
        )

      described_class.like_created(from_staff)

      expect(balance_for(user)).to eq(IngenicPointRule.amount_for(IngenicPointRule::LIKE_RECEIVED))
    end

    it "pays once however many times the same like arrives" do
      2.times { described_class.like_created(like) }

      expect(balance_for(user)).to eq(IngenicPointRule.amount_for(IngenicPointRule::LIKE_RECEIVED))
    end

    it "pays nothing for a like on a private message" do
      post = Fabricate(:private_message_post, user: user)
      on_private =
        PostAction.create!(
          post: post,
          user: liker,
          post_action_type_id: PostActionType.types[:like],
        )

      described_class.like_created(on_private)

      expect(balance_for(user)).to eq(0)
    end
  end

  describe ".like_destroyed" do
    it "takes back what the like earned" do
      like =
        PostAction.create!(
          post: first_post,
          user: liker,
          post_action_type_id: PostActionType.types[:like],
        )
      described_class.like_created(like)

      described_class.like_destroyed(like)

      expect(balance_for(user)).to eq(0)
    end
  end

  describe ".solution_accepted" do
    it "pays for an accepted answer" do
      answer = Fabricate(:post, topic: topic, user: user, post_number: 2)

      described_class.solution_accepted(answer)

      expect(balance_for(user)).to eq(
        IngenicPointRule.amount_for(IngenicPointRule::SOLUTION_ACCEPTED),
      )
    end

    it "takes it back when the answer is unmarked" do
      answer = Fabricate(:post, topic: topic, user: user, post_number: 2)
      described_class.solution_accepted(answer)

      described_class.solution_unaccepted(answer)

      expect(balance_for(user)).to eq(0)
    end
  end

  describe "a handler that fails" do
    it "writes to the log instead of failing the action the member took" do
      allow(Ingenic::Points).to receive(:award).and_raise(StandardError.new("table is gone"))

      expect { described_class.post_created(first_post) }.not_to raise_error
    end

    it "does not stop a deletion from completing" do
      allow(Ingenic::Points).to receive(:reverse_subject).and_raise(StandardError.new("gone"))

      expect { described_class.post_destroyed(first_post) }.not_to raise_error
    end
  end
end
