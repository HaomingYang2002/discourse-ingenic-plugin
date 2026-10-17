# frozen_string_literal: true

class AddIngenicDownloadFamily < ActiveRecord::Migration[7.2]
  # A resource belongs either to the chip line or to the algorithm library.
  #
  # The two are parallel in the catalogue, not nested: an algorithm runs across
  # chips and is not filed under one, while an SDK is something a particular
  # chip has. Expressing that as a family on the resource rather than as another
  # product-tree node keeps the tree about chips and stops an algorithm from
  # appearing in the documentation's chip selector.
  #
  # Every existing row was a chip resource, so the default is the honest answer
  # for them and the column can be added without a backfill.
  #
  # `product_slug` becomes nullable in the same step: it was NOT NULL while
  # every resource belonged to a chip, and an algorithm has no part number to
  # put there. The model requires it for chip resources and clears it for
  # algorithms, so the constraint moves from the column to the family.
  def up
    add_column :ingenic_downloads, :family, :string, null: false, default: "chip"
    add_index :ingenic_downloads, :family
    change_column_null :ingenic_downloads, :product_slug, true
  end

  def down
    change_column_null :ingenic_downloads, :product_slug, false
    remove_index :ingenic_downloads, :family
    remove_column :ingenic_downloads, :family
  end
end
