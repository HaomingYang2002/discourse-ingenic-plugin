# frozen_string_literal: true

# Follows MoveIngenicBoardDocumentationIntoDetails, which copied every address
# into the Markdown description. The column is empty of meaning now; this is a
# post deployment migration because Discourse refuses a column drop in a
# regular one, so live sites finish a deploy before the column goes.
class DropIngenicBoardDocumentationUrl < ActiveRecord::Migration[7.2]
  def up
    remove_column :ingenic_boards, :documentation_url
  end

  def down
    add_column :ingenic_boards, :documentation_url, :string
  end
end
