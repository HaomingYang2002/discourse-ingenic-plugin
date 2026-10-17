# frozen_string_literal: true

class CreateIngenicContent < ActiveRecord::Migration[7.2]
  def change
    create_table :ingenic_doc_products do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :locale, null: false, default: "en"
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ingenic_doc_products, [:slug, :locale], unique: true

    create_table :ingenic_doc_versions do |t|
      t.references :product, null: false, foreign_key: { to_table: :ingenic_doc_products }
      t.string :slug, null: false
      t.string :label, null: false
      t.string :locale, null: false, default: "en"
      t.boolean :latest, null: false, default: false
      t.boolean :deprecated, null: false, default: false
      t.date :released_on
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ingenic_doc_versions, [:product_id, :slug, :locale], unique: true

    create_table :ingenic_doc_pages do |t|
      t.references :version, null: false, foreign_key: { to_table: :ingenic_doc_versions }
      t.references :parent, foreign_key: { to_table: :ingenic_doc_pages }
      t.string :slug, null: false
      t.string :title, null: false
      t.text :body
      t.string :locale, null: false, default: "en"
      t.string :topic_url
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ingenic_doc_pages, [:version_id, :slug, :locale], unique: true

    create_table :ingenic_downloads do |t|
      t.string :product_slug, null: false
      t.string :kind, null: false
      t.string :version
      t.string :locale, null: false, default: "en"
      t.string :name, null: false
      t.text :description
      t.string :platform
      t.string :architecture
      t.string :file_url, null: false
      t.string :file_size
      t.string :sha256
      t.date :released_on
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ingenic_downloads, [:product_slug, :kind, :version, :locale], name: "idx_ingenic_downloads_lookup"

    create_table :ingenic_boards do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :locale, null: false, default: "en"
      t.string :chip
      t.text :description
      t.string :image_url
      t.string :documentation_url
      t.string :application_url, null: false
      t.boolean :published, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ingenic_boards, [:slug, :locale], unique: true
  end
end
