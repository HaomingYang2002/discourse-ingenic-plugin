# frozen_string_literal: true

# A page's identity was the row's primary key, but every version keeps its own
# row for the page it edited. A copy in a later version still pointed its
# `parent_id` at the row in the version it was copied from, so deleting that
# row, overriding it again or re-ordering a level could take unrelated rows
# with it — the tree edge was really an id in another version.
#
# `node_key` names the page itself and is shared by every version's row for it;
# `parent_node_key` is the tree edge. The resolver reads the tree from these,
# so row ids only decide which version owns the text.
class AddIngenicDocPageNodeKeys < ActiveRecord::Migration[7.2]
  class MigrationPage < ActiveRecord::Base
    self.table_name = "ingenic_doc_pages"
  end

  class MigrationVersion < ActiveRecord::Base
    self.table_name = "ingenic_doc_versions"
  end

  def up
    add_column :ingenic_doc_pages, :node_key, :string
    add_column :ingenic_doc_pages, :parent_node_key, :string

    backfill_node_keys!

    change_column_null :ingenic_doc_pages, :node_key, false

    add_index :ingenic_doc_pages, :node_key
    add_index :ingenic_doc_pages, :parent_node_key
    # One row per page per version and language. Two rows for the same page in
    # the same version would resolve to whichever the query returned first.
    add_index :ingenic_doc_pages,
              %i[node_key version_id locale],
              unique: true,
              name: "idx_ingenic_doc_pages_node_version_locale"

    # The kinds the resolver knows how to render; a third value would be
    # silently treated as an article.
    add_check_constraint :ingenic_doc_pages,
                         "kind IN ('page', 'folder')",
                         name: "ingenic_doc_pages_kind"
    # Slugs are addresses. A space or an uppercase letter in one produces a
    # link that the public route cannot match, and nothing reports it.
    add_check_constraint :ingenic_doc_pages,
                         "slug ~ '^[a-z0-9][a-z0-9-]*$'",
                         name: "ingenic_doc_pages_slug_format"

    # "Latest" is the version a reader lands on. Two flagged rows in the same
    # language would make that choice depend on query order.
    add_index :ingenic_doc_versions,
              %i[product_id locale],
              unique: true,
              where: "latest",
              name: "idx_ingenic_doc_versions_latest"
  end

  def down
    remove_index :ingenic_doc_versions, name: "idx_ingenic_doc_versions_latest"
    remove_check_constraint :ingenic_doc_pages, name: "ingenic_doc_pages_slug_format"
    remove_check_constraint :ingenic_doc_pages, name: "ingenic_doc_pages_kind"
    remove_index :ingenic_doc_pages, name: "idx_ingenic_doc_pages_node_version_locale"
    remove_index :ingenic_doc_pages, :parent_node_key
    remove_index :ingenic_doc_pages, :node_key
    remove_column :ingenic_doc_pages, :parent_node_key
    remove_column :ingenic_doc_pages, :node_key
  end

  private

  # Identity follows the rule the resolver already used: within one product a
  # slug names one page across versions, whichever language it was written in.
  # The row that introduced the slug in the oldest version becomes the key, so
  # the result is deterministic and the backfill can be re-run on the same data.
  def backfill_node_keys!
    versions =
      MigrationVersion.pluck(:id, :product_id, :position).each_with_object({}) do |(id, product_id, position), memo|
        memo[id] = [product_id, position]
      end
    rows = MigrationPage.pluck(:id, :version_id, :slug, :parent_id)

    node_by_slug = {}
    node_by_id = {}

    ordered_rows =
      rows.sort_by do |id, version_id, _slug, _parent_id|
        version = versions[version_id]
        [version ? version[1] : 0, id]
      end

    ordered_rows.each do |id, version_id, slug, _parent_id|
      product_id = versions[version_id]&.first
      key = [product_id, slug]
      node_by_slug[key] ||= id.to_s
      node_by_id[id] = node_by_slug[key]
    end

    rows.each do |id, _version_id, _slug, parent_id|
      MigrationPage.where(id: id).update_all(
        node_key: node_by_id[id],
        parent_node_key: parent_id && node_by_id[parent_id],
      )
    end
  end
end
