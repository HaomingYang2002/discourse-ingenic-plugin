# frozen_string_literal: true

class IngenicProductSerializer < ActiveModel::Serializer
  attributes :id, :slug, :name, :description, :locale

  has_many :versions, serializer: IngenicVersionSerializer
end
