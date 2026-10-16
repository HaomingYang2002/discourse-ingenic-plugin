# frozen_string_literal: true

module Ingenic
  # One page as a reader of a particular version sees it.
  #
  # The row it wraps belongs to whichever version last edited that slug, which
  # is not necessarily the version being read. Keeping the source row and the
  # reader-facing facts (depth, where it was inherited from) together means the
  # serializers never have to know that inheritance exists.
  class ResolvedPage
    # The serializers read their attributes through
    # `read_attribute_for_serialization`, which ActiveModel defines on the
    # classes it is mixed into rather than on Object. Without this the reader
    # answered every documentation page with a 500 — the page was resolved,
    # handed to the serializer, and the serializer could not read a single field
    # of it.
    include ActiveModel::Serialization

    attr_reader :page, :inherited_from, :parent_slug
    attr_accessor :depth

    def initialize(page, inherited_from: nil, parent_slug: nil)
      @page = page
      @inherited_from = inherited_from
      @parent_slug = parent_slug
      @depth = 0
    end

    def inherited?
      !inherited_from.nil?
    end

    delegate :id,
             :slug,
             :title,
             :body,
             :locale,
             :topic_url,
             :parent_id,
             :position,
             :updated_at,
             :version_id,
             to: :page
  end
end
