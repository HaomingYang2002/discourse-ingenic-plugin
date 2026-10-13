# frozen_string_literal: true

module Ingenic
  # The official identity badge: the mark a group's members wear beside their
  # username.
  #
  # Discourse already draws a group's flair beside a name and already knows how
  # to give a member that flair — but only as a side effect of the group being
  # flagged as their *primary* group, which also rewrites their title and
  # changes which group the site presents them as belonging to. That is a large
  # decision to make for the sake of a badge, so `ingenic_official_groups` names
  # the groups that hand out a badge on membership alone, and the group stays a
  # group.
  #
  # What this deliberately does not do:
  #
  # * It never takes away a badge the member chose for themselves from a group
  #   that is not on the list. Being added to an official group is not a reason
  #   to lose the badge you picked, and Discourse's own preferences page already
  #   offers every badge a member is entitled to — so the official badge is
  #   something they can choose, not something done to them.
  # * It never invents a badge. A listed group with no flair configured grants
  #   nothing, which is what lets the list be written before the artwork exists.
  # * It never touches a group that is not on the list, not even to clear it.
  module OfficialFlair
    module_function

    # The list, resolved once for a batch.
    #
    # A batch can cover a whole group, and the question "which groups are
    # official" has the same answer for every member of it. Asking per member
    # would be a round trip to a table with a few dozen rows in it, thousands of
    # times over.
    #
    # `retired` rides along because it is the same kind of fact — a group id
    # this plugin is still entitled to take a badge back from, though it is no
    # longer named by the setting — and because it is only known at the moment
    # the batch is built.
    class Roster
      def initialize(groups:, retired: [])
        @groups = groups
        @ids = groups.map(&:id)
        @retired = retired
      end

      # The badge this member should be wearing, or nil for none.
      #
      # The list is ordered and the first match wins, so naming two groups is a
      # way of saying which badge outranks which rather than leaving it to
      # chance.
      #
      # Membership is read straight from the join table rather than through
      # `user.group_ids`, which may have been loaded before the membership
      # changed: the removal event fires after the row is gone, and an
      # association read a moment earlier would still insist the member is in.
      def badge_for(user)
        member_of = GroupUser.where(user_id: user.id).pluck(:group_id)
        @groups.detect { |group| group.flair_url.present? && member_of.include?(group.id) }
      end

      # Whether this badge is one the list is entitled to take back. A badge
      # from anywhere else was the member's own choice, and is left alone.
      def handed_out?(group_id)
        @ids.include?(group_id) || @retired.include?(group_id)
      end

      # A roster with nothing on it can neither grant a badge nor take one back,
      # so there is nothing to ask it about. Worth knowing before a batch loads
      # the members it was only going to skip: for a forum with no official
      # groups, that is all of them.
      def empty?
        @groups.empty? && @retired.empty?
      end
    end

    # Brings one member into line with the list. Pass a roster to hold the list
    # still across a batch; without one it is read here, which is what a single
    # membership change wants.
    def sync_user(user, roster = nil)
      return if user.blank?

      roster ||= self.roster
      return if roster.empty?

      target = roster.badge_for(user)
      current = user.flair_group_id
      return if current == target&.id
      return if current.present? && !roster.handed_out?(current)

      write(user, target&.id)
    end

    # Brings every member of one group into line, for when the group's own flair
    # changed rather than its membership.
    def sync_group(group)
      return if group.blank?
      return unless official_group_ids.include?(group.id)

      sync_users(GroupUser.where(group_id: group.id).pluck(:user_id))
    end

    # Brings every member of every listed group into line. This is the only way
    # membership and entitlement can fall out of step without anyone joining or
    # leaving anything, which is why the list changing is what calls it.
    def sync_all(retired: [])
      ids = (official_group_ids + retired).uniq
      return if ids.empty?

      sync_users(GroupUser.where(group_id: ids).pluck(:user_id), retired: retired)
    end

    def sync_users(user_ids, retired: [])
      return if user_ids.empty?

      roster = self.roster(retired: retired)
      return if roster.empty?

      User.where(id: user_ids.uniq).find_each { |user| sync_user(user, roster) }
    end

    def roster(retired: [])
      Roster.new(groups: official_groups, retired: retired)
    end

    # A group reaching this event has changed in some way, and almost none of
    # those ways concern a badge. Both branches are queued rather than run here:
    # an admin saving a group should not wait on a group's worth of accounts
    # being written to, and the eventual outcome is the same either way.
    def after_group_change(group)
      return if group.blank?

      if group.saved_change_to_name?
        # A group can stop being official by being renamed out from under the
        # list, which no setting change announces. Its members are checked with
        # its id treated as retired so the badge goes with the name.
        Jobs.enqueue(:ingenic_official_flair_sync, retired: [group.id])
      elsif flair_gained_or_lost?(group)
        Jobs.enqueue(:ingenic_official_flair_sync, group_id: group.id)
      end
    end

    # The list itself changed: a group that has just been named has members who
    # should be wearing its badge by now, and a group that has just been dropped
    # has members still wearing one that is no longer its to hand out.
    def after_list_change(previous_value)
      Jobs.enqueue(:ingenic_official_flair_sync, retired: group_ids_for(previous_value))
    end

    # Whether a save to a group is one that decides who wears a badge at all.
    #
    # The two fields are the ones `Group#flair_type` reads. The colours are not
    # here on purpose: recolouring a badge changes how it looks to everyone
    # already wearing it and nothing about who wears it.
    #
    # This matters because the event fires for every change to a group,
    # membership changes included. A group with thousands of members must not be
    # re-checked because somebody edited its description.
    def flair_gained_or_lost?(group)
      group.saved_change_to_flair_icon? || group.saved_change_to_flair_upload_id?
    end

    # The groups the setting names, in the order it names them, with the ones
    # that do not exist simply absent.
    def official_groups
      names = names_in(SiteSetting.ingenic_official_groups)
      return [] if names.empty?

      found = Group.where("LOWER(groups.name) IN (?)", names).includes(:flair_upload).to_a
      names.filter_map { |name| found.find { |group| group.name.downcase == name } }
    end

    def official_group_ids
      official_groups.map(&:id)
    end

    # Group names as a stored list holds them. Forgiving about case and spacing,
    # because a group is named `T Series` on the group's own page and an admin
    # typing it into the setting has no way to know whether a stray capital
    # matters — and it does not.
    def names_in(raw)
      list = raw.is_a?(Array) ? raw : raw.to_s.split("|")
      list.map { |name| name.to_s.strip.downcase }.reject(&:empty?).uniq
    end

    # The group ids a stored list refers to, for the case where only the stored
    # value is left: the setting has already been replaced by the time the
    # change is acted on, so its previous names have to be resolved before the
    # members wearing those badges can be found.
    def group_ids_for(raw)
      names = names_in(raw)
      return [] if names.empty?

      Group.where("LOWER(groups.name) IN (?)", names).pluck(:id)
    end

    # `update_all` rather than `update`, the same way core's own group code
    # writes a flair: it keeps the write out of the callbacks that reconcile a
    # member's flair with their primary group, which would otherwise decide this
    # question a second time and differently.
    def write(user, group_id)
      User.where(id: user.id).update_all(flair_group_id: group_id)
      user.flair_group_id = group_id
    end
  end
end
