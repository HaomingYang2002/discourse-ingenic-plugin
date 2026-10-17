# frozen_string_literal: true

# A member can be deleted, and every one of these tables had to survive it.
#
# Each reference to `users` the plugin created was a plain one, which in
# PostgreSQL is RESTRICT: the account could not go while a row mentioned it. So
# an administrator deleting a member who had ever earned a point, applied for a
# download or opened a 高分悬赏 got a foreign key violation from the database
# instead of a deleted account — and nothing in the plugin was listening for the
# deletion to clean up first. Discourse's own `UserDestroyer` knows about its own
# tables; a plugin's are the plugin's problem.
#
# What replaces the plain references is the pattern discourse-adplugin uses for
# its own user columns, with the remedy chosen by what a row is *for*:
#
#   nullify  the row is a record of something that happened — a movement in the
#            points ledger, an application and the decision on it, a grant, a
#            bounty — or a note of who decided something (awarded_by,
#            reviewed_by, granted_by, revoked_by, accepted_by). The row stays and
#            only the account is blanked, so the books still add up and the
#            history still reads. What is lost is the name, which is the whole of
#            what a deleted account is.
#
#   cascade  the row is meaningless or private without its account. A developer
#            profile is information *about* a person, a point balance is a cached
#            total nobody holds any more, and a permission is a grant to a member
#            or a group — its check constraint requires exactly one principal, so
#            blanking one is not even possible.
#
# `ingenic_download_logs` is absent because it was written with `on_delete:
# :cascade` from the start, for this same reason: a delivery to an account that
# has since been deleted is still a delivery, and the row is only ever read as a
# count and a resource name.
#
# It lives in `db/post_migrate` because Postgres has no ALTER for a referential
# action: changing one means dropping the constraint and writing it again, and
# Discourse patches migrations so that a `DROP CONSTRAINT` outside a post-deploy
# migration raises. Written as a regular migration it aborted the whole set on
# its first `remove_foreign_key`, so nothing after it ran and the plugin could
# not be installed at all.
class LetIngenicRowsOutliveTheirAccounts < ActiveRecord::Migration[7.2]
  # Rows that stay, with the account blanked. The `_by` columns beside them were
  # already nullable — a decision can be recorded without saying who made it —
  # while the `user_id` column of each was not, because a row without an owner
  # was not a thing the plugin could express.
  NULLIFIED = {
    ingenic_point_entries: %i[user_id awarded_by_id],
    ingenic_download_requests: %i[user_id reviewed_by_id],
    ingenic_download_grants: %i[user_id granted_by_id revoked_by_id],
    ingenic_bounties: %i[user_id accepted_by_id],
  }.freeze

  # The four columns above that were NOT NULL, which the blanking needs.
  RELAXED = %i[
    ingenic_point_entries
    ingenic_download_requests
    ingenic_download_grants
    ingenic_bounties
  ].freeze

  # Rows that go with the account or the group they name.
  CASCADED = {
    ingenic_developer_profiles: { user_id: :users },
    ingenic_point_balances: { user_id: :users },
    ingenic_permissions: { user_id: :users, group_id: :groups },
  }.freeze

  def up
    RELAXED.each { |table| change_column_null table, :user_id, true }

    NULLIFIED.each do |table, columns|
      columns.each do |column|
        # Postgres has no ALTER for a referential action, so each key is dropped
        # and written again. The name it is given is derived from the table and
        # the column, so it comes back as the same key under a new rule.
        remove_foreign_key table, :users, column: column
        add_foreign_key table, :users, column: column, on_delete: :nullify
      end
    end

    CASCADED.each do |table, columns|
      columns.each do |column, target|
        remove_foreign_key table, target, column: column
        add_foreign_key table, target, column: column, on_delete: :cascade
      end
    end
  end

  # Back to the plain references, which is a rule the data may now break: if a
  # member has been deleted since this ran, the not-null columns cannot be
  # restored while their blanked rows are there, and the migration will say so
  # rather than quietly deleting the ledger to make room. That is the honest
  # direction of a rollback here — going back means deciding, by hand, what
  # those records were worth.
  def down
    NULLIFIED.each do |table, columns|
      columns.each do |column|
        remove_foreign_key table, :users, column: column
        add_foreign_key table, :users, column: column
      end
    end

    CASCADED.each do |table, columns|
      columns.each do |column, target|
        remove_foreign_key table, target, column: column
        add_foreign_key table, target, column: column
      end
    end

    RELAXED.each { |table| change_column_null table, :user_id, false }
  end
end
