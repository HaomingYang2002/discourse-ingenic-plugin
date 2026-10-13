# frozen_string_literal: true

module Ingenic
  # The points ledger: what a member has earned by contributing, and what they
  # have spent.
  #
  # Every movement goes through here, and every movement is one row in
  # `ingenic_point_entries` with the balance table moved by the same amount in
  # the same transaction. Nothing edits an entry, so a balance can always be
  # argued from the rows behind it — and recomputed from them, which
  # `rebuild!` does.
  #
  # Two rules the rest of the plugin relies on:
  #
  # * A movement is recorded once. An award carries the thing it is for, and the
  #   unique index on the entry is what makes a duplicate event produce nothing
  #   rather than a second helping.
  # * Nothing here is allowed to fail a forum action. The caller that hooks into
  #   posting rescues everything, because a reply must not be refused because
  #   the points table is having a bad day.
  module Points
    module_function

    def enabled?
      SiteSetting.ingenic_points_enabled
    end

    def total_for(user)
      IngenicPointBalance.total_for(user)
    end

    # Records one award for one thing that happened.
    #
    # Returns the entry, or nil when there is nothing to record: no rule for the
    # action, a rule priced at nothing, points switched off, or — the ordinary
    # case when an event fires about something already rewarded — an entry for
    # this exact thing that is already in the ledger.
    def award(user:, event:, subject: nil, reason: nil)
      return if user.nil? || !enabled?

      rule = IngenicPointRule.for(event)
      return if rule.nil? || rule.points.zero?

      record(
        user: user,
        points: rule.points,
        event: rule.event,
        reason: reason.presence || rule.label,
        subject: subject,
      )
    end

    # Takes back an award because the thing it was for went away.
    #
    # Written as its own movement rather than by removing the award: the ledger
    # says what happened, and what happened is that points were given and then
    # taken back. Nothing is written when there is nothing to take back, which
    # is the ordinary case — a post that earned nothing, on a forum where the
    # rule is retired.
    def reverse(entry, reason:, by: nil)
      return if entry.nil? || entry.points.zero? || entry.event == IngenicPointEntry::REVERSAL
      return if entry.reversed?

      record(
        user: entry.user,
        points: -entry.points,
        event: IngenicPointEntry::REVERSAL,
        reason: reason,
        subject: entry,
        by: by,
      )
    end

    # Everything a subject ever earned, taken back. What a deleted post wants:
    # whichever rule it was rewarded under, and without the caller having to
    # know which.
    def reverse_subject(subject, reason:, by: nil)
      return if subject.nil?

      IngenicPointEntry
        .for_subject(subject)
        .where.not(event: IngenicPointEntry::REVERSAL)
        .find_each { |entry| reverse(entry, reason: reason, by: by) }
    end

    # Takes points off an account for something it is buying.
    #
    # Answers rather than raises, because the caller is a download and "you have
    # not got enough" is a state to show, not an error page:
    #
    #   :spent        the points are gone and the thing is theirs
    #   :already      it was bought before, so nothing more is owed
    #   :insufficient not enough points, and nothing was written
    #
    # The balance is read with a row lock inside the transaction, so two
    # purchases arriving together cannot both pass a check made outside one.
    def spend(user:, points:, subject:, reason:)
      cost = points.to_i
      return :insufficient if user.nil? || cost <= 0 || !enabled?

      outcome = :insufficient

      ActiveRecord::Base.transaction do
        balance = IngenicPointBalance.lock.find_by(user_id: user.id)
        next if balance.nil? || balance.points < cost

        # Nil here is the ledger already holding this exact purchase, which is
        # an answer of its own rather than a failure: the thing is theirs, and
        # nothing more is owed for it.
        entry =
          record(
            user: user,
            points: -cost,
            event: IngenicPointEntry::DOWNLOAD,
            reason: reason,
            subject: subject,
          )
        outcome = entry ? :spent : :already
      end

      outcome
    end

    # An administrator's adjustment, with the note explaining it.
    #
    # Works whether or not points are switched on: the switch stops the forum
    # handing them out, and this is somebody deciding on purpose. A negative
    # amount is a deduction, which is the one way points are ever taken away
    # from a member outside the reversal path.
    def adjust(user:, points:, note:, by:)
      amount = points.to_i
      return if user.nil? || amount.zero?

      record(
        user: user,
        points: amount,
        event: IngenicPointEntry::MANUAL,
        reason: note.presence || I18n.t("ingenic.points.manual_reason"),
        note: note.presence,
        by: by,
      )
    end

    # Everything one subject has cost or earned its owner, for the screens that
    # have to explain a number.
    def entries_for(user, limit: 100)
      IngenicPointEntry.where(user_id: user.id).recent.limit(limit)
    end

    # The resources an account has unlocked, as ids, in one query — what the
    # download listing needs to draw a whole page of cards without asking about
    # each one.
    def unlocked_download_ids(user)
      return [] if user.nil?

      IngenicPointEntry
        .where(user_id: user.id, event: IngenicPointEntry::DOWNLOAD, subject_type: "IngenicDownload")
        .pluck(:subject_id)
        .to_set
    end

    # Recomputes every balance from the ledger.
    #
    # The balances are a cache, so this is the repair: after a restore, after an
    # import, or after somebody has been editing rows in the database. It is
    # also the reason a balance can be trusted without being the authority.
    def rebuild!
      totals = IngenicPointEntry.group(:user_id).sum(:points)
      now = Time.zone.now
      corrected = 0

      IngenicPointBalance.find_each do |row|
        total = totals.delete(row.user_id) || 0
        next if row.points == total

        IngenicPointBalance.where(id: row.id).update_all(["points = ?, updated_at = ?", total, now])
        corrected += 1
      end

      # Accounts with entries but no balance row: reachable if a row was deleted
      # by hand, which is exactly the kind of thing this is for.
      missing =
        totals.map do |user_id, total|
          { user_id: user_id, points: total, created_at: now, updated_at: now }
        end
      IngenicPointBalance.upsert_all(missing, unique_by: :user_id) if missing.any?

      { checked: IngenicPointBalance.count, corrected: corrected + missing.size }
    end

    # The one place an entry and its balance move are written, so they cannot
    # come apart. A duplicate entry rolls the transaction back with it, which is
    # what leaves the balance untouched when an award is refused.
    #
    # The savepoint is for the callers that are already inside a transaction —
    # a purchase holds a row lock while it works. A unique violation aborts the
    # transaction at the database, not merely the statement, so without it a
    # refused duplicate would take the caller's whole transaction down with it
    # and the lock would be released by an error rather than by an answer.
    def record(user:, points:, event:, reason:, subject: nil, note: nil, by: nil)
      entry = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        entry =
          IngenicPointEntry.create!(
            user_id: user.id,
            points: points,
            event: event,
            reason: reason,
            subject: subject,
            note: note,
            awarded_by_id: by&.id,
          )
        IngenicPointBalance.bump!(user.id, points)
      end

      entry
    rescue ActiveRecord::RecordNotUnique
      # This exact movement is already in the ledger. The only unique index an
      # insert here can trip is the one that says so.
      nil
    end
  end
end
