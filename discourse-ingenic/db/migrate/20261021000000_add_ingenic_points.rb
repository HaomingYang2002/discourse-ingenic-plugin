# frozen_string_literal: true

class AddIngenicPoints < ActiveRecord::Migration[7.2]
  # Where the plugin starts rather than where it has to stay. Every one of these
  # is a row an administrator can reprice, reword, reorder or retire from the
  # admin screen; the numbers below are a reading of how much each kind of
  # contribution is worth to a technical forum, not a rule.
  SEED = [
    ["topic_created", 5, "Opening a discussion"],
    ["post_created", 2, "Answering in one"],
    ["like_received", 1, "A post of yours being liked"],
    ["solution_accepted", 15, "Your answer being accepted"],
  ].freeze

  def change
    # What earns points and how many. A table rather than constants in the model
    # for the same reason the download classifications are: the amounts are
    # Ingenic's judgement about their own community and should not need a deploy
    # to change.
    #
    # One row per action, which the unique index enforces — two rules for one
    # action would be two answers to the same question.
    create_table :ingenic_point_rules do |t|
      t.string :event, null: false
      t.integer :points, null: false, default: 0
      t.string :label, null: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_point_rules, :event, unique: true

    # The ledger. Append-only in the way that matters: every movement is a row,
    # nothing is ever edited, and the balance is the sum of them. There is no
    # updated_at because there is no update.
    #
    # `subject` is the thing the movement is about — the post that was written,
    # the like that was given, the resource that was unlocked, or for a reversal
    # the entry it takes back. It is what makes an award recordable exactly once
    # and reversible exactly once.
    create_table :ingenic_point_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :points, null: false
      t.string :event, null: false
      t.string :reason, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.text :note
      t.references :awarded_by, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end

    # One movement of one kind about one thing, per person. This is the whole
    # defence against awarding twice: two events arriving together both try to
    # insert, and the database lets one of them through. A manual adjustment has
    # no subject, and the nulls are distinct in a unique index, so an
    # administrator can adjust the same account all day.
    add_index :ingenic_point_entries,
              %i[user_id event subject_type subject_id],
              unique: true,
              name: "idx_ingenic_point_entries_once"

    add_index :ingenic_point_entries,
              %i[user_id created_at],
              name: "idx_ingenic_point_entries_reader"

    # Reading the ledger of one subject — every movement a post ever caused.
    add_index :ingenic_point_entries,
              %i[subject_type subject_id],
              name: "idx_ingenic_point_entries_subject"

    # The running balance, so a page does not sum a table that grows with every
    # post on the forum. Derived, never authoritative: `Ingenic::Points.rebuild!`
    # recomputes every row from the ledger, which is what makes it safe to keep
    # as a cache.
    create_table :ingenic_point_balances do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :points, null: false, default: 0
      t.timestamps
    end

    # What a resource costs to unlock. Zero is free, which is every resource
    # until somebody says otherwise: the access levels already decide who may
    # have a file, and this is an addition to that rather than a replacement.
    add_column :ingenic_downloads, :point_cost, :integer, null: false, default: 0

    seed_rules
  end

  private

  def seed_rules
    now = Time.zone.now

    SEED.each_with_index do |(event, points, label), index|
      execute <<~SQL
        INSERT INTO ingenic_point_rules (event, points, label, position, published, created_at, updated_at)
        VALUES (#{connection.quote(event)}, #{points}, #{connection.quote(label)}, #{index}, true, #{connection.quote(now)}, #{connection.quote(now)})
        ON CONFLICT (event) DO NOTHING
      SQL
    end
  end
end
