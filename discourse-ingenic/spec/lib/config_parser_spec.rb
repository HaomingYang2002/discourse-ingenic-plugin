# frozen_string_literal: true

require "rails_helper"

describe DiscourseIngenic::ConfigParser do
  describe ".nav_items" do
    it "returns an empty list when the setting is blank" do
      SiteSetting.ingenic_nav_items = ""
      expect(described_class.nav_items).to eq([])
    end

    it "drops entries that are explicitly disabled" do
      SiteSetting.ingenic_nav_items = [
        { key: "home", label: "Home", icon: "house", href: "/", enabled: true },
        { key: "hidden", label: "Hidden", href: "/x", enabled: false },
      ].to_json

      items = described_class.nav_items

      expect(items.map { |item| item["key"] }).to eq(%w[home])
    end

    it "orders entries by position regardless of their order in the setting" do
      SiteSetting.ingenic_nav_items = [
        { key: "b", label: "B", href: "/b", position: 5 },
        { key: "a", label: "A", href: "/a", position: 1 },
      ].to_json

      expect(described_class.nav_items.map { |item| item["key"] }).to eq(%w[a b])
    end

    it "resolves a category slug to its forum path" do
      SiteSetting.ingenic_nav_items = [
        { key: "announcements", label: "Announcements", category: "official-announcements" },
      ].to_json

      expect(described_class.nav_items.first["href"]).to eq("/c/official-announcements")
    end

    it "degrades to an empty list when the JSON is malformed" do
      SiteSetting.ingenic_nav_items = "{not json"
      expect(described_class.nav_items).to eq([])
    end
  end

  describe ".homepage_blocks" do
    it "keeps only blocks with a known type and orders them by position" do
      SiteSetting.ingenic_homepage_blocks = [
        { type: "downloads", position: 2 },
        { type: "", position: 1 },
        { type: "boards", position: 0 },
      ].to_json

      blocks = described_class.homepage_blocks

      expect(blocks.map { |block| block["type"] }).to eq(%w[boards downloads])
    end

    it "applies a default limit when none is given" do
      SiteSetting.ingenic_homepage_blocks = [{ type: "discussions" }].to_json
      expect(described_class.homepage_blocks.first["limit"]).to eq(5)
    end

    it "degrades to an empty list when the JSON is malformed" do
      SiteSetting.ingenic_homepage_blocks = "[]not json"
      expect(described_class.homepage_blocks).to eq([])
    end
  end
end
