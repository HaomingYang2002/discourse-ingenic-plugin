# frozen_string_literal: true

class AddIngenicDownloadLogs < ActiveRecord::Migration[7.2]
  def change
    # One delivery of one file to one account.
    #
    # An approval is permanent, so the grant table says who *may* download and
    # never says who *did*. This is that record: the Ingenic team asked to be
    # able to see, afterwards, which account took which file.
    #
    # Append-only, so there is no updated_at — nothing in the plugin edits a row
    # once it is written.
    create_table :ingenic_download_logs do |t|
      # Cascade rather than restrict: deleting an account or a resource should
      # not fail because a log row mentions it. The name is also copied onto the
      # row so the entry still reads correctly in the common case where the
      # account is anonymised and the resource is unpublished instead.
      t.references :user,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade,
                   }
      t.references :download,
                   null: false,
                   foreign_key: {
                     to_table: :ingenic_downloads,
                     on_delete: :cascade,
                   }
      t.string :resource_name, null: false
      t.string :version
      t.string :ip_address
      t.string :user_agent
      t.string :locale
      t.datetime :created_at, null: false
    end

    add_index :ingenic_download_logs,
              %i[download_id created_at],
              name: "idx_ingenic_download_logs_by_resource"
    add_index :ingenic_download_logs,
              %i[user_id created_at],
              name: "idx_ingenic_download_logs_by_user"
  end
end
