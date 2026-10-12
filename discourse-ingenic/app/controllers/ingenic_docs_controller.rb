# frozen_string_literal: true

class IngenicDocsController < ::ApplicationController
  requires_plugin DiscourseIngenic::PLUGIN_NAME

  include DiscourseIngenic::AppShell

  # A visitor opening or refreshing /ingenic/docs/... is a plain browser
  # navigation, not an AJAX call. Without this the base controller rejects it
  # before we ever get to render the app shell.
  skip_before_action :check_xhr, only: %i[show]

  # Paths are /<product>/<version>/<page>; version and page are optional so
  # /ingenic/docs/<product> lands on the product's latest default version.
  MAX_PATH_SEGMENTS = 3

  def show
    return render_app_shell unless request.format.json?

    product = find_product
    return render_not_found(:product_not_found) unless product

    version = find_version(product)
    return render_not_found(:version_not_found) unless version

    page = find_page(version)
    return render_not_found(:page_not_found) if page_slug.present? && page.nil?

    render_json_dump(documentation_payload(product, version, page))
  end

  private

  def documentation_payload(product, version, page)
    payload = {
      product: IngenicProductSerializer.new(product, root: false),
      version: IngenicVersionSerializer.new(version, root: false),
      pages:
        ActiveModel::ArraySerializer.new(
          version.published_pages,
          each_serializer: IngenicPageListSerializer,
        ),
    }

    if page
      payload[:page] = IngenicPageSerializer.new(page, root: false)
      payload[:navigation] = version.navigation_for(page)
    end

    payload
  end

  def segments
    @segments ||= params[:path].to_s.split("/").reject(&:blank?).first(MAX_PATH_SEGMENTS)
  end

  def product_slug
    segments[0]
  end

  def version_slug
    segments[1]
  end

  def page_slug
    segments[2]
  end

  # Resolves the product named in the path, or — when the visitor has not chosen
  # one yet, which is every request to a bare /ingenic/docs — the first published
  # product. That is what lets the navigation's Documentation entry point at one
  # stable URL: the client asks the plugin where documentation starts and then
  # replaces the address with the canonical product path.
  def find_product
    scope = IngenicDocProduct.published.ordered
    scope = scope.where(slug: product_slug) if product_slug.present?

    in_reading_locale(scope)
  end

  # Versions hang off a product row and a product row belongs to a single
  # locale, so the product lookup has already settled the language. An explicit
  # `latest` is an alias for the version flagged latest, not a slug of its own.
  def find_version(product)
    return product.default_version if version_slug.blank? || version_slug == "latest"

    product.versions.published.find_by(slug: version_slug)
  end

  # The version already resolves the reading language per slug, so matching the
  # slug is all that is left; the locale-based fallback lives there rather than
  # here, which keeps one page per slug instead of one per translation.
  def find_page(version)
    return if page_slug.blank?

    version.published_pages.find { |page| page.slug == page_slug }
  end

  # The visitor's language wins over the site default. The two locales are
  # queried separately on purpose: `where(locale: [a, b]).first` returns whichever
  # row the database happens to hand back first, and which page a URL opens
  # should not depend on that.
  def in_reading_locale(scope)
    scope.where(locale: locale).first || scope.where(locale: default_locale).first
  end

  def locale
    @locale ||= I18n.locale.to_s
  end

  def default_locale
    SiteSetting.ingenic_default_locale
  end

  def render_not_found(key)
    render json: { errors: [I18n.t("ingenic.errors.#{key}")] }, status: 404
  end
end
