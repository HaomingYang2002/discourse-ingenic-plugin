# frozen_string_literal: true

# A member's running total.
#
# Derived from the ledger and never the authority on it: everything here can be
# recomputed with `Ingenic::Points.rebuild!`, which is what makes it safe to
# keep as a cache. It exists because the alternative — summing the ledger on
# every page that shows a balance — is a query whose cost grows with every post
# the forum has ever had.
class IngenicPointBalance < ActiveRecord::Base
  self.table_name = "ingenic_point_balances"

  # Required, unlike the ledger row beside it: a total is a number an account
  # holds, and there is nothing holding one once the account is gone. Deleting a
  # member therefore takes their balance row with them and leaves their movements
  # in the ledger — the pair to expect, since the number is recomputable from the
  # rows and nothing is lost that was not derived from them anyway.
  belongs_to :user

  validates :points, numericality: { only_integer: true }

  scope :top, -> { order(points: :desc, updated_at: :asc) }

  def self.for(user)
    return nil if user.nil?

    find_by(user_id: user.id)
  end

  # `self.for` rather than a bare `for`, which Ruby reads as the start of a for
  # loop and refuses.
  def self.total_for(user)
    self.for(user)&.points.to_i
  end

  # Moves one account's total by `delta`.
  #
  # One statement, and the arithmetic is in it rather than in Ruby: reading the
  # total, adding, and writing it back would lose a movement whenever two of
  # them arrived together, and the row lock that would fix that is a lock held
  # for the length of whatever the caller is doing.
  #
  # `ON CONFLICT` rather than create-then-update, so the first movement for an
  # account and the thousandth are the same code path and neither can trip over
  # the other. It cannot fail on a conflict, which matters because its caller is
  # usually already inside a transaction that has work to keep — a unique
  # violation would abort that transaction in the database, not just here.
  def self.bump!(user_id, delta)
    now = Time.zone.now

    upsert(
      { user_id: user_id, points: delta, created_at: now, updated_at: now },
      unique_by: :user_id,
      on_duplicate:
        Arel.sql(
          "points = ingenic_point_balances.points + EXCLUDED.points, " \
            "updated_at = EXCLUDED.updated_at",
        ),
    )

    find_by(user_id: user_id)
  end
end
