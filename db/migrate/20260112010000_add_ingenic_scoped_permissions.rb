# frozen_string_literal: true

class AddIngenicScopedPermissions < ActiveRecord::Migration[7.2]
  def change
    add_reference :ingenic_doc_products,
                  :parent,
                  foreign_key: { to_table: :ingenic_doc_products },
                  index: true

    create_table :ingenic_permissions do |t|
      t.references :user, foreign_key: true
      t.references :group, foreign_key: true
      t.string :resource_type, null: false
      t.bigint :resource_id, null: false
      t.string :permission, null: false, default: "manage"
      t.timestamps
    end

    add_index :ingenic_permissions,
              %i[user_id resource_type resource_id permission],
              unique: true,
              name: "idx_ingenic_permissions_user_scope"
    add_index :ingenic_permissions,
              %i[group_id resource_type resource_id permission],
              unique: true,
              name: "idx_ingenic_permissions_group_scope"
    add_check_constraint :ingenic_permissions,
                         "(user_id IS NOT NULL AND group_id IS NULL) OR (user_id IS NULL AND group_id IS NOT NULL)",
                         name: "ingenic_permissions_one_principal"
  end
end
