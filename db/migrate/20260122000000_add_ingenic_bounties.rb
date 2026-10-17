# frozen_string_literal: true

class AddIngenicBounties < ActiveRecord::Migration[7.2]
  def change
    # 高分悬赏: a member sets points aside on their own topic and pays them to
    # whoever writes the answer they accept.
    #
    # A row here is the offer, not the money. The money is in the points ledger
    # like every other movement — the escrow is one entry taking the points off
    # the asker when the bounty opens, and the release is another putting them on
    # the answerer when it settles. That is what makes a bounty auditable with
    # the same screen as everything else, and what stops escrowed points being
    # spent on a download while the offer stands: they are gone from the balance,
    # and this row is the promise that they come back.
    create_table :ingenic_bounties do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :points, null: false

      # open       the offer stands, and the points are escrowed
      # accepted   an answer was accepted and the points are the answerer's
      # cancelled  the asker withdrew, and the points came back
      # expired    nobody answered in time, and the points came back
      #
      # Only the first of these is a state a bounty moves out of, and it never
      # moves back into it — which is what the partial index below rests on.
      t.string :state, null: false, default: "open"
      t.bigint :accepted_post_id
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :settled_at
      t.timestamps
    end

    # One standing bounty per topic.
    #
    # Partial, because what is unique is the *open* one: a topic whose bounty
    # expired may have another, and a settled topic may be asked about again
    # later. This index is the answer to "may this topic be given a bounty right
    # now", asked by the database rather than by a check that ran a moment
    # earlier — two forms submitted together both insert, and one of them is
    # refused.
    add_index :ingenic_bounties,
              :topic_id,
              unique: true,
              where: "state = 'open'",
              name: "idx_ingenic_bounties_one_live_per_topic"

    add_index :ingenic_bounties, :state

    # What the expiry job reads: every open bounty whose time is up, in one
    # query, on a table that grows with the forum.
    add_index :ingenic_bounties,
              %i[state expires_at],
              name: "idx_ingenic_bounties_for_expiry"

    # The board, richest first. `points` is the ordering a member reads it in,
    # and the state is the filter, so the two together are the index.
    add_index :ingenic_bounties, %i[state points], name: "idx_ingenic_bounties_for_board"
  end
end
