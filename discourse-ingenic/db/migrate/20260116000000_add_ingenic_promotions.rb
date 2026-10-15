# frozen_string_literal: true

class AddIngenicPromotions < ActiveRecord::Migration[7.2]
  def change
    # The homepage promotion slots.
    #
    # The Chinese forum runs three of them — GitHub, the download centre and the
    # documentation centre — and all three have the same shape: a corner tag, a
    # headline, a paragraph, a button and a background image. What reads as
    # three features is therefore one list with three rows, and the Ingenic team
    # can add a fourth without a deploy.
    create_table :ingenic_promotions do |t|
      # The small tag above the headline ("Official", "New"). Named for where it
      # sits rather than "badge", which in Discourse means a forum badge and
      # would read as a mistake to anyone else working on this.
      t.string :corner_label
      t.string :title, null: false
      t.text :description
      t.string :button_label
      t.string :button_href
      t.boolean :button_external, null: false, default: false
      t.string :image_url
      t.string :locale, null: false, default: "en"
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true

      # A campaign has a life span, so the dates are optional and an entry with
      # neither runs until someone unpublishes it. Scheduling is what makes
      # "an activity" different from "a banner".
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end

    add_index :ingenic_promotions,
              %i[published position],
              name: "idx_ingenic_promotions_order"
    add_index :ingenic_promotions,
              %i[locale starts_at ends_at],
              name: "idx_ingenic_promotions_window"
  end
end
