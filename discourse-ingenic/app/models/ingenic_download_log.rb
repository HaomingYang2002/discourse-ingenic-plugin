# frozen_string_literal: true

# One recorded hand-over of a file.
#
# A grant answers "may this account download this"; this answers "who did, and
# when". The Ingenic team asked for the second one specifically — once an
# approval is given it lasts, so the row that proves a download happened is the
# only remaining record that the gated file was collected, and by which account.
#
# Append-only: there is no updated_at, because nothing here is ever edited. The
# resource name and version are copied in rather than read through the
# association, so the log still reads correctly after a resource is renamed or
# withdrawn — a record of what was handed over should not change retroactively.
class IngenicDownloadLog < ActiveRecord::Base
  self.table_name = "ingenic_download_logs"

  belongs_to :user
  belongs_to :download, class_name: "IngenicDownload"

  validates :resource_name, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Called from the delivery endpoint, after the permission check has passed, so
  # a row here means bytes actually left the server.
  #
  # Never raises: a failure to write the record must not turn a download the
  # visitor is entitled to into an error page. The alternative — losing the
  # audit row silently — is the lesser problem, and it is logged.
  def self.record!(user:, download:, request: nil)
    create!(
      user_id: user.id,
      download_id: download.id,
      resource_name: download.name,
      version: download.version,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent&.first(255),
      locale: I18n.locale.to_s,
    )
  rescue StandardError => e
    Rails.logger.warn("Ingenic: could not record download #{download.id} for user #{user.id}: #{e.message}")
    nil
  end
end
