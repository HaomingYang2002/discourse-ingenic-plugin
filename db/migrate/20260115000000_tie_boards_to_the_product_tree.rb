# frozen_string_literal: true

class TieBoardsToTheProductTree < ActiveRecord::Migration[7.2]
  def change
    # A board belongs to one chip in the product tree, which is what lets the
    # catalogue filter by series as well as by chip without a second list of
    # series names kept in step by hand. Nullable because the tree is maintained
    # separately: a board can be published before its chip has been added, and
    # losing the link should not take the board off the site.
    add_reference :ingenic_boards,
                  :product,
                  foreign_key: {
                    to_table: :ingenic_doc_products,
                  },
                  index: true

    # The short specification list a card shows under the description: memory,
    # interfaces, what comes in the box. Free text rather than columns because
    # every board line describes itself differently.
    add_column :ingenic_boards, :specs, :text

    # The catalogue's two filters both start from the chip, so the lookup the
    # listing does is by product.
    add_index :ingenic_boards, %i[product_id published position],
              name: "idx_ingenic_boards_catalogue"
  end
end
