# frozen_string_literal: true

class AddIngenicSiteLinks < ActiveRecord::Migration[7.2]
  def change
    # The strip of partner icons in the footer.
    #
    # An entry is either a link — an icon that leaves the site — or a QR code
    # that opens on hover, which is how the Chinese forum presents GitHub and
    # the WeChat account. One table rather than two because they differ only by
    # which payload is filled in, and an editor adding a platform should not
    # have to decide which table it belongs in before typing a name.
    create_table :ingenic_social_links do |t|
      t.string :label, null: false
      t.string :kind, null: false, default: "link"
      t.string :href
      t.string :image_url
      t.string :qr_image_url
      t.string :qr_caption
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_social_links,
              %i[published position],
              name: "idx_ingenic_social_links_order"

    # The link columns beside it. A column is a heading plus a list, and the two
    # are separate rows because the heading has no destination of its own.
    create_table :ingenic_footer_columns do |t|
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_footer_columns,
              %i[published position],
              name: "idx_ingenic_footer_columns_order"

    create_table :ingenic_footer_links do |t|
      t.references :column,
                   null: false,
                   foreign_key: {
                     to_table: :ingenic_footer_columns,
                   }
      t.string :label, null: false
      t.string :href, null: false
      t.boolean :external, null: false, default: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_footer_links,
              %i[column_id published position],
              name: "idx_ingenic_footer_links_order"
  end
end
