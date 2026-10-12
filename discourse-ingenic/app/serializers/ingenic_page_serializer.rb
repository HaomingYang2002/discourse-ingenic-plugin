# frozen_string_literal: true

class IngenicPageSerializer < ActiveModel::Serializer
  attributes :id,
             :slug,
             :title,
             :body,
             :locale,
             :topic_url,
             :discussion_url,
             :parent_id,
             :updated_at

  def updated_at
    object.updated_at&.iso8601
  end

  # Where the page's "Discuss in forum" link points. A page can name its own
  # topic, and otherwise falls back to the configured category, so every
  # documentation page still has a way back into the discussion.
  def discussion_url
    return object.topic_url if object.topic_url.present?

    category_slug = SiteSetting.ingenic_docs_discussion_category
    "/c/#{category_slug}" if category_slug.present?
  end

  # Documentation bodies are authored as Markdown by the Ingenic team, so they
  # go through the same sanitizer used for posts before reaching the client.
  def body
    PrettyText.cook(object.body.to_s, features: { Onebox: false })
  end
end
