# frozen_string_literal: true

require_relative "../../lib/ingenic/tag_policy"
require_relative "../../lib/ingenic/forum_categories"

# The forum's tag and section policy, applied once on deployment.
#
# These are rows and settings rather than columns, so they cannot be expressed
# as a schema change — but they are still part of what this plugin means by a
# working forum, and expecting a deployment to remember a rake task is how a
# production site ends up with three navigation links to 404s. Running here also
# means a test database gets the same policy as production.
#
# Both calls are idempotent; `rake ingenic:setup` runs them again for a forum
# whose administrator has changed something.
class ApplyIngenicForumPolicy < ActiveRecord::Migration[7.2]
  def up
    Ingenic::TagPolicy.apply!
    Ingenic::ForumCategories.ensure_layout!
  end

  def down
    # Policy is not schema. Deleting the tags would take them off topics and
    # take the tag group with them; there is no earlier state that is more
    # correct than the one this migration leaves behind.
  end
end
