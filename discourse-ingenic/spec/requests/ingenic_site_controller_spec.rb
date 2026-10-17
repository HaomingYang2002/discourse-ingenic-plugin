# frozen_string_literal: true

require "rails_helper"

# The data behind the homepage slots and the footer.
#
# Every list here is one the Ingenic team edits, and each is drawn on a page
# nobody signs in for, so what matters is what a visitor sees rather than who may
# change it: unpublished rows stay out, a campaign outside its window stays out,
# and a retired column takes its links with it.
describe IngenicSiteController do
  fab!(:column) { IngenicFooterColumn.create!(title: "Developers", position: 0) }

  describe "GET /ingenic/site" do
    it "returns a promotion that is on now" do
      IngenicPromotion.create!(title: "Spring campaign", locale: "en", corner_label: "New")

      get "/ingenic/site.json"

      expect(response.status).to eq(200)
      promotion = response.parsed_body["promotions"].first
      expect(promotion["title"]).to eq("Spring campaign")
      expect(promotion["corner_label"]).to eq("New")
    end

    it "leaves out a promotion whose window has closed" do
      IngenicPromotion.create!(title: "Finished", locale: "en", ends_at: 1.day.ago)
      IngenicPromotion.create!(title: "Later", locale: "en", starts_at: 1.day.from_now)
      IngenicPromotion.create!(title: "On now", locale: "en")

      get "/ingenic/site.json"

      expect(response.parsed_body["promotions"].map { |row| row["title"] }).to eq(["On now"])
    end

    it "leaves out a promotion nobody published" do
      IngenicPromotion.create!(title: "Draft", locale: "en", published: false)

      get "/ingenic/site.json"

      expect(response.parsed_body["promotions"]).to be_empty
    end

    it "sends both shapes of partner platform" do
      IngenicSocialLink.create!(
        label: "GitHub",
        kind: IngenicSocialLink::LINK,
        href: "https://github.com/ingenic",
        position: 0,
      )
      IngenicSocialLink.create!(
        label: "WeChat",
        kind: IngenicSocialLink::QR,
        qr_image_url: "/uploads/wechat.png",
        qr_caption: "Scan to follow",
        position: 1,
      )

      get "/ingenic/site.json"

      github, wechat = response.parsed_body["social_links"]
      expect(github["kind"]).to eq("link")
      expect(github["href"]).to eq("https://github.com/ingenic")
      expect(wechat["kind"]).to eq("qr")
      expect(wechat["qr_image_url"]).to eq("/uploads/wechat.png")
      expect(wechat["qr_caption"]).to eq("Scan to follow")
    end

    it "says whether a partner platform is drawn as its icon alone" do
      IngenicSocialLink.create!(
        label: "GitHub",
        kind: IngenicSocialLink::LINK,
        href: "https://github.com/ingenic",
        icon_only: true,
      )

      get "/ingenic/site.json"

      expect(response.parsed_body["social_links"].first["icon_only"]).to eq(true)
    end


    it "carries a column's published links and not the hidden ones" do
      shown = IngenicFooterLink.create!(column: column, label: "Downloads", href: "/ingenic/downloads")
      IngenicFooterLink.create!(
        column: column,
        label: "Secret",
        href: "/secret",
        published: false,
      )

      get "/ingenic/site.json"

      links = response.parsed_body["footer_columns"].first["links"]
      expect(links.map { |link| link["id"] }).to eq([shown.id])
    end

    it "leaves out a column nobody published, links and all" do
      retired = IngenicFooterColumn.create!(title: "Retired", published: false)
      IngenicFooterLink.create!(column: retired, label: "Gone", href: "/gone")

      get "/ingenic/site.json"

      columns = response.parsed_body["footer_columns"]
      expect(columns.map { |row| row["title"] }).to eq(["Developers"])
      expect(columns.flat_map { |row| row["links"] }.map { |link| link["label"] }).not_to include(
        "Gone",
      )
    end

    it "is not a page" do
      # Nothing in the theme draws this address, so a browser arriving here has
      # asked for something that does not exist. Answering with an app shell
      # would draw an empty page instead of saying so.
      get "/ingenic/site"

      expect(response.status).to eq(404)
    end
  end
end
