# frozen_string_literal: true

# Whether a board can be ordered is the team's decision, not a side effect of
# the links on the row. A board that is temporarily sold out keeps its
# application and purchase addresses so they come back when it is restocked;
# the switch says when the card should stop offering them.
#
# Existing rows start unsold, which is what the catalogue drew before this
# column existed. The old rule — no links means sold out — is not backfilled,
# because it cannot be told apart from a board that simply has no links.
class AddIngenicBoardSoldOut < ActiveRecord::Migration[7.2]
  def up
    add_column :ingenic_boards, :sold_out, :boolean, null: false, default: false
  end

  def down
    remove_column :ingenic_boards, :sold_out
  end
end
