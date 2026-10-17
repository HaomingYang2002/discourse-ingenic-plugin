# frozen_string_literal: true

# The little of a topic a bounty needs to be shown without it.
#
# Not TopicListSerializer and not TopicViewSerializer: both of those are answers
# to "draw me a topic", and this is a line under an amount on a board. What is
# here is what a card has room for — a title to click, a section to name, and
# whether an answer has already been accepted, so a settled topic is not
# advertised as still waiting for one.
class IngenicBountyTopicSerializer < ActiveModel::Serializer
  attributes :id, :title, :slug, :posts_count, :category_id, :closed, :url

  # Built here rather than in the browser, so that the two sides cannot disagree
  # about the shape of a topic address — `Topic.relative_url` is Discourse's own
  # answer to that, including its handling of a slug that was never generated.
  def url
    object.relative_url
  end
end
