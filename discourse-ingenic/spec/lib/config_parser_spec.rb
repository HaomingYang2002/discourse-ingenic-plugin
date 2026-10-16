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

    it "carries the group each entry belongs to" do
      SiteSetting.ingenic_nav_items = [
        { key: "docs", label: "Documentation", href: "/ingenic/docs", section: "resources" },
        { key: "points", label: "Points", href: "/ingenic/points", section: "member" },
        { key: "home", label: "Home", href: "/", section: "forum" },
      ].to_json

      expect(described_class.nav_items.map { |item| item["section"] }).to eq(
        %w[resources member forum],
      )
    end

    it "reads an entry in no group as the forum list" do
      SiteSetting.ingenic_nav_items = [
        { key: "home", label: "Home", href: "/" },
      ].to_json

      expect(described_class.nav_items.first["section"]).to eq("forum")
    end

    it "reads a group that does not exist as the forum list rather than losing the entry" do
      SiteSetting.ingenic_nav_items = [
        { key: "docs", label: "Documentation", href: "/ingenic/docs", section: "resource" },
        { key: "home", label: "Home", href: "/", section: "Developer Center" },
      ].to_json

      items = described_class.nav_items

      expect(items.size).to eq(2)
      expect(items.map { |item| item["section"] }).to eq(%w[forum forum])
    end

    it "reads a group written with different case or spacing as the group meant" do
      SiteSetting.ingenic_nav_items = [
        { key: "docs", label: "Documentation", href: "/ingenic/docs", section: " Resources " },
        { key: "points", label: "Points", href: "/ingenic/points", section: "MEMBER" },
      ].to_json

      expect(described_class.nav_items.map { |item| item["section"] }).to eq(
        %w[resources member],
      )
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

    describe "the categories block" do
      it "reads the named sections in the order they were written" do
        SiteSetting.ingenic_homepage_blocks = [
          { type: "categories", categories: %w[official-announcements technical-discussions] },
        ].to_json

        block = described_class.homepage_blocks.first

        expect(block["categories"]).to eq(%w[official-announcements technical-discussions])
      end

      it "reads a comma-separated line as the same list" do
        SiteSetting.ingenic_homepage_blocks = [
          { type: "categories", categories: "official-announcements, technical-discussions" },
        ].to_json

        expect(described_class.homepage_blocks.first["categories"]).to eq(
          %w[official-announcements technical-discussions],
        )
      end

      it "drops empty entries and surrounding spaces" do
        SiteSetting.ingenic_homepage_blocks = [
          { type: "categories", categories: ["  official-announcements  ", "", nil] },
        ].to_json

        expect(described_class.homepage_blocks.first["categories"]).to eq(%w[official-announcements])
      end

      it "leaves the list empty when no sections are named" do
        SiteSetting.ingenic_homepage_blocks = [{ type: "categories" }].to_json

        expect(described_class.homepage_blocks.first["categories"]).to eq([])
      end

      it "shows the all-sections entry unless it is turned off" do
        SiteSetting.ingenic_homepage_blocks = [{ type: "categories" }].to_json
        expect(described_class.homepage_blocks.first["show_all"]).to eq(true)

        SiteSetting.ingenic_homepage_blocks = [{ type: "categories", show_all: false }].to_json
        expect(described_class.homepage_blocks.first["show_all"]).to eq(false)
      end
    end
  end
end
