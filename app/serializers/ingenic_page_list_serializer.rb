# frozen_string_literal: true

class IngenicPageListSerializer < ActiveModel::Serializer
  attributes :id, :slug, :title, :kind, :parent_id, :parent_slug, :position, :depth, :inherited, :inherited_from_label

  # Set by Ingenic::DocumentationResolver for reading, and computed from the
  # parent chain when a raw page row is serialized (admin listings).
  def depth
    object.depth
  end

  def inherited
    object.respond_to?(:inherited?) && object.inherited?
  end

  def inherited_from_label
    inherited ? object.inherited_from.label : nil
  end
end
