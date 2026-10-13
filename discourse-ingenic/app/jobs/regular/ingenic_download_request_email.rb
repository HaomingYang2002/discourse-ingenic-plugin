# frozen_string_literal: true

module Jobs
  # Sends the notification that a download application is waiting.
  #
  # This runs as a job rather than inline with the request so a slow or failing
  # mail server cannot turn "the applicant pressed Apply" into an error page.
  # The application itself is already saved by then, and the admin queue shows
  # it whether or not the mail ever leaves.
  class IngenicDownloadRequestEmail < ::Jobs::Base
    sidekiq_options queue: "critical"

    def execute(args)
      request = IngenicDownloadRequest.find_by(id: args[:request_id])
      return if request.nil?

      to_address = args[:to_address].presence || SiteSetting.ingenic_download_admin_email
      if to_address.blank?
        # Nothing to send to and nowhere to say so, so this is logged and
        # dropped: the request is in the admin queue either way, and retrying a
        # message with no recipient would only fill the log.
        Rails.logger.warn(
          "Ingenic: download request #{request.id} has no notification address; set ingenic_download_admin_email",
        )
        return
      end

      message = IngenicDownloadMailer.request_received(to_address, request)
      Email::Sender.new(message, :ingenic_download_request).send
    end
  end
end
