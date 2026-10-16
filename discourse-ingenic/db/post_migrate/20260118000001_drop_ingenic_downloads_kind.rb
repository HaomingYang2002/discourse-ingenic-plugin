# frozen_string_literal: true

# The drop that `add_ingenic_download_categories` could not do itself.
#
# Discourse patches migrations so that `remove_column` and `rename_column` raise
# unless the file sits under `db/post_migrate`: a running application server may
# still be reading the column, so the drop waits until the new code is the only
# code running. `add_ingenic_download_categories` dropped it inline, which meant
# the migration set aborted at that line and nothing after it ever ran — the
# plugin could not be installed at all, and no static check said so.
#
# Post-deploy migrations are read from a plugin's own `db/post_migrate` too, so
# this is where the drop belongs. Everything else that migration does — the
# categories table, the reference and the index — is a normal schema change and
# stayed where it was.
class DropIngenicDownloadsKind < ActiveRecord::Migration[7.2]
  def up
    # A column no model reads any more: `IngenicDownload` has taken its
    # classification from `category_id` since the migration next door. Nothing
    # in the plugin names `kind` at all.
    remove_column :ingenic_downloads, :kind
  end

  def down
    add_column :ingenic_downloads, :kind, :string

    # Back the way it came: the category's name was the enum's value.
    execute <<~SQL
      UPDATE ingenic_downloads
      SET kind = ingenic_download_categories.name
      FROM ingenic_download_categories
      WHERE ingenic_downloads.category_id = ingenic_download_categories.id
    SQL
  end
end
