# frozen_string_literal: true

# A board and a sample chip are the same kind of catalogue entry — a picture,
# an introduction, and two links out — but they are not the same thing to a
# visitor, so the catalogue's first filter is which of the two to show. A
# string rather than a boolean because a third kind ("module", say) is a row
# value, not a migration.
#
# `details` is the long form shown in the card's dialog. The card itself has
# room for one short introduction (`description`); the dialog is where the
# specifications, the package and what is in the box are written out.
#
# Existing rows were all boards, so the default is the honest answer for them
# and the column can be added without a backfill.
class AddIngenicBoardKindAndDetails < ActiveRecord::Migration[7.2]
  def up
    add_column :ingenic_boards, :kind, :string, null: false, default: "board"
    add_column :ingenic_boards, :details, :text
    add_index :ingenic_boards, :kind
  end

  def down
    remove_index :ingenic_boards, :kind
    remove_column :ingenic_boards, :details
    remove_column :ingenic_boards, :kind
  end
end
