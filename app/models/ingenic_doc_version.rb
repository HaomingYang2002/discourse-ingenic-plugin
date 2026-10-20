# frozen_string_literal: true

class IngenicDocVersion < ActiveRecord::Base
  self.table_name = "ingenic_doc_versions"

  belongs_to :product, class_name: "IngenicDocProduct", foreign_key: :product_id

  has_many :pages,
           -> { order(position: :asc) },
           class_name: "IngenicDocPage",
           foreign_key: :version_id,
           dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: %i[product_id locale] }
  validates :label, presence: true

  # There is deliberately no `published` scope: a version has no such column.
  # What a reader may see is decided page by page, which is also what makes
  # inheritance work — a version that has not been written yet shows the pages
  # it inherited.
  scope :ordered, -> { order(position: :asc, released_on: :desc) }

  # The version's pages as a reader sees them, which includes everything
  # inherited from earlier versions. See Ingenic::DocumentationResolver.
  #
  # `locale` names the language whose pages to resolve. Readers leave it out to
  # use their own; the management screen passes the language picked at the top.
  def published_pages(locale: nil)
    resolver.effective_pages(self, locale: locale)
  end

  def find_readable_page(slug, locale: nil)
    resolver.find_page(self, slug, locale: locale)
  end

  # Every page the version resolves to, drafts included. Used by the management
  # page, which has to show what a reader cannot yet see.
  def page_tree(locale: nil)
    resolver.effective_pages(self, published_only: false, locale: locale)
  end

  # The row this version owns for a slug, if any. Its absence is what makes a
  # page inherited.
  def own_page(slug)
    pages.find_by(slug: slug)
  end

  def navigation_for(page, locale: nil)
    resolver.navigation_for(self, page, locale: locale)
  end

  # A reader lands on one version per language, so "latest" is exclusive
  # within the chip's versions filed under the same language. The workbench
  # has a checkbox for it; nothing in the public picker would show two.
  # `latest` is exclusive within a chip and language — the database enforces it
  # with a partial unique index. The exclusion has to be written *before* this
  # row is saved: clearing the sibling afterwards hits the index the moment
  # this row is inserted, and again when a latest version is moved to another
  # chip. Both failures made creating or moving a version look impossible.
  before_save :clear_sibling_latest, if: :latest?

  def make_latest!
    return unless latest?

    self.class.where(product_id: product_id, locale: locale).where.not(id: id).update_all(latest: false)
  end

  def resolver
    @resolver ||= Ingenic::DocumentationResolver.new(product)
  end

  private

  def clear_sibling_latest
    self.class
      .where(product_id: product_id, locale: locale)
      .where.not(id: id)
      .update_all(latest: false)
  end
end
