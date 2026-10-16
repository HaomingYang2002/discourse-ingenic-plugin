# frozen_string_literal: true

module Ingenic
  # 高分悬赏: a member sets points aside on their own topic and pays them to
  # whoever writes the answer they accept.
  #
  # Three decisions are made here and nowhere else.
  #
  # **The points are escrowed, not promised.** Opening a bounty takes them off
  # the asker's balance and writes a negative entry in the ledger, so what is
  # offered cannot be spent on a download while the offer stands. The alternative
  # — checking the balance at settlement time — would let a member offer the same
  # thousand points on five topics and settle whichever one got answered.
  #
  # **What the asker puts up is what the answerer receives.** No platform cut. The
  # forum is keeping the books, not taking a side in the transaction.
  #
  # **Accepting an answer is the payment, and it is final.** This is the one that
  # needs arguing for, and the argument is in `settle_for` below.
  #
  # Every movement goes through Ingenic::Points, so a bounty is auditable with the
  # same screen as everything else: the escrow, the release and the refund are
  # three ordinary rows in `ingenic_point_entries`, all of them carrying the
  # bounty as their subject.
  module Bounties
    module_function

    # Whether the forum offers bounties at all.
    #
    # Points have to be on for the same reason: an escrow is a movement in the
    # ledger, and a forum that has stopped handing points out has no balances to
    # set aside. The switch is here rather than in the controller so that a job
    # or a console is held to it too.
    def enabled?
      SiteSetting.ingenic_bounties_enabled && Points.enabled?
    end

    # Whether a bounty could be settled at all, which is a different question
    # from whether this member may open one.
    #
    # A bounty is paid when an answer is accepted, and accepting an answer is
    # discourse-solved's business rather than this plugin's. Without that plugin
    # there is no way to accept anything, so an open bounty would be a promise
    # the forum has no way to keep — and taking a member's points against a
    # promise nobody can fulfil is worse than not offering the feature. Whether
    # the *category* allows an accepted answer is a separate and narrower
    # question, and it is the guardian's, where the other "may this person do
    # this here" answers live.
    def available?
      enabled? && solved?
    end

    def solved?
      !defined?(DiscourseSolved::SolvedTopic).nil?
    end

    def min_points
      SiteSetting.ingenic_bounty_min_points.to_i
    end

    def max_points
      SiteSetting.ingenic_bounty_max_points.to_i
    end

    def expiry_days
      SiteSetting.ingenic_bounty_expiry_days.to_i
    end

    # The topic's current bounty, or nil. What a topic page asks.
    #
    # "Current" is the newest row whatever its state, not the standing one, and
    # those are the same row: a bounty can only be opened while none is standing,
    # so the newest row is the open one whenever there is an open one. Reading it
    # this way costs the same single lookup and also finds the bounty that has
    # been paid, which the topic page draws as a settled banner — the record of
    # what an answer was worth is half of what makes the board worth reading.
    #
    # One of the two — the accepted one — is shown a second time here because the
    # question it answered is where a reader arrives. Withdrawn and expired ones
    # are returned too and drawn by nobody: they are the newest row for the
    # moment between one offer ending and the next beginning, and "this bounty
    # was withdrawn" is not news a topic should carry forever.
    def for_topic(topic)
      return nil if topic.nil?

      IngenicBounty.where(topic_id: topic.id).order(created_at: :desc, id: :desc).first
    end

    # The board: every standing bounty the viewer may see, richest first.
    #
    # Read through the guardian rather than straight off the table, because a
    # bounty names a topic and a topic can be in a category the viewer has no
    # business knowing about. A board that leaked those titles would be a worse
    # leak than a topic list, because it would also say how much was on offer.
    def board(guardian:, limit: 10)
      return IngenicBounty.none if guardian.nil?

      visible =
        Topic
          .secured(guardian)
          .where(deleted_at: nil, visible: true, archived: false)
          .select(:id)

      IngenicBounty.live.where(topic_id: visible).by_value.limit(limit)
    end

    # Opens a bounty on a member's own topic; the permission is the guardian's,
    # the arithmetic is here.
    #
    # Answers rather than raises, for the same reason `Points.spend` does: the
    # caller is a form, and every one of these is a sentence to show the member
    # rather than an error page.
    #
    #   the bounty    the points are set aside and the offer stands
    #   :unavailable  the forum is not taking bounties
    #   :too_small    below the floor
    #   :too_large    above the ceiling
    #   :taken        the topic already has one standing
    #   :insufficient not enough points, and nothing was written
    def open!(topic:, user:, points:)
      return :unavailable if topic.nil? || user.nil? || !available?
      return :taken if IngenicBounty.live.exists?(topic_id: topic.id)

      amount = points.to_i
      # A bounty of nothing is not a bounty, whatever the floor has been set to.
      # A floor above a ceiling is a misconfiguration, and the floor wins: the
      # answer is then "too small" for everything, which is at least a sentence.
      return :too_small if amount < [min_points, 1].max
      return :too_large if amount > max_points

      bounty = nil
      spent = nil

      begin
        ActiveRecord::Base.transaction do
          bounty =
            IngenicBounty.create!(
              topic_id: topic.id,
              user_id: user.id,
              points: amount,
              state: IngenicBounty::OPEN,
              expires_at: expiry_days.days.from_now,
            )

          spent =
            Points.spend(
              user: user,
              points: amount,
              subject: bounty,
              reason: I18n.t("ingenic.bounties.escrow_reason", points: amount),
              event: IngenicPointEntry::BOUNTY,
            )

          # Not enough points: the offer comes back off the table with the
          # escrow that never happened. A bounty row without its escrow would be
          # a promise to pay points that were never set aside.
          raise ActiveRecord::Rollback unless spent == :spent
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Two forms submitted together and the other one got there first. The
        # partial index on `topic_id` is what says so, and the earlier check
        # above is only what usually saves us the round trip.
        return :taken
      end

      spent == :spent ? bounty : spent
    end

    # Withdraws a standing bounty and gives the points back.
    def cancel!(bounty:, by: nil)
      refund!(
        bounty: bounty,
        state: IngenicBounty::CANCELLED,
        reason: I18n.t("ingenic.bounties.cancel_reason"),
        by: by,
      )
    end

    # Closes a bounty nobody answered in time and gives the points back. The
    # asker is not asked: they offered the points for an answer within a period,
    # the period is over, and holding them past it would be the forum deciding to
    # keep an offer open that its author set an end to.
    def expire!(bounty)
      refund!(
        bounty: bounty,
        state: IngenicBounty::EXPIRED,
        reason: I18n.t("ingenic.bounties.expire_reason"),
      )
    end

    # Every bounty whose time is up, closed. Run on a schedule; the count is for
    # the log rather than for anybody to act on.
    #
    # `find_each` rather than a scope and a loop, because a forum old enough to
    # have thousands of due bounties should not load them all to give each one
    # its money back.
    def expire_due!
      expired = 0

      IngenicBounty.live.where("expires_at <= ?", Time.zone.now).find_each do |bounty|
        expired += 1 if expire!(bounty) == :refunded
      end

      expired
    end

    # An answer was accepted: pays the topic's standing bounty, if it has one.
    #
    # Reached from Discourse's own accepted-answer event, so it runs in the
    # middle of somebody else's action and must not be able to fail it. An
    # acceptance that cannot be paid for is still an acceptance, and points
    # sitting in escrow are points an administrator can see and deal with.
    #
    # ## Why the payment is final
    #
    # discourse-solved revokes the previous answer when a second one is accepted,
    # so an author who picks the wrong answer can change their mind. The bounty
    # does not follow them, and that is deliberate.
    #
    # The ledger records one movement of one kind about one thing: an acceptance
    # that has been paid for this post is in the table, and the unique index
    # behind that rule would refuse to write it again. So a reversal could not be
    # undone — the author would take the points back from the first answerer and
    # then be unable to pay the second, which is a state nobody can repair from
    # the forum. Leaving the payment where it is can be repaired: an
    # administrator adjusts the two accounts by hand, on a screen that already
    # exists for exactly this kind of correction.
    #
    # Between a mistake a person can fix and a state the software cannot leave,
    # the mistake is the one to ship.
    def settle_for(post)
      return if post.nil?

      bounty = IngenicBounty.live.find_by(topic_id: post.topic_id)
      return if bounty.nil?
      # The opening post is not an answer to itself.
      return if post.post_number.to_i <= 1
      return if post.user_id.nil?

      accept!(bounty: bounty, post: post, by: accepter_of(post))
    rescue StandardError => e
      Rails.logger.warn("Ingenic: bounty settlement failed: #{e.class} #{e.message}")
      nil
    end

    # Pays a standing bounty to the member who wrote the accepted answer.
    #
    #   :paid      the points are the answerer's and the bounty is closed
    #   :already   this bounty was paid before; nothing more is owed
    #   :not_open  it was never open, or it has been settled some other way
    #
    # The row is locked and re-read inside the transaction, so two acceptances
    # arriving together — an author and a moderator, or a double click — are
    # serialised, and the second one finds the bounty already closed rather than
    # paying it twice.
    def accept!(bounty:, post:, by: nil)
      return :not_open if bounty.nil? || !bounty.open?
      return :not_open if post.nil? || post.user_id.nil?

      outcome = :not_open

      ActiveRecord::Base.transaction do
        locked = IngenicBounty.lock.find_by(id: bounty.id)
        next if locked.nil? || !locked.open?

        entry =
          Points.record(
            user: post.user,
            points: locked.points,
            event: IngenicPointEntry::BOUNTY_AWARD,
            reason: I18n.t("ingenic.bounties.award_reason", points: locked.points),
            subject: locked,
          )

        # Nil is the ledger already holding this exact payment. The state check
        # above should have caught it, and this is the second guard: if the two
        # ever disagree, the ledger is the one that is right.
        if entry.nil?
          outcome = :already
          next
        end

        locked.update!(
          state: IngenicBounty::ACCEPTED,
          accepted_post_id: post.id,
          accepted_by_id: by&.id,
          settled_at: Time.zone.now,
        )
        outcome = :paid
      end

      outcome
    end

    # Who accepted the answer, for the record.
    #
    # The event carries the post and not the person, and the bounty keeps the
    # name so that "who decided this" has an answer a year later — which is the
    # same reason an administrator's adjustment keeps its note.
    def accepter_of(post)
      return nil unless solved?

      DiscourseSolved::TopicAnswer.find_by(answer_post_id: post.id)&.accepter
    rescue StandardError
      nil
    end

    # Gives the escrow back and closes the bounty.
    #
    # The two ways this happens — the asker withdrawing and nobody answering in
    # time — differ only in the word written down, which is why they share a
    # body and pass their state and their reason in.
    def refund!(bounty:, state:, reason:, by: nil)
      return :not_open if bounty.nil? || !bounty.open?

      outcome = :not_open

      ActiveRecord::Base.transaction do
        locked = IngenicBounty.lock.find_by(id: bounty.id)
        next if locked.nil? || !locked.open?

        entry =
          Points.record(
            user: locked.user,
            points: locked.points,
            event: IngenicPointEntry::BOUNTY_REFUND,
            reason: reason,
            subject: locked,
            by: by,
          )

        if entry.nil?
          outcome = :already
          next
        end

        locked.update!(state: state, settled_at: Time.zone.now)
        outcome = :refunded
      end

      outcome
    end
  end
end
