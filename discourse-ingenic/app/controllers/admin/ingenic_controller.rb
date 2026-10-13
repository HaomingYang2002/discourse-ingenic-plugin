# frozen_string_literal: true

module Admin
  class IngenicController < Ingenic::BaseController
    def index
      render body: nil
    end

    # Documentation ---------------------------------------------------------

    def documentation
      render_json_dump(series: visible_series.map { |record| product_json(record, include_children: true) })
    end

    def product
      record = IngenicDocProduct.find(params[:id])
      authorize_ingenic!(record)
      render_json_dump(product: product_json(record, include_versions: true))
    end

    def create_product
      record = IngenicDocProduct.new(product_params)
      authorize_create!(record.parent)
      save_or_error(record) { render_json_dump(product: product_json(record)) }
    end

    def update_product
      record = IngenicDocProduct.find(params[:id])
      authorize_ingenic!(record)
      save_or_error(record) { render_json_dump(product: product_json(record, include_versions: true)) }
    end

    def destroy_product
      record = IngenicDocProduct.find(params[:id])
      authorize_ingenic!(record)
      record.destroy!
      head :no_content
    rescue ActiveRecord::DeleteRestrictionError
      render_json_error(I18n.t("ingenic.admin_errors.has_children"), status: 422)
    end

    def create_version
      record = IngenicDocVersion.new(version_params)
      authorize_ingenic!(record.product)
      save_or_error(record) { render_json_dump(version: version_json(record)) }
    end

    def update_version
      record = IngenicDocVersion.find(params[:id])
      authorize_ingenic!(record)
      save_or_error(record) { render_json_dump(version: version_json(record)) }
    end

    def destroy_version
      record = IngenicDocVersion.find(params[:id])
      authorize_ingenic!(record)
      record.destroy!
      head :no_content
    end

    # The whole editing surface for one version in a single response: the
    # product tree it belongs to, its sibling versions, and every page it
    # resolves to with inherited pages flagged.
    def version_tree
      version = IngenicDocVersion.find(params[:id])
      authorize_ingenic!(version)

      render_json_dump(
        product: product_json(version.product, include_versions: true),
        version: version_json(version),
        pages: version.page_tree.map { |page| admin_page_json(page) },
      )
    end

    def create_page
      record = IngenicDocPage.new(page_params)
      authorize_ingenic!(record.version)
      save_or_error(record) { render_json_dump(page: page_json(record)) }
    end

    def update_page
      record = IngenicDocPage.find(params[:id])
      authorize_ingenic!(record.version)
      save_or_error(record) { render_json_dump(page: page_json(record)) }
    end

    def destroy_page
      record = IngenicDocPage.find(params[:id])
      authorize_ingenic!(record.version)
      record.destroy!
      head :no_content
    end

    # Materialises an inherited page into this version so it can be edited here.
    # Until this runs the version holds no row for the slug, which is exactly
    # what makes it inherit.
    def override_page
      version = IngenicDocVersion.find(params[:version_id])
      authorize_ingenic!(version)

      resolved = version.find_readable_page(params[:slug])
      return render_json_error(I18n.t("ingenic.admin_errors.page_not_found"), status: 404) if resolved.nil?

      # Already owned by this version: editing it is the same request.
      return render_json_dump(page: page_json(resolved.page)) unless resolved.inherited?

      copy = resolved.page.dup
      copy.version_id = version.id
      copy.save!
      render_json_dump(page: page_json(copy), inherited_from: nil)
    end

    # Drops this version's row so the page goes back to inheriting.
    def revert_page
      version = IngenicDocVersion.find(params[:version_id])
      authorize_ingenic!(version)

      row = version.own_page(params[:slug])
      return render_json_error(I18n.t("ingenic.admin_errors.page_not_found"), status: 404) if row.nil?

      row.destroy!
      head :no_content
    end

    # Boards ----------------------------------------------------------------

    def board_list
      boards = ::Ingenic::PermissionResolver.new(current_user).visible_ids(IngenicBoard).ordered

      render_json_dump(
        boards: boards.map { |board| board_json(board) },
        # The chips a board can be filed against, each with the series it sits
        # under, so the picker can offer them without a second request.
        chips: board_chip_options,
      )
    end

    def create_board
      # A board has no parent scope to inherit from, so only an administrator can
      # create one. Scoped managers edit the boards they were granted.
      authorize_create!
      record = IngenicBoard.new(board_params)
      save_or_error(record) { render_json_dump(board: board_json(record)) }
    end

    def update_board
      record = IngenicBoard.find(params[:id])
      authorize_ingenic!(record)
      save_or_error(record) { render_json_dump(board: board_json(record)) }
    end

    def destroy_board
      record = IngenicBoard.find(params[:id])
      authorize_ingenic!(record)
      record.update!(published: false)
      head :no_content
    end

    # Downloads -------------------------------------------------------------

    def download_list
      downloads = ::Ingenic::PermissionResolver.new(current_user).visible_ids(IngenicDownload).ordered
      pending = IngenicDownloadRequest.pending.group(:download_id).count
      granted = IngenicDownloadGrant.active.group(:download_id).count

      render_json_dump(
        downloads:
          downloads.map do |download|
            admin_download_json(download, pending[download.id] || 0, granted[download.id] || 0)
          end,
        access_levels: IngenicDownload::ACCESS_LEVELS,
        kinds: IngenicDownload::KINDS,
        storage_writable: Ingenic::DownloadStorage.writable?,
      )
    end

    def create_download
      # A resource with no parent scope to inherit from is created by an
      # administrator; a scoped manager edits the resources they were granted.
      authorize_create!
      record = IngenicDownload.new(download_params)
      uploaded = apply_upload(record)

      if record.save
        render_json_dump(download: admin_download_json(record, *counts_for(record)))
      else
        # The bytes are already on disk by the time validation runs, and nothing
        # will ever name them again if the row is refused.
        Ingenic::DownloadStorage.delete(uploaded) if uploaded
        render_record_error(record)
      end
    end

    def update_download
      record = IngenicDownload.find(params[:id])
      authorize_ingenic!(record)

      replaced = record.storage_path
      uploaded = apply_upload(record)

      if record.save
        # Replacing an upload orphans the file it replaced.
        Ingenic::DownloadStorage.delete(replaced) if replaced.present? && replaced != record.storage_path
        render_json_dump(download: admin_download_json(record, *counts_for(record)))
      else
        Ingenic::DownloadStorage.delete(uploaded) if uploaded
        render_record_error(record)
      end
    end

    # Withdrawn rather than destroyed: a resource that has been downloaded is
    # referred to by requests and grants, and those records are the audit trail
    # for who was given access to what.
    def destroy_download
      record = IngenicDownload.find(params[:id])
      authorize_ingenic!(record)
      record.update!(published: false)
      head :no_content
    end

    def download_requests
      # Deciding an application is an administrative act rather than a content
      # edit: it hands a named account access to a file, so it is not delegated
      # to a scoped content manager.
      authorize_ingenic!(permissions: true)
      requests = IngenicDownloadRequest.includes(:user, :download).recent.limit(200)

      render_json_dump(
        requests: requests.map { |request| download_request_json(request) },
        pending_count: IngenicDownloadRequest.pending.count,
      )
    end

    def approve_request
      authorize_ingenic!(permissions: true)
      request = IngenicDownloadRequest.find(params[:id])
      request.approve!(
        current_user,
        note: params[:note].to_s.strip.presence,
        expires_at: parse_time(params[:expires_at]),
      )
      Jobs.enqueue(:ingenic_download_decision_email, request_id: request.id)
      render_json_dump(request: download_request_json(request))
    end

    def reject_request
      authorize_ingenic!(permissions: true)
      request = IngenicDownloadRequest.find(params[:id])
      request.reject!(current_user, note: params[:note].to_s.strip.presence)
      Jobs.enqueue(:ingenic_download_decision_email, request_id: request.id)
      render_json_dump(request: download_request_json(request))
    end

    def download_grants
      authorize_ingenic!(permissions: true)
      grants = IngenicDownloadGrant.includes(:user, :download).order(created_at: :desc).limit(200)
      render_json_dump(grants: grants.map { |grant| download_grant_json(grant) })
    end

    def revoke_grant
      authorize_ingenic!(permissions: true)
      grant = IngenicDownloadGrant.find(params[:id])
      grant.revoke!(current_user)
      render_json_dump(grant: download_grant_json(grant))
    end

    # Permissions -----------------------------------------------------------

    def permissions
      authorize_ingenic!(permissions: true)
      render_json_dump(
        permissions:
          IngenicPermission
            .includes(:user, :group)
            .order(:resource_type, :resource_id)
            .map { |permission| permission_json(permission) },
      )
    end

    def create_permission
      authorize_ingenic!(permissions: true)
      record = IngenicPermission.new(permission_params)
      save_or_error(record) { render_json_dump(permission: permission_json(record)) }
    end

    def destroy_permission
      authorize_ingenic!(permissions: true)
      IngenicPermission.find(params[:id]).destroy!
      head :no_content
    end

    private

    def save_or_error(record)
      if record.save
        yield
      else
        render_record_error(record)
      end
    end

    # A scoped manager may hold a grant on a chip without holding one on the
    # series above it, so the series rows are pulled in as containers. Without
    # them the management page would have nothing to hang the chip under.
    def visible_series
      return IngenicDocProduct.series.ordered if current_user.admin?

      ids = ::Ingenic::PermissionResolver.new(current_user).visible_ids(IngenicDocProduct).pluck(:id)
      parent_ids = IngenicDocProduct.where(id: ids).where.not(parent_id: nil).distinct.pluck(:parent_id)
      IngenicDocProduct.series.where(id: ids + parent_ids).ordered
    end

    def product_params
      params.permit(:kind, :parent_id, :slug, :name, :description, :locale, :published, :position)
    end

    def version_params
      params.permit(:product_id, :slug, :label, :locale, :latest, :deprecated, :released_on, :position, :published)
    end

    def page_params
      params.permit(:version_id, :parent_id, :slug, :title, :body, :locale, :topic_url, :published, :position)
    end

    def board_params
      permitted =
        params.permit(
          :slug,
          :name,
          :locale,
          :chip,
          :product_id,
          :description,
          :specs,
          :image_url,
          :documentation_url,
          :application_url,
          :published,
          :position,
        )

      # An empty picker option means "no chip from the tree", which is null
      # rather than a blank string the foreign key would refuse.
      permitted[:product_id] = permitted[:product_id].presence
      permitted
    end

    def download_params
      params.permit(
        :product_slug,
        :kind,
        :version,
        :locale,
        :name,
        :description,
        :platform,
        :architecture,
        :file_url,
        :file_size,
        :sha256,
        :released_on,
        :published,
        :position,
        :access_level,
      )
    end

    def permission_params
      params.permit(:user_id, :group_id, :resource_type, :resource_id, :permission)
    end

    # Writes the uploaded file, if the request carries one, and returns where it
    # went. The path is returned rather than read back off the record so that a
    # refused save can clean up the file it just wrote.
    #
    # A stored file clears any URL the row had: two sources for the same bytes
    # is one more than the delivery endpoint is willing to choose between.
    def apply_upload(record)
      file = params[:file]
      return nil unless file.respond_to?(:read)

      # Reported on the record rather than raised, so the upload form shows the
      # same kind of error as a missing name would.
      unless Ingenic::DownloadStorage.writable?
        record.errors.add(:base, I18n.t("ingenic.admin_errors.storage_unavailable"))
        return nil
      end

      stored = Ingenic::DownloadStorage.store(file)
      record.storage_path = stored[:path]
      record.original_filename = file.original_filename.to_s.presence
      record.file_sha256 = stored[:sha256]
      record.file_size = ActiveSupport::NumberHelper.number_to_human_size(stored[:size])
      record.file_url = nil
      stored[:path]
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    # The counts for the one row a save just returned, as [waiting, granted].
    # The listing counts the whole table in two queries instead; here there is a
    # single row to answer for, and reporting zero would blank out the counters
    # the manager is looking at until the next reload.
    def counts_for(download)
      [
        IngenicDownloadRequest.pending.where(download_id: download.id).count,
        IngenicDownloadGrant.active.where(download_id: download.id).count,
      ]
    end

    def admin_download_json(download, pending, granted)
      download
        .attributes
        .slice(
          "id",
          "product_slug",
          "kind",
          "version",
          "locale",
          "name",
          "description",
          "platform",
          "architecture",
          "file_url",
          "file_size",
          "sha256",
          "released_on",
          "published",
          "position",
          "access_level",
          "file_sha256",
        )
        .merge(
          "stored" => download.stored?,
          "pending_requests" => pending,
          "active_grants" => granted,
        )
    end

    def download_request_json(request)
      profile = IngenicDeveloperProfile.for(request.user)

      {
        "id" => request.id,
        "status" => request.status,
        "message" => request.message,
        "review_note" => request.review_note,
        "created_at" => request.created_at.iso8601,
        "reviewed_at" => request.reviewed_at&.iso8601,
        "user_id" => request.user_id,
        "username" => request.user.username,
        "user_email" => request.user.email,
        "download_id" => request.download_id,
        "download_name" => request.download.name,
        "profile_summary" => profile&.summary(limit: 6).presence,
      }
    end

    def download_grant_json(grant)
      {
        "id" => grant.id,
        "user_id" => grant.user_id,
        "username" => grant.user.username,
        "download_id" => grant.download_id,
        "download_name" => grant.download.name,
        "active" => grant.active?,
        "expires_at" => grant.expires_at&.iso8601,
        "revoked_at" => grant.revoked_at&.iso8601,
        "note" => grant.note,
        "created_at" => grant.created_at.iso8601,
      }
    end

    def product_json(product, include_children: false, include_versions: false)
      data =
        product
          .attributes
          .slice("id", "kind", "parent_id", "slug", "name", "description", "locale", "published", "position")

      if include_children
        data["chips"] = product.children.ordered.map { |child| product_json(child, include_versions: true) }
      end

      if include_versions
        data["versions"] = product.versions.map { |version| version_json(version).merge("page_count" => version.pages.count) }
      end

      data
    end

    def version_json(version)
      version
        .attributes
        .slice("id", "product_id", "slug", "label", "locale", "latest", "deprecated", "released_on", "position", "published")
    end

    def page_json(page)
      page
        .attributes
        .slice("id", "version_id", "parent_id", "slug", "title", "body", "locale", "topic_url", "published", "position")
    end

    # A page as the management page needs it: the stored row plus what the
    # resolver decided about it.
    def admin_page_json(resolved)
      page_json(resolved.page).merge(
        "depth" => resolved.depth,
        "parent_slug" => resolved.parent_slug,
        "inherited" => resolved.inherited?,
        "inherited_from_id" => resolved.inherited? ? resolved.inherited_from.id : nil,
        "inherited_from_label" => resolved.inherited? ? resolved.inherited_from.label : nil,
      )
    end

    def board_chip_options
      IngenicDocProduct
        .chips
        .includes(:parent)
        .ordered
        .map do |chip|
          {
            "id" => chip.id,
            "name" => chip.name,
            "slug" => chip.slug,
            "series_name" => chip.parent&.name,
          }
        end
    end

    def board_json(board)
      board
        .attributes
        .slice(
          "id",
          "slug",
          "name",
          "locale",
          "chip",
          "product_id",
          "description",
          "specs",
          "image_url",
          "documentation_url",
          "application_url",
          "published",
          "position",
        )
        .merge(
          # Server-derived rather than read off the row: the tree is what decides
          # which chip a board shows, and the label column is only the fallback.
          "chip_name" => board.chip_name,
          "series_name" => board.series_name,
        )
    end

    def permission_json(permission)
      permission.attributes.slice("id", "user_id", "group_id", "resource_type", "resource_id", "permission")
    end
  end
end
