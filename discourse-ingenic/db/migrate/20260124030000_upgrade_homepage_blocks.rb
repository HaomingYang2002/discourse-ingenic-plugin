# frozen_string_literal: true

# A forum that has ever saved the homepage layout in admin keeps that saved
# list forever: the setting overrides the theme's default layout, so the new
# weekly-contributor card would never appear on an existing site until somebody
# opened the page and added it by hand.
#
# This is the one-time catch-up. It only touches a list that was already
# customised (an empty value means "draw the default layout", which is already
# current), and it only rearranges the four rail blocks the front page is meant
# to end with: latest activity, popular posts, bounties, weekly contributors.
# Other blocks keep the slots they had.
class UpgradeHomepageBlocks < ActiveRecord::Migration[7.0]
  RAIL_ORDER = %w[promotions hot bounties leaderboard].freeze

  def up
    list = blocks
    return if list.empty?

    changed = false

    unless list.any? { |item| item["type"] == "leaderboard" }
      list << { "type" => "leaderboard", "limit" => 5 }
      changed = true
    end

    # The four rail cards are pulled out, put in the intended order and put back
    # into the same slots, so a block somebody placed among them does not move.
    slots = []
    rail = []
    list.each_with_index do |item, index|
      if RAIL_ORDER.include?(item["type"])
        slots << index
        rail << item
      end
    end

    if rail.size > 1
      ordered = rail.sort_by { |item| RAIL_ORDER.index(item["type"]) || RAIL_ORDER.size }
      unless ordered == rail
        slots.each_with_index { |slot, index| list[slot] = ordered[index] }
        changed = true
      end
    end

    SiteSetting.ingenic_homepage_blocks = JSON.generate(list) if changed
  end

  def down
    # The previous list cannot be reconstructed: the card is a new feature and
    # the order was the point of the change. Rolling back leaves a valid list,
    # which is what the admin screen expects.
  end

  private

  def blocks
    raw = SiteSetting.ingenic_homepage_blocks.to_s
    return [] if raw.blank?

    parsed = JSON.parse(raw)
    return [] unless parsed.is_a?(Array)

    parsed.select { |item| item.is_a?(Hash) }
  rescue JSON::ParserError
    []
  end
end
