# frozen_string_literal: true

class AddIngenicHomeControls < ActiveRecord::Migration[7.2]
  def change
    # The buttons in the header, beside the logo. They are content rather than
    # theme code because the destinations change without a release: the Chinese
    # site, a GitHub organisation, a partner's portal. A button is either a
    # label, an icon, or both; `show_label` is what makes "icon only" a choice
    # rather than a side effect of leaving the name empty, which would take the
    # accessible name away with it.
    create_table :ingenic_header_links do |t|
      t.string :label, null: false
      t.string :href, null: false
      t.string :icon
      t.string :image_url
      t.boolean :show_label, null: false, default: true
      t.boolean :external, null: false, default: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_header_links,
              %i[published position],
              name: "idx_ingenic_header_links_order"

    # The cards under "Popular sections". A card either names a category — in
    # which case the reader gets its real colour, icon, description and topic
    # count — or carries its own destination, which is how the documentation
    # page sits beside the forum's sections without a category pretending to be
    # one. A row with both uses the category and ignores the href.
    create_table :ingenic_section_cards do |t|
      t.string :label
      t.string :category
      t.string :href
      t.string :description
      t.string :icon
      t.string :image_url
      t.string :color
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_section_cards,
              %i[published position],
              name: "idx_ingenic_section_cards_order"

    # A partner platform shown as its icon alone. The label stays in the row —
    # it is the button's accessible name — but it is not drawn.
    add_column :ingenic_social_links, :icon_only, :boolean, null: false, default: false
  end
end
