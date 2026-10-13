# frozen_string_literal: true

class IngenicDownload < ActiveRecord::Base
  self.table_name = "ingenic_downloads"

  # The three tiers, in the order the Ingenic team describes them.
  #
  # public_login        signed in is enough
  # login_form          signed in, with developer information on file
  # login_form_request  signed in, information on file, and an approved request
  LOGIN_ONLY = "public_login"
  FORM_REQUIRED = "login_form"
  APPROVAL_REQUIRED = "login_form_request"
  ACCESS_LEVELS = [LOGIN_ONLY, FORM_REQUIRED, APPROVAL_REQUIRED].freeze

  has_many :requests,
           class_name: "IngenicDownloadRequest",
           foreign_key: :download_id,
           dependent: :destroy
  has_many :grants,
           class_name: "IngenicDownloadGrant",
           foreign_key: :download_id,
           dependent: :destroy
  has_many :logs,
           class_name: "IngenicDownloadLog",
           foreign_key: :download_id,
           dependent: :destroy

  # Optional on purpose. The classification is Ingenic's own list and they can
  # retire an entry, which leaves the resources filed under it unfiled rather
  # than deleted; a resource in that state has to remain valid so it can be
  # reclassified instead of refusing to save.
  belongs_to :category, class_name: "IngenicDownloadCategory", optional: true

  validates :name, presence: true
  validates :access_level, inclusion: { in: ACCESS_LEVELS }
  validates :product_slug, presence: true
  validate :has_somewhere_to_download_from
  # Not signed, for the same reason a point rule is not: a negative price is a
  # charge for arriving, and a member who cannot afford one would be refused a
  # file for having done nothing.
  validates :point_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, released_on: :desc, name: :asc) }
  scope :gated, -> { where.not(access_level: LOGIN_ONLY) }

  def login_only?
    access_level == LOGIN_ONLY
  end

  def form_required?
    access_level == FORM_REQUIRED
  end

  def approval_required?
    access_level == APPROVAL_REQUIRED
  end

  # Whether this resource costs points to unlock. An addition to the access
  # levels rather than a fourth one: the levels decide who may have a file, and
  # this decides what it costs once they may.
  def costs_points?
    point_cost.positive?
  end

  # What the listing prints on the card. Null for a resource whose category has
  # been retired or was never set, which the callers treat as "show no label"
  # rather than as an error.
  def category_name
    category&.name
  end

  # True when the bytes live on this server rather than behind a URL, which is
  # the only case the plugin can actually gate.
  def stored?
    storage_path.present?
  end

  def external?
    !stored? && file_url.present? && file_url !~ %r{\A/}
  end

  private

  def has_somewhere_to_download_from
    return if file_url.present? || storage_path.present?

    errors.add(:base, "a resource needs either a file URL or an uploaded file")
  end
end
