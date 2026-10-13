# frozen_string_literal: true

class IngenicBoardSerializer < ActiveModel::Serializer
  attributes :id,
             :slug,
             :name,
             :chip,
             :chip_name,
             :product_slug,
             :series_slug,
             :series_name,
             :description,
             :specs,
             :image_url,
             :documentation_url,
             :application_url,
             :locale

  # The slugs are what the filter controls compare against, and they come back
  # as null rather than empty for a board that has not been filed against the
  # tree yet, so the page can tell "no chip" from "chip named nothing".
  def product_slug
    object.product&.slug
  end

  def series_slug
    object.series&.slug
  end

  def series_name
    object.series&.name
  end
end
