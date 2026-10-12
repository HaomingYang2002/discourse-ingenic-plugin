# frozen_string_literal: true

class IngenicDownloadSerializer < ActiveModel::Serializer
  attributes :id,
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
             :external

  def released_on
    object.released_on&.iso8601
  end

  def external
    object.external?
  end
end
