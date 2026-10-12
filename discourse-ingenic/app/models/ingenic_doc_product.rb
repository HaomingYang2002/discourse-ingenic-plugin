# frozen_string_literal: true

class IngenicDocProduct < ActiveRecord::Base
  self.table_name = "ingenic_doc_products"

  has_many :versions,
           -> { order(position: :asc, released_on: :desc) },
           class_name: "IngenicDocVersion",
           foreign_key: :product_id,
           dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :locale }
  validates :name, presence: true
  validates :locale, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  def default_version
    versions.where(published: true).detect(&:latest) ||
      versions.where(published: true).first
  end
end
