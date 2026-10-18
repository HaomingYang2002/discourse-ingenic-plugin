# frozen_string_literal: true

module Jobs
  # Puts 高赞 on topics whose posts have collected enough likes, and takes it
  # back when they no longer have them.
  #
  # Scheduled rather than hung off the like event: a topic crosses the line on
  # somebody else's click, and the number that matters is the total across the
  # topic's posts, which no single event knows. A periodic pass also notices a
  # like being removed — a deleted post should take its likes with it, and the
  # tag should follow.
  #
  # Six hours is frequent enough that a good answer wears the tag the same day,
  # and rare enough that a forum of any size is not re-counted hourly for a
  # badge that changes slowly.
  class IngenicHighLikeTag < ::Jobs::Scheduled
    every 6.hours

    def execute(_args)
      return unless SiteSetting.ingenic_enabled && SiteSetting.ingenic_high_like_enabled

      changed =
        Ingenic::StatusTags.refresh_high_like!(
          threshold: SiteSetting.ingenic_high_like_threshold,
        )

      Rails.logger.info("Ingenic: 高赞 changed on #{changed} topics") if changed.positive?
    end
  end
end
