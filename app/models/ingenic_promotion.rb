# frozen_string_literal: true

# One promotional slot on the homepage.
#
# The Chinese forum runs three of these — GitHub, the download centre and the
# documentation centre — all with the same shape, so what looks like three
# features is one list with three rows.
#
# An entry with no dates runs until it is unpublished. An entry with dates shows
# only inside them, which is what makes a scheduled campaign possible: it can go
# up on a Monday and take itself down on a Friday without anyone remembering.
class IngenicPromotion < ActiveRecord::Base
  self.table_name = "ingenic_promotions"

  validates :title, presence: true
  validates :locale, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  scope :live,
        -> {
          now = Time.zone.now
          published
            .where("starts_at IS NULL OR starts_at <= ?", now)
            .where("ends_at IS NULL OR ends_at >= ?", now)
        }

  def live?
    published? &&
      (starts_at.nil? || starts_at <= Time.zone.now) &&
      (ends_at.nil? || ends_at >= Time.zone.now)
  end

  # Whether the button leaves the forum. Held as a column rather than inferred
  # from the URL, because an admin may want a same-site link opened in a new tab.
  def external?
    button_external
  end
end
