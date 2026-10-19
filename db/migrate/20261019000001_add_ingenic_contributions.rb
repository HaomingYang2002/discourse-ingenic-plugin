# frozen_string_literal: true

# A contribution score, kept apart from the points a member can spend.
#
# The two numbers answer different questions. Points are money: earned by the
# same actions, spent on downloads and set aside as a bounty. Contribution is a
# reading of how much somebody took part — it is never spent, it is not affected
# by a purchase, and a bounty changing hands does not move it.
#
# Keeping it in its own table is what makes that independence real rather than
# a promise: nothing here writes to `ingenic_point_balances`, and switching the
# spendable points off does not erase the ranking.
class AddIngenicContributions < ActiveRecord::Migration[7.2]
  def change
    create_table :ingenic_contributions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :points, null: false
      t.string :event, null: false
      t.string :subject_type
      t.bigint :subject_id
      # The day the award belongs to. Only the daily visit reads it, but it is
      # stored on every row so a later report can group by day without guessing
      # from a timestamp.
      t.date :on_date, null: false
      t.datetime :created_at, null: false
    end

    # One award of one kind for one thing. A post can earn a topic award and a
    # solution award — different events, both kept — but the same event on the
    # same post is written once, however many times the handler hears about it.
    add_index :ingenic_contributions,
              %i[event subject_type subject_id],
              unique: true,
              where: "subject_id IS NOT NULL",
              name: "idx_ingenic_contributions_once"

    # A visit counts once a day. The condition is what lets the index coexist
    # with the post awards above: only visit rows are unique per day.
    add_index :ingenic_contributions,
              %i[user_id on_date],
              unique: true,
              where: "event = 'daily_visit'",
              name: "idx_ingenic_contributions_visit"

    add_index :ingenic_contributions, %i[created_at]
    add_index :ingenic_contributions, %i[user_id created_at]
  end
end
