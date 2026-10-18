# frozen_string_literal: true

# One chip can have three different people looking after it: the writer of its
# documentation, the engineer who publishes its SDKs, and the person who keeps
# its development boards up to date. Before this column a grant on a product
# said only "may manage this chip", so any one of them could edit all three.
#
# `area` narrows a grant to one of those jobs. Existing rows are backfilled by
# the resource they already name, which is what the old interface meant: a page
# or a product was documentation, a download was a download, a board was a
# board.
class AddIngenicPermissionArea < ActiveRecord::Migration[7.2]
  AREAS = %w[documentation downloads boards].freeze

  def up
    add_column :ingenic_permissions, :area, :string, null: false, default: "documentation"

    execute <<~SQL
      UPDATE ingenic_permissions
      SET area = 'downloads'
      WHERE resource_type = 'IngenicDownload'
    SQL

    execute <<~SQL
      UPDATE ingenic_permissions
      SET area = 'boards'
      WHERE resource_type = 'IngenicBoard'
    SQL

    # The default was only there so the column could be added to rows that
    # already existed. From here on the model names the area, and a row that
    # forgot to would be a grant with no meaning rather than a documentation
    # grant by accident.
    change_column_default :ingenic_permissions, :area, from: "documentation", to: nil

    remove_index :ingenic_permissions, name: "idx_ingenic_permissions_user_scope"
    remove_index :ingenic_permissions, name: "idx_ingenic_permissions_group_scope"

    add_index :ingenic_permissions,
              %i[user_id area resource_type resource_id permission],
              unique: true,
              name: "idx_ingenic_permissions_user_scope"
    add_index :ingenic_permissions,
              %i[group_id area resource_type resource_id permission],
              unique: true,
              name: "idx_ingenic_permissions_group_scope"
    add_index :ingenic_permissions,
              %i[area resource_type resource_id],
              name: "idx_ingenic_permissions_area_scope"
  end

  def down
    remove_index :ingenic_permissions, name: "idx_ingenic_permissions_area_scope"
    remove_index :ingenic_permissions, name: "idx_ingenic_permissions_user_scope"
    remove_index :ingenic_permissions, name: "idx_ingenic_permissions_group_scope"

    add_index :ingenic_permissions,
              %i[user_id resource_type resource_id permission],
              unique: true,
              name: "idx_ingenic_permissions_user_scope"
    add_index :ingenic_permissions,
              %i[group_id resource_type resource_id permission],
              unique: true,
              name: "idx_ingenic_permissions_group_scope"

    remove_column :ingenic_permissions, :area
  end
end
