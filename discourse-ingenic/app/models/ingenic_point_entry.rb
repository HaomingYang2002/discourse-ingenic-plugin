# frozen_string_literal: true

# One movement of points.
#
# The ledger is the record: every award, every deduction and every reversal is
# a row, nothing is edited, and a member's balance is the sum of theirs. The
# balance table is a cache of this, which is what makes it safe to recompute.
#
# `reason` is written down at the time rather than read back from the rule that
# produced it. Renaming "Replying to one" to "Answering in one" should change
# what the next reply is worth, not what last year's replies say they were.
class IngenicPointEntry < ActiveRecord::Base
  self.table_name = "ingenic_point_entries"

  # Movements that are not one of the earning rules.
  #
  # manual         an administrator adjusting an account, with a note
  # download       a resource unlocked by spending points
  # reversal       an award taken back because the post or the like behind it
  #                went away
  # bounty         points set aside by opening a 高分悬赏 — negative, and on the
  #                asker: the escrow leaves their balance so it cannot be spent
  #                elsewhere while the offer stands
  # bounty_award   the escrow released to the answerer
  # bounty_refund  the escrow returned to the asker, because they withdrew the
  #                offer or because nobody answered in time
  #
  # The three bounty movements all carry the bounty row as their subject, which
  # is what makes each of them recordable exactly once: the same release cannot
  # be written twice, and neither can the refund that follows a withdrawal.
  MANUAL = "manual"
  DOWNLOAD = "download"
  REVERSAL = "reversal"
  BOUNTY = "bounty"
  BOUNTY_AWARD = "bounty_award"
  BOUNTY_REFUND = "bounty_refund"

  belongs_to :user
  belongs_to :awarded_by, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :points, numericality: { only_integer: true }
  validates :event, presence: true
  validates :reason, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :for_subject, ->(subject) {
    where(subject_type: subject.class.base_class.name, subject_id: subject.id)
  }

  # Whether this entry has already been taken back, so a reversal cannot be
  # recorded twice by a second event about the same post.
  def reversed?
    self.class.where(event: REVERSAL, subject_type: self.class.name, subject_id: id).exists?
  end

  def award?
    points.positive? && event != REVERSAL
  end
end
