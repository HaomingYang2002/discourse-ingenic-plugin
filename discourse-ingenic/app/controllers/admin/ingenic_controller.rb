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
      render_json_dump(boards: boards.map { |board| board_json(board) })
    end

    def board
      record = IngenicBoard.find(params[:id])
      authorize_ingenic!(record)
      render_json_dump(board: board_json(record))
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
      params.permit(:slug, :name, :locale, :chip, :description, :image_url, :documentation_url, :application_url, :published, :position)
    end

    def permission_params
      params.permit(:user_id, :group_id, :resource_type, :resource_id, :permission)
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

    def board_json(board)
      board
        .attributes
        .slice("id", "slug", "name", "locale", "chip", "description", "image_url", "documentation_url", "application_url", "published", "position")
    end

    def permission_json(permission)
      permission.attributes.slice("id", "user_id", "group_id", "resource_type", "resource_id", "permission")
    end
  end
end
