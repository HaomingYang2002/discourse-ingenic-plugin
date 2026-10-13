# frozen_string_literal: true

require_dependency "email/message_builder"

# Emails the download centre sends.
#
# Bodies and subjects come from locale keys rather than from view templates:
# that is the mechanism `Email::MessageBuilder` already implements for mailers
# whose text lives in `server.yml`, and it avoids a plugin needing its own view
# path appended to ActionMailer.
class IngenicDownloadMailer < ActionMailer::Base
  include Email::BuildEmailHelper

  # To the team, when a developer applies for a gated resource.
  def request_received(to_address, request)
    build_email(
      to_address,
      template: "ingenic_download_request_received",
      applicant_username: request.user.username,
      applicant_name: request.user.name.presence || request.user.username,
      resource_name: request.download.name,
      resource_product: request.download.product_slug,
      resource_version: request.download.version,
      applicant_message: request.message,
      profile_summary: profile_summary(request.user),
      review_url: "#{Discourse.base_url}/admin/plugins/discourse-ingenic/downloads",
    )
  end

  # To the applicant, when the team decides.
  def request_decided(to_address, request)
    build_email(
      to_address,
      template:
        "ingenic_download_request_#{request.approved? ? "approved" : "rejected"}",
      recipient_username: request.user.username,
      resource_name: request.download.name,
      review_note: request.review_note,
      downloads_url: "#{Discourse.base_url}/ingenic/downloads",
    )
  end

  private

  def profile_summary(user)
    profile = IngenicDeveloperProfile.for(user)
    profile&.summary(limit: 4).presence || "-"
  end
end
