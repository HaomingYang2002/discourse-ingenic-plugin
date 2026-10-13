# frozen_string_literal: true

class IngenicDocProduct < ActiveRecord::Base
  self.table_name = "ingenic_doc_products"

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
  validate :parent_cannot_be_self_or_descendant

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

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
end
