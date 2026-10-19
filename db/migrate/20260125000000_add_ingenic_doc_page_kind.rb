# frozen_string_literal: true

# A documentation tree is not only articles. The reference site groups chapters
# under folders that expand in place and have no text of their own; here the
# only way to make a parent was to write an article that happened to have
# children, so every chapter heading opened an empty page.
#
# Existing rows are pages, which is what they already behaved as. Nothing that
# reads the tree changes until a folder is created.
class AddIngenicDocPageKind < ActiveRecord::Migration[7.2]
  def up
    add_column :ingenic_doc_pages, :kind, :string, null: false, default: "page"
    add_index :ingenic_doc_pages, :kind
  end

  def down
    remove_index :ingenic_doc_pages, :kind
    remove_column :ingenic_doc_pages, :kind
  end
end
