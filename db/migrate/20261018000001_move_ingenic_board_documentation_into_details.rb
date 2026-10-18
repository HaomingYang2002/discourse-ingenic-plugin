# frozen_string_literal: true

# The board dialog used to end in a separate "Documentation" link. The link
# belongs in the description with everything else, and the description is now
# Markdown, so the address moves into the body.
#
# A board that already had one keeps it visible: the address is appended to the
# description as a Markdown link. The empty column is dropped by a post
# deployment migration, which is how Discourse retires a column safely.
class MoveIngenicBoardDocumentationIntoDetails < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE ingenic_boards
      SET details = CASE
        WHEN details IS NULL OR btrim(details) = ''
          THEN '[Documentation](' || documentation_url || ')'
        ELSE details || E'\\n\\n[Documentation](' || documentation_url || ')'
      END
      WHERE documentation_url IS NOT NULL AND btrim(documentation_url) <> ''
    SQL
  end

  def down
    # The appended Markdown link is left in place: it is what the dialog now
    # shows, and removing it would lose the address this migration preserved.
  end
end
