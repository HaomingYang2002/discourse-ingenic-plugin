# frozen_string_literal: true

class AddIngenicBoardPurchaseUrl < ActiveRecord::Migration[7.2]
  def change
    # The Chinese forum's board cards carry two actions — apply for one, or buy
    # one — and they point at different places, so one link cannot serve both.
    #
    # The application link stays required and the purchase link is optional,
    # because a board that is lent but not sold has nowhere to buy.
    add_column :ingenic_boards, :purchase_url, :string
  end
end
