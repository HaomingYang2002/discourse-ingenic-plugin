# frozen_string_literal: true

class IngenicDownloadsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # Direct navigations to /ingenic/downloads must reach the app shell; the
  # filter requests the download centre makes stay AJAX and keep hitting JSON.
  skip_before_action :check_xhr, only: %i[index]

  def index
    return render_app_shell unless request.format.json?

    scope = IngenicDownload.published.where(locale: [locale, default_locale])

    scope = scope.where(product_slug: params[:product]) if params[:product].present?
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    scope = scope.where(version: params[:version]) if params[:version].present?
    scope = scope.where(platform: params[:platform]) if params[:platform].present?

    downloads = scope.ordered

    render_json_dump(
      downloads: ActiveModel::ArraySerializer.new(downloads, each_serializer: IngenicDownloadSerializer),
      filters: {
        products: IngenicDownload.published.distinct.order(:product_slug).pluck(:product_slug),
        kinds: IngenicDownload.published.distinct.order(:kind).pluck(:kind),
        versions: IngenicDownload.published.distinct.order(version: :desc).pluck(:version).compact,
        platforms: IngenicDownload.published.distinct.pluck(:platform).compact.sort,
      },
    )
  end

  private

  def locale
    @locale ||= I18n.locale.to_s
  end

  def default_locale
    SiteSetting.ingenic_default_locale
  end
end
