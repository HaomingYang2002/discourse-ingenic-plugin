# frozen_string_literal: true

class IngenicDownload < ActiveRecord::Base
  self.table_name = "ingenic_downloads"

  KINDS = %w[sdk firmware manual datasheet toolchain example release_notes other].freeze

  validates :name, presence: true
  validates :file_url, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :product_slug, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, released_on: :desc, name: :asc) }

  def external?
    file_url.present? && file_url !~ %r{\A/}
  end
end
