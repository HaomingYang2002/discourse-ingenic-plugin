# frozen_string_literal: true

module Jobs
  # Hands out, moves and takes back the official identity badge for a group's
  # worth of members at once.
  #
  # Queued rather than run where the change happened, because the changes that
  # reach it are the ones an admin makes in a form — saving the list of official
  # groups, uploading a badge, renaming a group — and none of them should wait
  # on one write per member of the group before the form returns.
  #
  # The three ways in are one job rather than three because they differ only in
  # how much they cover, and the policy already knows how to answer for any of
  # them.
  class IngenicOfficialFlairSync < ::Jobs::Base
    sidekiq_options queue: "low"

    def execute(args)
      if (group_id = args[:group_id].presence)
        group = Group.find_by(id: group_id)
        return if group.nil?

        Ingenic::OfficialFlair.sync_group(group)
      else
        Ingenic::OfficialFlair.sync_all(retired: Array(args[:retired]).map(&:to_i))
      end
    end
  end
end
