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
      record.assign_attributes(product_params)
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
      record.assign_attributes(version_params)
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
      record.assign_attributes(page_params)
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
      record.assign_attributes(board_params)
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
        # Sent with the listing so the editor can offer the classification
        # without a second request. Includes retired entries, because a resource
        # filed under one has to keep showing it until it is reclassified.
        categories: download_categories_json,
        storage_writable: Ingenic::DownloadStorage.writable?,
        # The log names accounts, so a scoped content manager is not offered the
        # tab. Sent as a flag rather than letting the page ask and be refused,
        # because a refused request per page load is a worse way to say no.
        can_read_log: current_user.admin?,
      )
    end

    # Categories ------------------------------------------------------------

    def create_download_category
      authorize_admin_only!
      record = IngenicDownloadCategory.new(download_category_params)
      save_or_error(record) { render_json_dump(category: category_json(record)) }
    end

    def update_download_category
      authorize_admin_only!
      record = IngenicDownloadCategory.find(params[:id])
      record.assign_attributes(download_category_params)
      save_or_error(record) { render_json_dump(category: category_json(record)) }
    end

    # The resources filed under it survive as unfiled. Retiring a label is not a
    # reason to lose the files someone spent a week uploading and classifying.
    def destroy_download_category
      authorize_admin_only!
      IngenicDownloadCategory.find(params[:id]).destroy!
      head :no_content
    end

    # The record of what was actually taken. Read-only: this is evidence, and an
    # edit surface over it would be one more thing to trust.
    def download_logs
      authorize_admin_only!

      logs = IngenicDownloadLog.includes(:user, :download).recent
      logs = logs.where(download_id: params[:download_id]) if params[:download_id].present?

      render_json_dump(
        logs: logs.limit(500).map { |log| download_log_json(log) },
        total: IngenicDownloadLog.count,
        by_resource: download_log_summary,
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
      record.assign_attributes(download_params)
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

    # Site content ----------------------------------------------------------

    # One request for the whole page. All three lists are short and all three are
    # drawn together, so fetching them separately would only add three round
    # trips to a screen whose entire content is what comes back.
    def site
      authorize_admin_only!

      render_json_dump(
        promotions: IngenicPromotion.ordered.map { |record| promotion_json(record) },
        social_links: IngenicSocialLink.ordered.map { |record| social_link_json(record) },
        footer_columns:
          IngenicFooterColumn.includes(:links).ordered.map { |record| footer_column_json(record) },
      )
    end

    # Promotions ------------------------------------------------------------

    def create_promotion
      authorize_admin_only!
      record = IngenicPromotion.new(promotion_params)
      save_or_error(record) { render_json_dump(promotion: promotion_json(record)) }
    end

    def update_promotion
      authorize_admin_only!
      record = IngenicPromotion.find(params[:id])
      record.assign_attributes(promotion_params)
      save_or_error(record) { render_json_dump(promotion: promotion_json(record)) }
    end

    # Deleted rather than withdrawn, unlike a download or a board. Nothing
    # refers to a promotion, so there is no history to keep and an editor who
    # says "remove this" means remove it. Unpublishing is the way to take one
    # down without losing the wording.
    def destroy_promotion
      authorize_admin_only!
      IngenicPromotion.find(params[:id]).destroy!
      head :no_content
    end

    # Partner platforms -----------------------------------------------------

    def create_social_link
      authorize_admin_only!
      record = IngenicSocialLink.new(social_link_params)
      save_or_error(record) { render_json_dump(social_link: social_link_json(record)) }
    end

    def update_social_link
      authorize_admin_only!
      record = IngenicSocialLink.find(params[:id])
      record.assign_attributes(social_link_params)
      save_or_error(record) { render_json_dump(social_link: social_link_json(record)) }
    end

    def destroy_social_link
      authorize_admin_only!
      IngenicSocialLink.find(params[:id]).destroy!
      head :no_content
    end

    # Footer columns --------------------------------------------------------

    def create_footer_column
      authorize_admin_only!
      record = IngenicFooterColumn.new(footer_column_params)
      save_or_error(record) { render_json_dump(footer_column: footer_column_json(record)) }
    end

    def update_footer_column
      authorize_admin_only!
      record = IngenicFooterColumn.find(params[:id])
      record.assign_attributes(footer_column_params)
      save_or_error(record) { render_json_dump(footer_column: footer_column_json(record)) }
    end

    # Takes its links with it. They have no meaning apart from the heading, and
    # leaving them behind would make them unreachable rather than preserved.
    def destroy_footer_column
      authorize_admin_only!
      IngenicFooterColumn.find(params[:id]).destroy!
      head :no_content
    end

    # Footer links ----------------------------------------------------------

    def create_footer_link
      authorize_admin_only!
      record = IngenicFooterLink.new(footer_link_params)
      save_or_error(record) { render_json_dump(footer_link: footer_link_json(record)) }
    end

    def update_footer_link
      authorize_admin_only!
      record = IngenicFooterLink.find(params[:id])
      record.assign_attributes(footer_link_params)
      save_or_error(record) { render_json_dump(footer_link: footer_link_json(record)) }
    end

    def destroy_footer_link
      authorize_admin_only!
      IngenicFooterLink.find(params[:id]).destroy!
      head :no_content
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

    # Saves and renders, or reports why not.
    #
    # Every update action assigns the form to its record before it authorizes,
    # rather than after: the form may move a record to a different parent — a
    # page to another version, a chip to another series — and the scope that has
    # to permit the write is the one the record is moving into.
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
          :purchase_url,
          :published,
          :position,
        )

      # An empty picker option means "no chip from the tree", which is null
      # rather than a blank string the foreign key would refuse.
      permitted[:product_id] = permitted[:product_id].presence
      permitted
    end

    def download_params
      permitted =
        params.permit(
          :product_slug,
          :category_id,
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

      # "No category" comes back from the picker as an empty string, which the
      # foreign key would refuse; null is the value that means unfiled.
      permitted[:category_id] = permitted[:category_id].presence
      permitted
    end

    def permission_params
      params.permit(:user_id, :group_id, :resource_type, :resource_id, :permission)
    end

    def download_category_params
      params.permit(:name, :locale, :position, :published)
    end

    def promotion_params
      permitted =
        params.permit(
          :corner_label,
          :title,
          :description,
          :button_label,
          :button_href,
          :button_external,
          :image_url,
          :locale,
          :position,
          :published,
        )

      # The two dates come from datetime inputs, which submit an empty string
      # when cleared. Assigning the strings directly would leave the column set
      # to a value Rails parses on write and a validation cannot read.
      permitted[:starts_at] = parse_time(params[:starts_at])
      permitted[:ends_at] = parse_time(params[:ends_at])
      permitted
    end

    def social_link_params
      params.permit(
        :label,
        :kind,
        :href,
        :image_url,
        :qr_image_url,
        :qr_caption,
        :position,
        :published,
      )
    end

    def footer_column_params
      params.permit(:title, :position, :published)
    end

    def footer_link_params
      params.permit(:column_id, :label, :href, :external, :position, :published)
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
          "category_id",
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
          # Read through the association rather than off a column, because the
          # name can be corrected in the category list without touching every
          # resource filed under it.
          "category_name" => download.category_name,
          "pending_requests" => pending,
          "active_grants" => granted,
        )
    end

    def category_json(category)
      category.attributes.slice("id", "name", "locale", "position", "published")
    end

    # Counted in one query rather than one per row: the management page shows
    # every category, and a count per category is the classic way to turn a
    # screen that loads instantly into one that does not.
    def download_categories_json
      counts = IngenicDownload.group(:category_id).count
      IngenicDownloadCategory.ordered.map do |category|
        category_json(category).merge("download_count" => counts[category.id] || 0)
      end
    end

    def download_log_json(log)
      {
        "id" => log.id,
        "created_at" => log.created_at.iso8601,
        "user_id" => log.user_id,
        "username" => log.user&.username,
        "download_id" => log.download_id,
        "resource_name" => log.resource_name,
        "version" => log.version,
        "ip_address" => log.ip_address,
        "locale" => log.locale,
      }
    end

    # Counted over the whole log rather than over the slice on screen, and
    # capped: this is the answer to "which files are being taken", which the
    # first few dozen rows already give.
    def download_log_summary
      counts = IngenicDownloadLog.group(:download_id).count
      names = IngenicDownload.where(id: counts.keys).pluck(:id, :name).to_h

      counts
        .sort_by { |download_id, count| [-count, download_id] }
        .first(50)
        .map do |download_id, count|
          { "download_id" => download_id, "name" => names[download_id], "count" => count }
        end
    end

    def promotion_json(promotion)
      promotion
        .attributes
        .slice(
          "id",
          "corner_label",
          "title",
          "description",
          "button_label",
          "button_href",
          "button_external",
          "image_url",
          "locale",
          "position",
          "published",
        )
        .merge(
          "starts_at" => promotion.starts_at&.iso8601,
          "ends_at" => promotion.ends_at&.iso8601,
          # Sent as well as the dates: the list has to say whether an entry is
          # on the page right now, and working that out from two timestamps in
          # the browser is a second implementation of the same rule.
          "live" => promotion.live?,
        )
    end

    def social_link_json(link)
      link.attributes.slice(
        "id",
        "label",
        "kind",
        "href",
        "image_url",
        "qr_image_url",
        "qr_caption",
        "position",
        "published",
      )
    end

    def footer_column_json(column)
      column
        .attributes
        .slice("id", "title", "position", "published")
        .merge("links" => column.links.map { |link| footer_link_json(link) })
    end

    def footer_link_json(link)
      link.attributes.slice("id", "column_id", "label", "href", "external", "position", "published")
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
          "purchase_url",
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
