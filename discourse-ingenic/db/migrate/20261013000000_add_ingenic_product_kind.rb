# frozen_string_literal: true

class AddIngenicProductKind < ActiveRecord::Migration[7.2]
  def up
    add_column :ingenic_doc_products, :kind, :string

    # Rows that predate the series/chip split are backfilled from their shape:
    # a root product acted as the thing a reader picked, which is now a series,
    # and anything already nested is a chip. Admins can re-assign afterwards
    # from the documentation management page.
    execute <<~SQL
      UPDATE ingenic_doc_products
         SET kind = CASE WHEN parent_id IS NULL THEN 'series' ELSE 'chip' END
       WHERE kind IS NULL
    SQL

    change_column_default :ingenic_doc_products, :kind, "series"
    change_column_null :ingenic_doc_products, :kind, false

    add_index :ingenic_doc_products, %i[kind position], name: "idx_ingenic_doc_products_kind"

    # A series is a root and a chip always hangs off a series. Enforced in the
    # database as well as the model so a console write cannot produce a tree the
    # documentation resolver has no meaning for.
    add_check_constraint :ingenic_doc_products,
                         "(kind = 'series' AND parent_id IS NULL) OR (kind = 'chip' AND parent_id IS NOT NULL)",
                         name: "ingenic_doc_products_kind_shape"
  end

  def down
    remove_check_constraint :ingenic_doc_products, name: "ingenic_doc_products_kind_shape"
    remove_index :ingenic_doc_products, name: "idx_ingenic_doc_products_kind"
    remove_column :ingenic_doc_products, :kind
  end
end
