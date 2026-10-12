# frozen_string_literal: true

class IngenicVersionSerializer < ActiveModel::Serializer
  attributes :id, :slug, :label, :locale, :latest, :deprecated, :released_on

  def released_on
    object.released_on&.iso8601
  end
end
