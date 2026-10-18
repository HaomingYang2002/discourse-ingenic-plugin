# frozen_string_literal: true

require "rails_helper"

# The tag colour overrides. The table holds explicit choices only: a tag with
# no row keeps the built-in family, and a tag nobody has classified at all is
# sky. Both fallbacks are asserted here because the theme draws every tag from
# one of them.
describe IngenicTagColour do
  it "requires a tag name" do
    expect(described_class.new(tag_name: "", family: "sky")).not_to be_valid
  end

  it "refuses the same tag twice" do
    described_class.create!(tag_name: "linux", family: "tech")

    expect(described_class.new(tag_name: "linux", family: "sky")).not_to be_valid
  end

  it "refuses a family the theme cannot draw" do
    expect(described_class.new(tag_name: "linux", family: "orange")).not_to be_valid
  end

  it "prefers an explicit assignment" do
    described_class.create!(tag_name: "linux", family: "announcement")

    expect(described_class.family_for("linux")).to eq("announcement")
  end

  it "falls back to the family the name suggests" do
    expect(described_class.family_for("linux")).to eq("tech")
    expect(described_class.family_for("Linux")).to eq("tech")
    expect(described_class.family_for("公告")).to eq("announcement")
    expect(described_class.family_for("solved")).to eq("resolved")
  end

  it "falls back to sky for a name it does not know" do
    expect(described_class.family_for("a-tag-nobody-classified")).to eq("sky")
  end

  it "sends only explicit assignments to the theme" do
    described_class.create!(tag_name: "linux", family: "announcement")

    expect(described_class.override_map).to eq("linux" => "announcement")
  end
end
