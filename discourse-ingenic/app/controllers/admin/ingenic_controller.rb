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
        # The languages this Discourse can serve, each labelled with the
        # name its own speakers use: the same list core's language
        # pickers offer, so a value no visitor's locale can equal is not
        # something an administrator can type in by hand.
        locales: locale_options,
        # Sent with the listing so the editor can offer the classification
        # without a second request. Includes retired entries, because a resource
        # filed under one has to keep showing it until it is reclassified.
        categories: download_categories_json,
        storage_writable: ::Ingenic::DownloadStorage.writable?,
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

      begin
        saved = record.save
      rescue StandardError
        # A refusal that raises - a foreign key, a constraint - never reaches
        # the branch below, and the file this request just wrote would sit
        # on disk with nothing naming it.
        ::Ingenic::DownloadStorage.delete(uploaded) if uploaded
        raise
      end

      if saved
        render_json_dump(download: admin_download_json(record, *counts_for(record)))
      else
        # The bytes are already on disk by the time validation runs, and nothing
        # will ever name them again if the row is refused.
        ::Ingenic::DownloadStorage.delete(uploaded) if uploaded
        render_record_error(record)
      end
    end

    def update_download
      record = IngenicDownload.find(params[:id])
      record.assign_attributes(download_params)
      authorize_ingenic!(record)

      replaced = record.storage_path
      uploaded = apply_upload(record)

      begin
        saved = record.save
      rescue StandardError
        # The row still points at the file it already had, so only the
        # upload this request wrote is cleaned up.
        ::Ingenic::DownloadStorage.delete(uploaded) if uploaded
        raise
      end

      if saved
        # Replacing an upload orphans the file it replaced.
        ::Ingenic::DownloadStorage.delete(replaced) if replaced.present? && replaced != record.storage_path
        render_json_dump(download: admin_download_json(record, *counts_for(record)))
      else
        ::Ingenic::DownloadStorage.delete(uploaded) if uploaded
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

      # The applicant's account can have been deleted while the application sat
      # in the queue, and there is then nothing to approve *for*: a grant is a
      # row naming an account. Refused as a sentence the queue already knows how
      # to show, rather than by writing access for nobody.
      if request.user.nil?
        return render_json_error(I18n.t("ingenic.admin_errors.applicant_deleted"), status: 422)
      end

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

    # Points ----------------------------------------------------------------

    # One request for the whole screen: what the rules pay, the most recent
    # movements, and who is holding what.
    #
    # Administrator-only throughout, including the reading. The ledger names
    # accounts and the adjustments move a member's standing on the site, which
    # is the same kind of act as deciding an access request — and that is not
    # delegated to a scoped content manager either.
    def points
      authorize_admin_only!

      render_json_dump(
        rules: IngenicPointRule.ordered.map { |rule| point_rule_json(rule) },
        events: IngenicPointRule::EVENTS,
        entries: IngenicPointEntry.includes(:user, :awarded_by).recent.limit(100).map { |entry| point_entry_json(entry) },
        balances: IngenicPointBalance.top.includes(:user).limit(50).map { |row| point_balance_json(row) },
        totals: point_totals,
        enabled: ::Ingenic::Points.enabled?,
        exclude_staff: SiteSetting.ingenic_points_exclude_staff,
      )
    end

    # The amounts and the wording, which is all of a rule an admin is allowed to
    # change. The event itself is the ledger's vocabulary, and a rule for an
    # event nothing fires would award points for something that never happens.
    def update_point_rule
      authorize_admin_only!
      record = IngenicPointRule.find(params[:id])
      record.assign_attributes(point_rule_params)
      save_or_error(record) { render_json_dump(rule: point_rule_json(record)) }
    end

    # A hand-written movement, with the note that explains it.
    #
    # Works while points are switched off, on purpose: the switch stops the
    # forum handing points out on its own, and this is somebody deciding.
    def adjust_points
      authorize_admin_only!

      # By username, because that is what the account picker on the screen hands
      # back and what an administrator already knows. It is also the value the
      # ledger prints, so the row a mistake was noticed on names its own account.
      username = params[:username].to_s.strip
      user = username.present? ? User.find_by_username(username) : nil
      return render_json_error(I18n.t("ingenic.admin_errors.user_not_found"), status: 404) if user.nil?

      amount = params[:points].to_i
      if amount.zero?
        return render_json_error(I18n.t("ingenic.admin_errors.points_amount_blank"), status: 422)
      end

      entry =
        ::Ingenic::Points.adjust(
          user: user,
          points: amount,
          note: params[:note].to_s.strip.first(500).presence,
          by: current_user,
        )

      render_json_dump(
        entry: entry && point_entry_json(entry),
        balance: ::Ingenic::Points.total_for(user),
      )
    end

    # Recomputes every balance from the ledger. The repair for the day the
    # numbers and the rows behind them disagree.
    def rebuild_points
      authorize_admin_only!
      render_json_dump(::Ingenic::Points.rebuild!)
    end

    # The ledger, one account at a time. The screen shows the recent movements
    # already; this is for when somebody asks why their number is what it is.
    def point_entries
      authorize_admin_only!

      scope = IngenicPointEntry.recent
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

      render_json_dump(
        # Counted before the cap, so the page can say how many there are as well
        # as showing the first slice of them.
        total: scope.count,
        entries: scope.includes(:user, :awarded_by).limit(200).map { |entry| point_entry_json(entry) },
      )
    end

    # Site content ----------------------------------------------------------

    # One request for the whole page. All three lists are short and all three are
    # drawn together, so fetching them separately would only add three round
    # trips to a screen whose entire content is what comes back.
    def site
      authorize_admin_only!

      render_json_dump(
        homepage_blocks: DiscourseIngenic::ConfigParser.homepage_blocks,
        promotions: IngenicPromotion.ordered.map { |record| promotion_json(record) },
        social_links: IngenicSocialLink.ordered.map { |record| social_link_json(record) },
        footer_columns:
          IngenicFooterColumn.includes(:links).ordered.map { |record| footer_column_json(record) },
      )
    end

    # The front page's layout: which blocks it draws and in what order.
    #
    # The list is replaced whole rather than edited row by row, because a block
    # has no identity apart from its place in the list — reordering two of them
    # is a change to the list, not to either one. A type the renderer does not
    # know is refused rather than dropped: saved-and-invisible is the one
    # outcome an editor could not see anywhere.
    def update_homepage_blocks
      authorize_admin_only!

      blocks = params[:blocks]
      blocks = JSON.parse(blocks) if blocks.is_a?(String)

      if !blocks.is_a?(Array) || !blocks.all? { |block| block.is_a?(Hash) }
        return render_json_error(I18n.t("ingenic.admin_errors.invalid_homepage_blocks"), status: 422)
      end

      normalized = blocks.map.with_index do |block, index|
        type = block["type"].to_s
        if !DiscourseIngenic::ConfigParser::HOMEPAGE_BLOCK_TYPES.include?(type)
          return render_json_error(
            I18n.t("ingenic.admin_errors.invalid_homepage_blocks"),
            status: 422,
          )
        end

        layout = block["layout"].to_s
        limit = block["limit"].to_s.to_i
        {
          "type" => type,
          "layout" => DiscourseIngenic::ConfigParser::HOMEPAGE_LAYOUTS.include?(layout) ? layout : "",
          "position" => index,
          # Zero is "not given", not "show none": a block with no limit would
          # draw whatever it found, which is the one thing the field exists to
          # prevent.
          "limit" => limit.zero? ? 5 : limit.clamp(1, 50),
          "category" => block["category"].to_s.strip,
          "title" => block["title"].to_s.strip,
          "categories" => DiscourseIngenic::ConfigParser.slug_list(block["categories"]),
          "show_all" => block["show_all"] != false,
        }
      end

      SiteSetting.ingenic_homepage_blocks = JSON.generate(normalized)
      render_json_dump(homepage_blocks: DiscourseIngenic::ConfigParser.homepage_blocks)
    rescue JSON::ParserError
      render_json_error(I18n.t("ingenic.admin_errors.invalid_homepage_blocks"), status: 422)
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

    # No `published`: a version has no such column, and permitting one made a
    # request that carried it (the shape an older client would send, and the
    # shape every other form in this controller sends) raise
    # `UnknownAttributeError` — a 500 where the version should simply have been
    # created. What a reader may see is decided page by page.
    def version_params
      params.permit(:product_id, :slug, :label, :locale, :latest, :deprecated, :released_on, :position)
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

    # The languages this site actually publishes in, each labelled with the
    # name its own speakers use. The front end shows a resource to whoever
    # is reading in that locale, so a resource filed under a language the
    # site does not serve is one nobody ever sees - and, like a
    # misspelling, it reports nothing. Discourse carries translations for
    # forty languages this site does not publish in, so they are not
    # offered.
    def locale_options
      names = LocaleSiteSetting.values.index_by { |option| option[:value].to_s }

      served_locales.map do |code|
        { value: code, name: names.dig(code, :native_name).presence || code }
      end
    end

    # What this site serves, rather than what Discourse has translations
    # for: the language an anonymous reader gets, the plugin's own default,
    # and the languages content localisation is switched on for.
    def served_locales
      codes = [SiteSetting.default_locale, SiteSetting.ingenic_default_locale]
      if SiteSetting.content_localization_enabled
        codes.concat(Array(SiteSetting.content_localization_supported_locales))
      end

      codes.map { |code| code.to_s.strip }.reject(&:empty?).uniq
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
          :point_cost,
        )

      # "No category" comes back from the picker as an empty string, or as
      # the sentinel the ui-kit select uses for its first option. The
      # foreign key would refuse either, and null means unfiled.
      category_id = permitted[:category_id].to_s
      permitted[:category_id] = nil if category_id.empty? || category_id == "__NONE__"
      permitted
    end

    def permission_params
      params.permit(:user_id, :group_id, :resource_type, :resource_id, :permission)
    end

    # The event is deliberately not permitted: it is the ledger's vocabulary,
    # and renaming one would orphan every entry already written under it.
    def point_rule_params
      params.permit(:points, :label, :published, :position)
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
      unless ::Ingenic::DownloadStorage.writable?
        record.errors.add(:base, I18n.t("ingenic.admin_errors.storage_unavailable"))
        return nil
      end

      stored = ::Ingenic::DownloadStorage.store(file)
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
          "original_filename",
          "sha256",
          "released_on",
          "published",
          "position",
          "access_level",
          "point_cost",
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
        # A deleted applicant leaves both blank. The queue draws the row without
        # a name rather than dropping it: the application and the answer it got
        # are still the record of what happened here.
        "username" => request.user&.username,
        "user_email" => request.user&.email,
        "download_id" => request.download_id,
        "download_name" => request.download.name,
        "profile_summary" => profile&.summary(limit: 6).presence,
      }
    end

    def download_grant_json(grant)
      {
        "id" => grant.id,
        "user_id" => grant.user_id,
        # Blank for a grant whose account has been deleted, which lets nobody in
        # and is still worth showing as a decision that was made.
        "username" => grant.user&.username,
        "download_id" => grant.download_id,
        "download_name" => grant.download.name,
        "active" => grant.active?,
        "expires_at" => grant.expires_at&.iso8601,
        "revoked_at" => grant.revoked_at&.iso8601,
        "note" => grant.note,
        "created_at" => grant.created_at.iso8601,
      }
    end

    def point_rule_json(rule)
      rule.attributes.slice("id", "event", "label", "points", "position", "published")
    end

    def point_entry_json(entry)
      {
        "id" => entry.id,
        "created_at" => entry.created_at.iso8601,
        "user_id" => entry.user_id,
        "username" => entry.user&.username,
        "points" => entry.points,
        "event" => entry.event,
        "reason" => entry.reason,
        "note" => entry.note,
        # Named for what it was for, so a row about a post that has since been
        # deleted still reads as something rather than as a bare id.
        "subject" => entry.subject_type,
        "subject_id" => entry.subject_id,
        "awarded_by" => entry.awarded_by&.username,
      }
    end

    def point_balance_json(row)
      {
        "user_id" => row.user_id,
        "username" => row.user&.username,
        "points" => row.points,
        "updated_at" => row.updated_at.iso8601,
      }
    end

    # What the screen puts at the top. Summed from the ledger rather than from
    # the balances, because the ledger is the authority and the difference
    # between the two is exactly what the repair button is for.
    #
    # Broken out by what the movements were rather than shown as one negative
    # total: "taken back because the post was deleted" and "spent on a download"
    # are different facts about the forum, and adding them together hides both.
    def point_totals
      by_event = IngenicPointEntry.group(:event).sum(:points)

      {
        # Only the earning rules, so this is what the forum paid out for
        # contributions rather than everything that ever went up.
        "earned" => IngenicPointRule::EVENTS.sum { |event| by_event[event] || 0 },
        "reversed" => (by_event[IngenicPointEntry::REVERSAL] || 0).abs,
        "spent" => (by_event[IngenicPointEntry::DOWNLOAD] || 0).abs,
        "adjusted" => by_event[IngenicPointEntry::MANUAL] || 0,
        # Not a movement but a state: points currently set aside behind standing
        # 悬赏. The bounty events themselves net to nothing — every escrow is
        # either released or returned, and the two add up to what was taken — so
        # they are not a bucket here. This is the figure an administrator
        # actually wants, which is how much is promised right now.
        "escrowed" => IngenicBounty.live.sum(:points),
        "holders" => IngenicPointBalance.where("points > 0").count,
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
