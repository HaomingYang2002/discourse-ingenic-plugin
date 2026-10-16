# frozen_string_literal: true

module DiscourseIngenic
  # Admin-editable navigation and homepage layout are stored as JSON strings in
  # site settings so that the Ingenic team can reorder or hide entries without a
  # deploy. Parsing is defensive: a malformed value degrades to an empty list
  # instead of breaking page rendering.
  module ConfigParser
    module_function

    def parse_list(raw)
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      return [] unless parsed.is_a?(Array)

      parsed.select { |item| item.is_a?(Hash) }
    rescue JSON::ParserError => e
      Rails.logger.warn("[discourse-ingenic] #{e.message}")
      []
    end

    def nav_items
      parse_list(SiteSetting.ingenic_nav_items)
        .select { |item| item["enabled"] != false }
        .map
        .with_index do |item, index|
          {
            "key" => item["key"].presence || "item-#{index}",
            "label" => item["label"].to_s,
            "icon" => item["icon"].presence || "circle",
            "href" => resolve_href(item),
            "external" => item["external"] == true,
            "position" => item["position"].is_a?(Integer) ? item["position"] : index,
          }
        end
        .sort_by { |item| item["position"] }
    end

    def homepage_blocks
      parse_list(SiteSetting.ingenic_homepage_blocks)
        .select { |item| item["enabled"] != false }
        .map
        .with_index do |item, index|
          {
            "type" => item["type"].to_s,
            "position" => item["position"].is_a?(Integer) ? item["position"] : index,
            "limit" => item["limit"].is_a?(Integer) ? item["limit"] : 5,
            "category" => item["category"].to_s,
            "title" => item["title"].to_s,
            "html" => item["html"].to_s,
            # The categories block. An empty list means "the busiest ones",
            # which is what a front page wants before anyone has decided which
            # sections deserve the space.
            "categories" => slug_list(item["categories"]),
            "show_all" => item["show_all"] != false,
          }
        end
        .select { |item| item["type"].present? }
        .sort_by { |item| item["position"] }
    end

    # Written as a list, or as the comma-separated line an admin is more likely
    # to type into a one-line field.
    def slug_list(raw)
      list = raw.is_a?(Array) ? raw : raw.to_s.split(",")
      list.map { |slug| slug.to_s.strip }.reject(&:empty?)
    end

    # A nav entry may point at a Discourse category slug, an internal path or an
    # absolute external URL. Category entries resolve to /c/<slug> so that the
    # Ingenic team can reorder them without knowing final category ids.
    def resolve_href(item)
      return item["href"].to_s if item["href"].present?

      category = item["category"].to_s
      return "" if category.blank?

      "/c/#{category}"
    end
  end
end
