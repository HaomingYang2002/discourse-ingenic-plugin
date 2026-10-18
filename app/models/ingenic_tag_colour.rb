# frozen_string_literal: true

# One tag's place in the theme's four colour families.
#
# Only tags an administrator has changed have a row. The built-in list below is
# what the theme shipped with, so a site that never opens the screen keeps the
# colours it already has, and a tag nobody has classified falls back to the sky
# family — a new tag is coloured the moment somebody writes it.
class IngenicTagColour < ActiveRecord::Base
  self.table_name = "ingenic_tag_colours"

  FAMILIES = %w[sky tech resolved announcement].freeze

  # The names the theme classifies out of the box. Keys are lower-cased because
  # Discourse writes a Latin tag's `data-tag-name` in lower case; Chinese names
  # are unchanged by `downcase`, so one lookup covers both.
  DEFAULTS = {
    "linux" => "tech",
    "android" => "tech",
    "camera" => "tech",
    "sdk" => "tech",
    "firmware" => "tech",
    "driver" => "tech",
    "open-source" => "tech",
    "ai" => "tech",
    "安卓" => "tech",
    "相机" => "tech",
    "驱动" => "tech",
    "固件" => "tech",
    "开源" => "tech",
    "solved" => "resolved",
    "已解决" => "resolved",
    "announcement" => "announcement",
    "公告" => "announcement",
  }.freeze

  validates :tag_name, presence: true, uniqueness: true
  validates :family, inclusion: { in: FAMILIES }

  # What one tag should be drawn as: the administrator's choice if there is one,
  # otherwise the built-in classification, otherwise sky.
  def self.family_for(name)
    key = name.to_s
    find_by(tag_name: key)&.family || DEFAULTS[key.downcase] || "sky"
  end

  # The overrides only. The theme already carries the built-in families, so
  # sending the whole vocabulary would be a larger payload saying the same
  # thing; sending just the rows keeps "what an administrator changed" visible
  # in the site data.
  def self.override_map
    pluck(:tag_name, :family).to_h
  end
end
