# frozen_string_literal: true

class IngenicDownload < ActiveRecord::Base
  self.table_name = "ingenic_downloads"

  KINDS = %w[sdk firmware manual datasheet toolchain example release_notes other].freeze

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

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :access_level, inclusion: { in: ACCESS_LEVELS }
  validates :product_slug, presence: true
  validate :has_somewhere_to_download_from

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
