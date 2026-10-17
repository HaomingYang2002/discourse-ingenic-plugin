# frozen_string_literal: true

require "rails_helper"

# The header buttons and the home cards ride in the site payload rather than in
# /ingenic/site.json: the header is drawn on every page and the cards sit above
# the fold, so both have to be in the first paint. What is checked here is that
# the payload carries the published rows, in order, in the shape the theme reads.
describe "the site payload" do
  it "carries the published header buttons in order" do
    IngenicHeaderLink.create!(
      label: "Ingenic",
      href: "https://www.ingenic.com",
      icon: "globe",
      position: 1,
    )
    IngenicHeaderLink.create!(
      label: "GitHub",
      href: "https://github.com",
      icon: "fab-github",
      show_label: false,
      position: 0,
    )
    IngenicHeaderLink.create!(
      label: "Hidden",
      href: "/secret",
      published: false,
    )

    get "/site.json"

    buttons = response.parsed_body.dig("ingenic_header_links")
    expect(buttons.map { |row| row["label"] }).to eq(%w[GitHub Ingenic])
    expect(buttons.first["show_label"]).to eq(false)
    expect(buttons.last["icon"]).to eq("globe")
  end

  it "carries the published home cards in order" do
    IngenicSectionCard.create!(label: "Docs", href: "/ingenic/docs", position: 1)
    IngenicSectionCard.create!(category: "technical-discussions", position: 0)

    get "/site.json"

    cards = response.parsed_body.dig("ingenic_section_cards")
    expect(cards.map { |row| row["category"] }).to eq(["technical-discussions", nil])
    expect(cards.last["href"]).to eq("/ingenic/docs")
  end
end
