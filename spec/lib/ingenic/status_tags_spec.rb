# frozen_string_literal: true

require "rails_helper"

describe Ingenic::StatusTags do
  fab!(:topic) { Fabricate(:topic) }
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  def names(topic)
    topic.reload.tags.pluck(:name)
  end

  it "puts 已解决 on the topic and takes it off again" do
    described_class.solved!(topic, solved: true)
    expect(names(topic)).to include("已解决")

    described_class.solved!(topic, solved: false)
    expect(names(topic)).not_to include("已解决")
  end

  it "is idempotent about a tag that is already there" do
    2.times { described_class.solved!(topic, solved: true) }

    expect(names(topic).count("已解决")).to eq(1)
  end

  describe ".refresh_high_like!" do
    def like(post)
      PostAction.create!(
        post: post,
        user: Fabricate(:user),
        post_action_type_id: PostActionType.types[:like],
      )
    end

    it "adds 高赞 when the topic reaches the threshold" do
      3.times { like(first_post) }

      expect(described_class.refresh_high_like!(threshold: 3)).to eq(1)
      expect(names(topic)).to include("高赞")
      expect(topic.reload.custom_fields[Ingenic::StatusTags::HOT_FIELD]).to be_truthy
    end

    it "leaves a topic short of the threshold alone" do
      2.times { like(first_post) }

      expect(described_class.refresh_high_like!(threshold: 3)).to eq(0)
      expect(names(topic)).not_to include("高赞")
    end

    it "takes back a tag it applied when the likes go away" do
      like(first_post)
      described_class.refresh_high_like!(threshold: 1)
      expect(names(topic)).to include("高赞")

      PostAction.where(post: first_post).delete_all

      expect(described_class.refresh_high_like!(threshold: 1)).to eq(1)
      expect(names(topic)).not_to include("高赞")
      expect(topic.reload.custom_fields[Ingenic::StatusTags::HOT_FIELD]).to be_nil
    end

    it "does not remove 高赞 that staff applied by hand" do
      topic.tags << Tag.find_by!(name: "高赞")

      described_class.refresh_high_like!(threshold: 20)

      expect(names(topic)).to include("高赞")
    end

    it "does nothing when the threshold is below one" do
      expect(described_class.refresh_high_like!(threshold: 0)).to eq(0)
    end
  end
end
