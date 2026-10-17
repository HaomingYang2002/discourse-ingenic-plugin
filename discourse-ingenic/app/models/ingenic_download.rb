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

  # The catalogue's two top-level lines. A chip resource belongs to a part
  # number; an algorithm is offered across parts and has no chip of its own, so
  # it is not filed under one. Keeping the family here rather than as another
  # node in the product tree keeps the tree about chips.
  FAMILY_CHIP = "chip"
  FAMILY_ALGORITHM = "algorithm"
  FAMILIES = [FAMILY_CHIP, FAMILY_ALGORITHM].freeze

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
  validates :family, inclusion: { in: FAMILIES }
  # A row cannot be both untethered and filed under a part number. Clearing the
  # slug here makes the family the single source of truth even for a row that
  # was switched from chip to algorithm after it had one.
  before_validation { self.product_slug = nil if algorithm? }
  # Only a chip resource needs a part number. An algorithm that runs on several
  # chips is not filed under one, and requiring a slug would either invent a
  # false attachment or leave algorithms out of the catalogue.
  validates :product_slug, presence: true, if: :chip?
  validate :has_somewhere_to_download_from
  # Not signed, for the same reason a point rule is not: a negative price is a
  # charge for arriving, and a member who cannot afford one would be refused a
  # file for having done nothing.
  validates :point_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, released_on: :desc, name: :asc) }
  scope :gated, -> { where.not(access_level: LOGIN_ONLY) }
  scope :in_family, ->(family) { where(family: family) }

  def chip?
    family == FAMILY_CHIP
  end

  def algorithm?
    family == FAMILY_ALGORITHM
  end

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
