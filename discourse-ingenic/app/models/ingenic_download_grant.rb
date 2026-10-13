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

  belongs_to :user
  belongs_to :download, class_name: "IngenicDownload"
  belongs_to :request, class_name: "IngenicDownloadRequest", optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  validates :user_id, uniqueness: { scope: :download_id }

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
