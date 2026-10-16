# frozen_string_literal: true

# Permission for one account to download one resource.
#
# A grant is a row per person per resource rather than a flag on the user,
# because access here is granted resource by resource: letting someone download
# one chip's SDK says nothing about the next one. Revoking keeps the row and
# clears the permission, so the same account can be let back in without losing
# the history of having been let in before.
class IngenicDownloadGrant < ActiveRecord::Base
  self.table_name = "ingenic_download_grants"

  # Optional for the same reason the application is: the account a grant was
  # written for can be deleted, and the row stays behind as the record that it
  # was granted, with the account blanked. A blanked grant lets nobody in — every
  # lookup for one is made by account id — so what it still says is only that
  # access was given here once.
  belongs_to :user, optional: true
  belongs_to :download, class_name: "IngenicDownload"
  belongs_to :request, class_name: "IngenicDownloadRequest", optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  # One row per account per resource, which the unique index behind this also
  # enforces. Skipped when the account is blank: two deleted accounts that were
  # each granted the same resource leave two rows with nothing in that column,
  # and revoking one of them is still something an administrator may do. The
  # index still refuses a second row for an account that does exist.
  validates :user_id, uniqueness: { scope: :download_id }, allow_nil: true

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.zone.now) }

  # Approving a request and granting access by hand are the same act, so both go
  # through here. Reinstating a revoked grant updates the existing row rather
  # than inserting a second one, which the unique index would refuse anyway.
  def self.issue!(user, download, request: nil, granted_by: nil, expires_at: nil, note: nil)
    grant = find_or_initialize_by(user_id: user.id, download_id: download.id)
    grant.assign_attributes(
      request: request,
      granted_by: granted_by,
      expires_at: expires_at,
      note: note,
      revoked_at: nil,
    )
    grant.save!
    grant
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at.future?)
  end

  def revoke!(actor = nil)
    update!(revoked_at: Time.zone.now, revoked_by: actor)
  end
end
