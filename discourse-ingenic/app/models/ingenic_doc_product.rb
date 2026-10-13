# frozen_string_literal: true

class IngenicDocProduct < ActiveRecord::Base
  self.table_name = "ingenic_doc_products"

  SERIES = "series"
  CHIP = "chip"
  KINDS = [SERIES, CHIP].freeze

  belongs_to :parent,
             class_name: "IngenicDocProduct",
             foreign_key: :parent_id,
             optional: true

  has_many :children,
           -> { order(position: :asc, name: :asc) },
           class_name: "IngenicDocProduct",
           foreign_key: :parent_id,
           dependent: :restrict_with_error

  has_many :versions,
           -> { order(position: :asc, released_on: :desc) },
           class_name: "IngenicDocVersion",
           foreign_key: :product_id,
           dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :locale }
  validates :name, presence: true
  validates :locale, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :parent_cannot_be_self_or_descendant
  validate :shape_matches_kind

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :series, -> { where(kind: SERIES) }
  scope :chips, -> { where(kind: CHIP) }

  def series?
    kind == SERIES
  end

  def chip?
    kind == CHIP
  end

  # The chips a reader can pick under this series, in display order.
  def selectable_chips
    children.published.ordered
  end

  def default_version
    versions.where(published: true).detect(&:latest) ||
      versions.where(published: true).first
  end

  private

  def parent_cannot_be_self_or_descendant
    return if parent.nil?
    return errors.add(:parent, "cannot be itself") if parent == self

    ancestor = parent
    while ancestor
      if ancestor == self
        errors.add(:parent, "cannot be a descendant")
        break
      end
      ancestor = ancestor.parent
    end
  end

  # A series is a root and a chip belongs to exactly one series. The database
  # enforces the same shape; this is here so the admin forms report it as a
  # validation error instead of a constraint violation.
  def shape_matches_kind
    if series? && parent_id.present?
      errors.add(:parent_id, "a series cannot have a parent")
    elsif chip? && parent_id.nil?
      errors.add(:parent_id, "a chip must belong to a series")
    elsif chip? && parent && !parent.series?
      errors.add(:parent_id, "a chip must belong to a series, not another chip")
    end
  end
end
