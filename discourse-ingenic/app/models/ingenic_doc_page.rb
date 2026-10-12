# frozen_string_literal: true

class IngenicDocPage < ActiveRecord::Base
  self.table_name = "ingenic_doc_pages"

  belongs_to :version, class_name: "IngenicDocVersion", foreign_key: :version_id
  belongs_to :parent, class_name: "IngenicDocPage", foreign_key: :parent_id, optional: true

  has_many :children,
           -> { order(position: :asc) },
           class_name: "IngenicDocPage",
           foreign_key: :parent_id,
           dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: [:version_id, :locale] }
  validates :title, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc) }

  def depth
    parent ? parent.depth + 1 : 0
  end
end
