# frozen_string_literal: true

class SendIngenicBountiesWithTheirTopics < ActiveRecord::Migration[7.2]
  # A bounty is read through its topic and means nothing without one: the topic
  # page asks which offer stands on it, the board reaches offers by way of the
  # topics the viewer may see, and accepting an answer looks one up by the post's
  # topic. So the row goes when the topic goes — cascade, where a member's rows
  # are nullified, because a member can be gone and still leave a record behind
  # while an offer standing on nothing is not a record of anything.
  #
  # The schema alone would be the wrong fix. A standing bounty's points are not
  # promised, they are escrowed: the balance moved when the offer was opened, and
  # a row that disappears takes with it the only thing that would ever have moved
  # the points back. So the cascade is paired with the handler that closes the
  # standing offers first — `Ingenic::Bounties.refund_for_topic!`, called from the
  # `Topic` callback in `plugin.rb` — and the two together are what make deleting
  # a topic cost nobody anything.
  #
  # It lives in `db/post_migrate` with the migration it follows, for the same
  # reason: rewriting a referential action means dropping the constraint first,
  # and Discourse refuses a `DROP CONSTRAINT` in a regular migration.
  #
  # Before this, `ingenic_bounties.topic_id` was a plain reference, and the
  # database refused to delete a topic that carried a bounty. That came out
  # worse than a refusal: `PostDestroyer` destroys a topic's replies before it
  # destroys the topic, each in its own transaction, so the refusal landed on the
  # last step and left a topic stripped of its answers and still standing, behind
  # an error page that explained none of it. And a settled bounty stays on its
  # topic by design, so a topic that had ever carried one could not be deleted at
  # all.
  def up
    remove_foreign_key :ingenic_bounties, :topics
    add_foreign_key :ingenic_bounties, :topics, on_delete: :cascade
  end

  # Back to refusing. Nothing is lost by reversing this — the rows a cascade
  # would have removed are still there — but a topic carrying a bounty cannot be
  # permanently deleted again while the key is this way.
  def down
    remove_foreign_key :ingenic_bounties, :topics
    add_foreign_key :ingenic_bounties, :topics
  end
end
