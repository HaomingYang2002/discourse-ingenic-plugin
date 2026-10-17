# frozen_string_literal: true

# A classification a resource is filed under: SDK release, datasheet, product
# brief, version notes.
#
# This used to be a constant in the model. It is a table because it is Ingenic's
# own vocabulary rather than the plugin's — the Chinese forum's own filter list
# spells one chip CP020 where everything else says CW020 — and needing a deploy
# per rename is the wrong price for a wording change.
class IngenicDownloadCategory < ActiveRecord::Base
  self.table_name = "ingenic_download_categories"

  # Nullify rather than restrict: retiring a category should not be blocked by
  # the resources filed under it, and should not silently delete them either.
  # The listing shows them as unfiled until someone reclassifies them.
  has_many :downloads,
           class_name: "IngenicDownload",
           foreign_key: :category_id,
           dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :locale }

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  def download_count
    downloads.count
  end
end
