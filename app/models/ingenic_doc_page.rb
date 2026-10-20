# frozen_string_literal: true

class IngenicDocPage < ActiveRecord::Base
  self.table_name = "ingenic_doc_pages"

  # A folder is a heading in the table of contents, not a page: it expands and
  # collapses, and has no body. Everything else is an article. Storing the two
  # in one table keeps the parent chain — and therefore version inheritance —
  # unchanged.
  KINDS = %w[page folder].freeze

  belongs_to :version, class_name: "IngenicDocVersion", foreign_key: :version_id
  belongs_to :parent, class_name: "IngenicDocPage", foreign_key: :parent_id, optional: true

  has_many :children,
           -> { order(position: :asc) },
           class_name: "IngenicDocPage",
           foreign_key: :parent_id,
           dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: [:version_id, :locale] }
  validates :title, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }

  # `node_key` names the page itself rather than the row that holds this
  # version's copy of it: a page inherited, overridden or re-ordered by a later
  # version keeps the same key, and children keep pointing at it after the row
  # they were copied from is edited or removed. `parent_node_key` is the tree
  # edge the resolver walks. Both are written by the callbacks below; the key
  # never changes after creation.
  attr_readonly :node_key

  validates :node_key, presence: true, uniqueness: { scope: %i[version_id locale] }

  before_validation :ensure_node_key, on: :create
  before_validation :sync_parent_node_key

  # A body under a folder is invisible to every reader, so accepting one would
  # store text that can never be seen and leave the editor wondering where it
  # went.
  before_save { self.body = nil if folder? }

  # A parent chain that loops back on itself makes every depth walk recurse
  # forever — the admin screen, the reader and the API all build the tree from
  # it. Walking up from the prospective parent is the cheap way to see the loop
  # before it is written.
  validate :parent_does_not_close_a_loop

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc) }
  scope :folders, -> { where(kind: "folder") }

  def folder?
    kind == "folder"
  end

  def depth
    parent ? parent.depth + 1 : 0
  end

  # `dependent: :destroy` follows parent_id without looking at version_id: a
  # later version's copy of a page still points at the folder it was copied
  # from. Destroying this folder would therefore destroy that version's own
  # text, which is not part of this subtree. Move such rows up to this page's
  # parent before the cascade runs.
  def detach_foreign_descendants!
    ids = subtree_ids

    IngenicDocPage
      .where(parent_id: ids)
      .where.not(version_id: version_id)
      .update_all(parent_id: parent_id)
  end

  private

  # Ids of this page and everything below it, in any version.
  def subtree_ids
    ids = [id]
    frontier = [id]

    until frontier.empty?
      children = IngenicDocPage.where(parent_id: frontier).pluck(:id) - ids
      ids.concat(children)
      frontier = children
    end

    ids
  end

  # A slug is the page's address and its identity in the resolver, so a page
  # created under a slug the product already knows joins that page's node
  # instead of becoming a second page the same slug would shadow. Importing the
  # same manual into a newer version is the case this keeps in one piece.
  def ensure_node_key
    return if node_key.present?

    self.node_key = existing_node_key || SecureRandom.uuid
  end

  def existing_node_key
    return if version_id.blank? || slug.blank?

    product_id = version&.product_id
    return if product_id.nil?

    IngenicDocPage
      .joins(:version)
      .where(ingenic_doc_versions: { product_id: product_id })
      .where(slug: slug)
      .where.not(node_key: nil)
      .pick(:node_key)
  end

  # The tree edge is derived from the parent row, so the admin can keep filing
  # a page by `parent_id` while the resolver only ever reads node keys. A copy
  # (`dup`) carries its source's `parent_node_key` and never reaches the query
  # unless the parent actually changed.
  def sync_parent_node_key
    if parent_id.present?
      return if parent_node_key.present? && !parent_id_changed?

      self.parent_node_key = IngenicDocPage.where(id: parent_id).pick(:node_key)
    elsif parent_id_changed?
      self.parent_node_key = nil
    end
  end

  def parent_does_not_close_a_loop
    return if parent_id.blank?

    seen = Set.new
    node = parent

    while node
      if (id.present? && node.id == id) || seen.include?(node.id)
        errors.add(:parent_id, :invalid)
        return
      end

      seen << node.id
      node = node.parent
    end
  end
end
