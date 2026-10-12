# frozen_string_literal: true

class IngenicDocVersion < ActiveRecord::Base
  self.table_name = "ingenic_doc_versions"

  belongs_to :product, class_name: "IngenicDocProduct", foreign_key: :product_id

  has_many :pages,
           -> { order(position: :asc) },
           class_name: "IngenicDocPage",
           foreign_key: :version_id,
           dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: [:product_id, :locale] }
  validates :label, presence: true

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, released_on: :desc) }

  # The version's pages in the reading language, one entry per slug.
  #
  # A page can exist twice under one version — once in the reader's language and
  # once in the site default — so the rows are collapsed here rather than in the
  # controller. Without this a partially translated version would show every
  # translated page twice in the tree, once per locale.
  def published_pages
    reading = I18n.locale.to_s
    rows =
      pages.where(
        published: true,
        locale: [reading, SiteSetting.ingenic_default_locale],
      ).to_a

    rows.sort_by { |page| page.locale == reading ? 0 : 1 }.uniq(&:slug).sort_by(&:position)
  end

  # Returns the previous/next page in the flattened reading order so that the
  # theme can render footer navigation without recomputing the tree.
  def navigation_for(page)
    flat = flatten_pages(published_pages)
    index = flat.index { |item| item.id == page.id }

    {
      previous: index && index.positive? ? IngenicPageListSerializer.new(flat[index - 1], root: false) : nil,
      next: index && index < flat.length - 1 ? IngenicPageListSerializer.new(flat[index + 1], root: false) : nil,
    }
  end

  private

  # Depth-first walk so that nested pages read in the same order they appear in
  # the sidebar tree.
  def flatten_pages(page_list, parent_id = nil)
    page_list
      .select { |item| item.parent_id == parent_id }
      .sort_by(&:position)
      .flat_map { |item| [item] + flatten_pages(page_list, item.id) }
  end
end
