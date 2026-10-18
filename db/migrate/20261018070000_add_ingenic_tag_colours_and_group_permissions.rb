# frozen_string_literal: true

class AddIngenicTagColoursAndGroupPermissions < ActiveRecord::Migration[7.2]
  def change
    # A tag's colour is a presentation decision the site owner keeps changing:
    # a new chip family arrives, a subject stops being "technical", an
    # announcement tag is retired. Baking the names into the theme meant every
    # such change was a code change, so the mapping is a row here and the theme
    # reads it from the site payload.
    #
    # The name is the tag itself rather than a foreign key: Discourse deletes a
    # tag row when its last topic loses it, and a colour that outlives a tag is
    # harmless — it is waiting for the name to be used again — while a cascading
    # delete would silently throw the choice away. `family` is one of four
    # semantic families, not a hex value, so contrast stays the theme's promise
    # rather than something an editor can accidentally break.
    create_table :ingenic_tag_colours do |t|
      t.string :tag_name, null: false
      t.string :family, null: false, default: "sky"
      t.timestamps
    end

    add_index :ingenic_tag_colours, :tag_name, unique: true

    # Which groups may reach which management screen. This is the coarse layer
    # beside `ingenic_permissions`, which grants one product, page, board or
    # download to one user or group. A feature here says "everything on this
    # screen", which is what an administrator means by putting an account in a
    # content group; the per-record grants remain for narrower delegation.
    #
    # `feature` is a fixed vocabulary in the model, not a foreign key: the list
    # is the plugin's capabilities, and a row naming one that no longer exists
    # should be refused rather than silently ignored.
    create_table :ingenic_group_permissions do |t|
      t.integer :group_id, null: false
      t.string :feature, null: false
      t.timestamps
    end

    add_index :ingenic_group_permissions,
              %i[group_id feature],
              unique: true,
              name: "idx_ingenic_group_permissions_unique"

    add_foreign_key :ingenic_group_permissions,
                    :groups,
                    column: :group_id,
                    on_delete: :cascade
  end
end
