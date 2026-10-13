# frozen_string_literal: true

module Jobs
  # Tells an applicant what the team decided.
  #
  # Sent from a job for the same reason as the request notification: approving
  # is a database decision that has already been made and recorded, and it
  # should not be rolled back because an SMTP connection timed out.
  class IngenicDownloadDecisionEmail < ::Jobs::Base
    sidekiq_options queue: "critical"

    def execute(args)
      request = IngenicDownloadRequest.find_by(id: args[:request_id])
      return if request.nil? || request.pending?

      message =
        IngenicDownloadMailer.request_decided(
          request.user.email,
          request,
        )
      Email::Sender.new(message, :ingenic_download_decision, request.user).send
    end
  end
end
