# frozen_string_literal: true

class IngenicBoardSerializer < ActiveModel::Serializer
  attributes :id,
             :slug,
             :name,
             :chip,
             :description,
             :image_url,
             :documentation_url,
             :application_url,
             :locale
end
