# frozen_string_literal: true

# What earns points, and how many.
#
# The amounts, the wording and the order are the team's; the list of actions is
# the plugin's. Each action needs somewhere in Discourse that reports it, so a
# row naming something nothing listens for would be a promise the plugin cannot
# keep — which is why the events are a fixed vocabulary and the numbers are not.
class IngenicPointRule < ActiveRecord::Base
  self.table_name = "ingenic_point_rules"

  TOPIC_CREATED = "topic_created"
  POST_CREATED = "post_created"
  LIKE_RECEIVED = "like_received"
  SOLUTION_ACCEPTED = "solution_accepted"

  EVENTS = [TOPIC_CREATED, POST_CREATED, LIKE_RECEIVED, SOLUTION_ACCEPTED].freeze

  validates :event, presence: true, inclusion: { in: EVENTS }, uniqueness: true
  validates :label, presence: true
  # Not signed: a rule that subtracts would be a punishment, and there is a
  # better place for one — a manual adjustment, where an administrator writes
  # down who and why.
  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :published, -> { where(published: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  # The earning rule for an action, or nil when it is retired or was never
  # seeded. Nil is the ordinary answer for a forum that has turned one off.
  def self.for(event)
    published.find_by(event: event.to_s)
  end

  # What one occurrence is worth right now, with nothing to award reading as
  # nothing.
  #
  # `self.for` rather than a bare `for`: without a receiver Ruby reads the name
  # as the start of a for loop and refuses the line outright.
  def self.amount_for(event)
    self.for(event)&.points.to_i
  end
end
