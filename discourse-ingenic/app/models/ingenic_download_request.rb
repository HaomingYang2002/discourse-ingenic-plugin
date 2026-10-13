# frozen_string_literal: true

# A developer asking for access to a resource they cannot download yet.
#
# The request is the audit trail. Approving one does not delete it or record the
# decision only on the grant, so "who let this account in, when, and on what
# grounds" stays answerable after the grant has been revoked and reissued.
class IngenicDownloadRequest < ActiveRecord::Base
  self.table_name = "ingenic_download_requests"

  PENDING = "pending"
  APPROVED = "approved"
  REJECTED = "rejected"
  STATUSES = [PENDING, APPROVED, REJECTED].freeze

  belongs_to :user
  belongs_to :download, class_name: "IngenicDownload"
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: PENDING) }
  scope :recent, -> { order(created_at: :desc) }

  def pending?
    status == PENDING
  end

  def approved?
    status == APPROVED
  end

  def rejected?
    status == REJECTED
  end

  # Approving is what creates the permission, so the two happen together. A
  # request marked approved with no grant would leave the applicant still
  # locked out and the queue showing nothing left to do.
  def approve!(reviewer, note: nil, expires_at: nil)
    transaction do
      update!(
        status: APPROVED,
        reviewed_by: reviewer,
        reviewed_at: Time.zone.now,
        review_note: note,
      )
      IngenicDownloadGrant.issue!(user, download, request: self, granted_by: reviewer, expires_at: expires_at, note: note)
    end
  end

  def reject!(reviewer, note: nil)
    update!(
      status: REJECTED,
      reviewed_by: reviewer,
      reviewed_at: Time.zone.now,
      review_note: note,
    )
  end
end
