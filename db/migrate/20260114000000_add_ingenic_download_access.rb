# frozen_string_literal: true

class AddIngenicDownloadAccess < ActiveRecord::Migration[7.2]
  def change
    # Files an admin uploads are stored on the server rather than linked, which
    # is what makes access control meaningful — a redirect to a public URL is
    # not a permission check. A row therefore has either a URL or a stored file,
    # so the old not-null on file_url has to go.
    change_column_null :ingenic_downloads, :file_url, true
    add_column :ingenic_downloads, :access_level, :string, null: false, default: "public_login"
    add_column :ingenic_downloads, :storage_path, :string
    add_column :ingenic_downloads, :original_filename, :string
    add_column :ingenic_downloads, :file_sha256, :string
    add_index :ingenic_downloads, :access_level

    create_table :ingenic_developer_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      # The form is admin-configurable, so the answers are stored as a document
      # rather than as columns. That keeps a change of form from being a
      # migration, at the cost of not being able to index a single answer.
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    create_table :ingenic_download_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :download, null: false, foreign_key: { to_table: :ingenic_downloads }
      t.string :status, null: false, default: "pending"
      t.text :message
      t.text :review_note
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :ingenic_download_requests,
              %i[user_id download_id status],
              name: "idx_ingenic_requests_lookup"
    # One open application per person per resource. Enforced here rather than in
    # the model because two submissions arriving at once would both pass a
    # model-level check.
    add_index :ingenic_download_requests,
              %i[user_id download_id],
              unique: true,
              where: "status = 'pending'",
              name: "idx_ingenic_requests_one_pending"

    create_table :ingenic_download_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.references :download, null: false, foreign_key: { to_table: :ingenic_downloads }
      t.references :request,
                   foreign_key: {
                     to_table: :ingenic_download_requests,
                   }
      t.references :granted_by, foreign_key: { to_table: :users }
      t.references :revoked_by, foreign_key: { to_table: :users }
      t.datetime :expires_at
      t.datetime :revoked_at
      t.text :note
      t.timestamps
    end

    # One grant row per person per resource, revoked and reinstated in place.
    # The audit trail lives in the requests table, so a second row here would
    # only create a way for two contradictory answers to exist at once.
    add_index :ingenic_download_grants, %i[user_id download_id], unique: true
  end
end
