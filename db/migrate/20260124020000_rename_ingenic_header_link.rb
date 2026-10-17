# frozen_string_literal: true

# The header's official-site button was seeded as "Ingenic". That is the
# company's short name, not its website's English name, and the button sits
# beside the logo where the full name is what tells a visitor what opens in the
# new tab.
#
# Only the seeded row is touched: a label somebody has already edited is left
# alone, which is why the old value is part of the condition.
class RenameIngenicHeaderLink < ActiveRecord::Migration[7.0]
  OLD_LABEL = "Ingenic"
  NEW_LABEL = "Ingenic Semiconductor"

  def up
    execute <<~SQL
      UPDATE ingenic_header_links
      SET label = #{connection.quote(NEW_LABEL)}, updated_at = CURRENT_TIMESTAMP
      WHERE label = #{connection.quote(OLD_LABEL)}
        AND href LIKE '%ingenic.com%'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE ingenic_header_links
      SET label = #{connection.quote(OLD_LABEL)}, updated_at = CURRENT_TIMESTAMP
      WHERE label = #{connection.quote(NEW_LABEL)}
        AND href LIKE '%ingenic.com%'
    SQL
  end
end
