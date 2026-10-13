# frozen_string_literal: true

# A development board in the catalogue.
#
# A board is a physical thing the Ingenic team sells or lends, so the plugin
# never takes an order for one: the two links on a card leave the forum, and
# everything here is presentation.
class IngenicBoard < ActiveRecord::Base
  self.table_name = "ingenic_boards"

  belongs_to :product,
             class_name: "IngenicDocProduct",
             foreign_key: :product_id,
             optional: true

  validates :slug, presence: true, uniqueness: { scope: :locale }
  validates :name, presence: true
  validates :application_url, presence: true
  validate :product_is_a_chip
  validate :purchase_link_is_usable

  # Setting the link is what says which chip a board is for, so the label
  # follows it rather than being a second thing to keep correct by hand. The
  # column stays because a board can be listed before its chip exists in the
  # tree, and because it keeps a board's chip readable without a join.
  before_validation :take_chip_name_from_product

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  # Both filters read the product tree rather than a chip name typed onto the
  # board, so a series is a board whose chip's parent is that series.
  def self.for_series(slug)
    chips = IngenicDocProduct.series.where(slug: slug).select(:id)
    joins(:product).where(ingenic_doc_products: { parent_id: chips })
  end

  def self.for_chip(slug)
    joins(:product).where(ingenic_doc_products: { slug: slug })
  end

  # What the card prints under the name. The tree wins when the board is linked
  # to it, because a rename there is meant to show up here.
  def chip_name
    product&.name.presence || chip
  end

  def series
    product&.parent
  end

  def series_name
    series&.name
  end

  # The card draws a Buy button only when there is somewhere to buy. Not every
  # board is sold — some are lent to developers on application — so an absent
  # link is a normal state rather than an unfinished record.
  def purchase?
    purchase_url.present?
  end

  private

  # A purchase link is only ever sent to a browser as a Location or an href, so
  # the same two shapes the download centre accepts are accepted here. A typo
  # caught on save is one the admin can still fix, rather than a dead button.
  def purchase_link_is_usable
    return if purchase_url.blank?

    return if purchase_url.start_with?("/") || purchase_url.match?(%r{\Ahttps?://}i)

    errors.add(:purchase_url, "must be a site path or an http(s) address")
  end

  def take_chip_name_from_product
    self.chip = product.name if product.present?
  end

  # Only a chip: a board is for a specific part, and a board filed against a
  # series would appear under every chip in it.
  def product_is_a_chip
    return if product.nil?
    return errors.add(:product, "must be a chip") unless product.chip?
  end
end
