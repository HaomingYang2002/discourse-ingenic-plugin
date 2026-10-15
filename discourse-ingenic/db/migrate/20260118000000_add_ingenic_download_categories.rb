# frozen_string_literal: true

class AddIngenicDownloadCategories < ActiveRecord::Migration[7.2]
  # The list the plugin shipped with while it was a constant in the model. It is
  # only used to seed the table, so that the list starts where the code was
  # rather than empty and the Ingenic team edits names instead of inventing them.
  SEED = %w[sdk firmware manual datasheet toolchain example release_notes other].freeze

  def up
    create_table :ingenic_download_categories do |t|
      t.string :name, null: false
      t.string :locale, null: false, default: "en"
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :ingenic_download_categories, %i[name locale], unique: true

    add_reference :ingenic_downloads,
                  :category,
                  foreign_key: {
                    to_table: :ingenic_download_categories,
                  },
                  index: true

    seed_categories

    # The fixed enum goes away once every row points at a category. Two sources
    # for one fact is the thing this migration exists to remove.
    remove_index :ingenic_downloads, name: "idx_ingenic_downloads_lookup"
    remove_column :ingenic_downloads, :kind

    add_index :ingenic_downloads,
              %i[product_slug category_id version locale],
              name: "idx_ingenic_downloads_lookup"
  end

  def down
    remove_index :ingenic_downloads, name: "idx_ingenic_downloads_lookup"
    add_column :ingenic_downloads, :kind, :string

    execute <<~SQL
      UPDATE ingenic_downloads
      SET kind = ingenic_download_categories.name
      FROM ingenic_download_categories
      WHERE ingenic_downloads.category_id = ingenic_download_categories.id
    SQL

    add_index :ingenic_downloads,
              %i[product_slug kind version locale],
              name: "idx_ingenic_downloads_lookup"

    remove_reference :ingenic_downloads, :category
    drop_table :ingenic_download_categories
  end

  private

  def seed_categories
    now = Time.zone.now

    SEED.each_with_index do |name, index|
      execute <<~SQL
        INSERT INTO ingenic_download_categories (name, locale, position, published, created_at, updated_at)
        VALUES (#{connection.quote(name)}, 'en', #{index}, true, #{connection.quote(now)}, #{connection.quote(now)})
        ON CONFLICT (name, locale) DO NOTHING
      SQL
    end

    # Rows that already existed keep their classification as they move off the
    # enum. There are none on a fresh install; on one where the plugin has been
    # used this is what stops the migration from erasing the answer.
    execute <<~SQL
      UPDATE ingenic_downloads
      SET category_id = ingenic_download_categories.id
      FROM ingenic_download_categories
      WHERE ingenic_downloads.kind = ingenic_download_categories.name
        AND ingenic_downloads.category_id IS NULL
    SQL
  end
end
