# frozen_string_literal: true

# One line of the contribution score.
#
# Separate from `IngenicPointEntry` on purpose: points are spendable, this is a
# ranking. Nothing writes to a balance from here, and deleting a row lowers a
# member's contribution without touching what they own.
class IngenicContribution < ActiveRecord::Base
  self.table_name = "ingenic_contributions"

  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  validates :points, numericality: { only_integer: true }
  validates :event, presence: true
  validates :on_date, presence: true

  scope :since, ->(time) { where(created_at: time..) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
