# frozen_string_literal: true

# One bounty, as the two places that draw one need it: the topic page, where it
# is a banner over the question, and the board, where it is a row in a list of
# what is on offer.
#
# The board needs the topic — a bounty is meaningless without the question it is
# on — and the topic page needs none of it, which is why the topic is here
# rather than in a second serializer. A row that named an amount and nothing to
# answer would be a number with nowhere to go.
class IngenicBountySerializer < ActiveModel::Serializer
  attributes :id,
             :points,
             :state,
             :expires_at,
             :settled_at,
             :accepted_post_id,
             :created_at,
             :can_cancel

  has_one :user, serializer: BasicUserSerializer, embed: :objects
  has_one :topic, serializer: IngenicBountyTopicSerializer, embed: :objects

  # Who was paid, so the settled banner can name them. Null while the offer
  # stands, and null again if the answer or the account behind it is gone by the
  # time somebody reads the topic: the banner then says what was paid without
  # saying to whom, which is what the row still knows.
  has_one :answerer, serializer: BasicUserSerializer, embed: :objects

  # Whether the viewer may withdraw this offer, which is the author or a member
  # of staff. Answered here rather than worked out in the browser, because the
  # browser's answer would be a guess about the server's.
  def can_cancel
    scope.can_cancel_ingenic_bounty?(object)
  end
end
