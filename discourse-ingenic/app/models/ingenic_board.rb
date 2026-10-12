# frozen_string_literal: true

class IngenicBoard < ActiveRecord::Base
  self.table_name = "ingenic_boards"

  validates :slug, presence: true, uniqueness: { scope: :locale }
  validates :name, presence: true
  validates :application_url, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }
end
