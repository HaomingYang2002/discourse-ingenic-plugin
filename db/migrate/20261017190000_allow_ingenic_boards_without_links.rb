# frozen_string_literal: true

# A board is now offered by whichever link is set, and a catalogue entry with
# neither is a legitimate row: it means the board is sold out, and the card
# says so instead of drawing a button that goes nowhere. The application link
# was the one required column, so it has to stop being required before an
# admin can record that state.
#
# `down` is lossy by nature — the blanks it fills were the sold-out rows — but
# an empty string is exactly what those rows held before this column was
# required, so nothing that was ever saved is invented.
class AllowIngenicBoardsWithoutLinks < ActiveRecord::Migration[7.2]
  def up
    change_column_null :ingenic_boards, :application_url, true
  end

  def down
    execute "UPDATE ingenic_boards SET application_url = '' WHERE application_url IS NULL"
    change_column_null :ingenic_boards, :application_url, false
  end
end
