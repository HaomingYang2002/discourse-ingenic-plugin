# frozen_string_literal: true

require "rails_helper"

# The cards under "Popular sections". A card either follows a category or
# carries its own name and destination; the shapes that would draw an unlabelled
# or dead link are refused here.
describe IngenicSectionCard do
  def card(attrs = {})
    IngenicSectionCard.new({ label: "Technical Discussions", href: "/c/technical-discussions/6" }.merge(attrs))
  end

  it "accepts a card with a name and a destination" do
    expect(card).to be_valid
  end

  it "accepts a category card without a name, because the category has one" do
    expect(card(label: "", href: "", category: "technical-discussions")).to be_valid
  end

  it "requires a name when the card does not follow a category" do
    record = card(label: "")

    expect(record).not_to be_valid
    expect(record.errors[:label]).to be_present
  end

  it "requires somewhere to go" do
    record = card(href: "")

    expect(record).not_to be_valid
    expect(record.errors[:href]).to be_present
  end

  it "refuses a category written as a path rather than a slug" do
    record = card(category: "/c/technical-discussions")

    expect(record).not_to be_valid
    expect(record.errors[:category]).to be_present
  end

  it "orders by position and then by id" do
    second = IngenicSectionCard.create!(label: "Announcements", href: "/c/x/1", position: 1)
    first = IngenicSectionCard.create!(label: "Docs", href: "/ingenic/docs", position: 0)

    expect(described_class.ordered.to_a).to eq([first, second])
  end

  it "leaves unpublished cards out of the published set" do
    IngenicSectionCard.create!(label: "Docs", href: "/ingenic/docs", published: false)

    expect(described_class.published.count).to eq(0)
  end
end
