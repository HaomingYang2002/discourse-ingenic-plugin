# frozen_string_literal: true

module Admin
  class IngenicController < Ingenic::BaseController
    def index
      render body: nil
    end

    def documentation
      products = ::Ingenic::PermissionResolver.new(current_user).visible_ids(IngenicDocProduct).ordered
      render_json_dump(products: products.map { |product| product_json(product) })
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

    def create_page
      record = IngenicDocPage.new(page_params)
      authorize_ingenic!(record.version)
      save_or_error(record) { render_json_dump(page: page_json(record)) }
    end

    def update_page
      record = IngenicDocPage.find(params[:id])
      authorize_ingenic!(record)
      save_or_error(record) { render_json_dump(page: page_json(record)) }
    end

    def destroy_page
      record = IngenicDocPage.find(params[:id])
      authorize_ingenic!(record)
      record.destroy!
      head :no_content
    end

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

    def permissions
      authorize_ingenic!(permissions: true)
      render_json_dump(permissions: IngenicPermission.includes(:user, :group).order(:resource_type, :resource_id).map { |permission| permission_json(permission) })
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

    def product_params
      params.permit(:slug, :name, :description, :locale, :published, :position, :parent_id)
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

    def product_json(product, include_versions: false)
      data = product.attributes.slice("id", "slug", "name", "description", "locale", "published", "position", "parent_id")
      if include_versions
        data["versions"] = product.versions.map do |version|
          version.attributes.slice("id", "slug", "label", "locale", "latest", "deprecated", "released_on", "position", "published").merge(
            "pages" => version.pages.ordered.map { |page| page_json(page) },
          )
        end
      end
      data
    end

    def version_json(version)
      version.attributes.slice("id", "product_id", "slug", "label", "locale", "latest", "deprecated", "released_on", "position", "published")
    end

    def page_json(page)
      page.attributes.slice("id", "version_id", "parent_id", "slug", "title", "body", "locale", "topic_url", "published", "position")
    end

    def board_json(board)
      board.attributes.slice("id", "slug", "name", "locale", "chip", "description", "image_url", "documentation_url", "application_url", "published", "position")
    end

    def permission_json(permission)
      permission.attributes.slice("id", "user_id", "group_id", "resource_type", "resource_id", "permission")
    end
  end
end
