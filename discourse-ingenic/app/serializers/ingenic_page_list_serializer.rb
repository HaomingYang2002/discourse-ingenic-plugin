# frozen_string_literal: true

class IngenicPageListSerializer < ActiveModel::Serializer
  attributes :id, :slug, :title, :parent_id, :position, :depth

  def depth
    object.depth
  end
end
