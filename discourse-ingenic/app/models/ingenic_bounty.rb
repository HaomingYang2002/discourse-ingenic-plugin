# frozen_string_literal: true

# 高分悬赏: one member's offer, standing on one topic.
#
# A bounty is the asker's own points, not the forum's. They set them aside when
# they open it and they are paid to whoever writes the answer the asker accepts
# — in full, with no cut, because the forum is keeping the books here rather
# than taking a side.
#
# The money lives in the points ledger; this table is the promise about it. What
# that buys is a state a row can only leave once: `open` is the only state with
# anything owed, and settling a bounty moves it out of `open` under a row lock,
# so the same bounty cannot be paid twice however many acceptances arrive at
# once. The partial unique index on `topic_id` is the same idea one level up —
# one standing offer per topic.
class IngenicBounty < ActiveRecord::Base
  self.table_name = "ingenic_bounties"

  OPEN = "open"
  ACCEPTED = "accepted"
  CANCELLED = "cancelled"
  EXPIRED = "expired"

  STATES = [OPEN, ACCEPTED, CANCELLED, EXPIRED].freeze

  belongs_to :topic

  # The member who offered it. A settled bounty is the record of what an answer
  # was worth and stays on the topic after its asker has gone — with the name
  # blanked, which is what makes this optional. A standing one whose asker is
  # deleted is still paid if an answer is accepted, and still expires at its
  # deadline; the refund is then recorded against nobody, there being no account
  # left to hold the points.
  belongs_to :user, optional: true
  belongs_to :accepted_post, class_name: "Post", optional: true
  belongs_to :accepted_by, class_name: "User", optional: true

  # Whoever wrote the accepted answer — the member the points were paid to.
  # Read through the post rather than stored, so it is the author of the answer
  # that is named and not whoever pressed accept: the asker usually does both,
  # but staff can accept on their behalf, and the name a settled bounty has to
  # carry is the one that was paid.
  has_one :answerer, through: :accepted_post, source: :user

  validates :points, numericality: { only_integer: true, greater_than: 0 }
  validates :state, presence: true, inclusion: { in: STATES }
  validates :expires_at, presence: true

  # A friendly mirror of the partial index, for the message rather than for the
  # guarantee: the database is what makes two open bounties on one topic
  # impossible, and this is what turns the second one into a sentence instead of
  # a raised exception.
  validates :topic_id, uniqueness: { conditions: -> { where(state: OPEN) } }, if: :open?

  # Read as "standing". `open` would have been the word — the state is called
  # that — but `open` on a class is `Kernel#open`, and this plugin has already
  # paid for that trap once over in IngenicPointRule.self.for.
  scope :live, -> { where(state: OPEN) }
  scope :settled, -> { where.not(state: OPEN) }

  # Richest first, and oldest first within a price: the board is a list of what
  # is on offer, and two offers of the same size should not shuffle between
  # reads.
  scope :by_value, -> { order(points: :desc, created_at: :asc) }

  def open?
    state == OPEN
  end

  def settled?
    !open?
  end

  # Past its time but not yet dealt with. The expiry job is what closes these,
  # so between the deadline and the next run of that job a bounty is both open
  # and due — which is a state the board and the topic page have to answer for.
  def due?
    open? && expires_at <= Time.zone.now
  end
end
