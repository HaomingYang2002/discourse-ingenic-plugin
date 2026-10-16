# frozen_string_literal: true

module Jobs
  # Closes 高分悬赏 offers whose time is up and gives the asker their points back.
  #
  # Hourly rather than to the minute. Nobody is watching the clock on an offer
  # that has already run its fortnight, and the hour of grace costs the asker
  # nothing: their points are in escrow either way, and the refund is the same
  # whether it lands at the deadline or an hour after it.
  #
  # It runs whether or not bounties are still being *offered*. Switching the
  # feature off should stop the forum taking new offers, not strand the points
  # behind the ones already standing — so the guard here is the plugin's own
  # switch and nothing narrower.
  class IngenicBountyExpiry < ::Jobs::Scheduled
    every 1.hour

    def execute(_args)
      return unless SiteSetting.ingenic_enabled

      expired = Ingenic::Bounties.expire_due!

      Rails.logger.info("Ingenic: closed and refunded #{expired} expired bounties") if expired.positive?
    end
  end
end
