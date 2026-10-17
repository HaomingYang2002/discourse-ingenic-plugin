# frozen_string_literal: true

require "rails_helper"

describe IngenicBoardsController do
  before { SiteSetting.ingenic_enabled = true }

  fab!(:series) do
    IngenicDocProduct.create!(
      slug: "t-series",
      name: "T Series",
      kind: IngenicDocProduct::SERIES,
      locale: "en",
      position: 0,
    )
  end

  fab!(:chip) do
    IngenicDocProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicDocProduct::CHIP,
      parent: series,
      locale: "en",
      position: 0,
    )
  end

  fab!(:other_series) do
    IngenicDocProduct.create!(
      slug: "c-series",
      name: "C Series",
      kind: IngenicDocProduct::SERIES,
      locale: "en",
      position: 1,
    )
  end

  fab!(:other_chip) do
    IngenicDocProduct.create!(
      slug: "c100",
      name: "C100",
      kind: IngenicDocProduct::CHIP,
      parent: other_series,
      locale: "en",
      position: 0,
    )
  end

  def board(attrs = {})
    IngenicBoard.create!(
      {
        slug: "halley5",
        name: "Halley5",
        locale: "en",
        application_url: "https://example.com/apply",
      }.merge(attrs),
    )
  end

  describe "GET /ingenic/boards" do
    it "lists the published boards with the chip they are for" do
      board(product: chip, specs: "DDR3 1GB")

      get "/ingenic/boards.json"

      entry = response.parsed_body["boards"].first
      expect(entry["slug"]).to eq("halley5")
      expect(entry["kind"]).to eq("board")
      expect(entry["chip_name"]).to eq("T33")
      expect(entry["series_slug"]).to eq("t-series")
      expect(entry["product_slug"]).to eq("t33")
      expect(entry["specs"]).to eq("DDR3 1GB")
    end

    it "offers both kinds and every chip, each naming the series it belongs to" do
      get "/ingenic/boards.json"

      filters = response.parsed_body["filters"]
      expect(filters["kinds"]).to contain_exactly("board", "sample")

      chip_filter = filters["chips"].find { |item| item["slug"] == "c100" }
      expect(chip_filter["series_slug"]).to eq("c-series")
      expect(chip_filter["series_name"]).to eq("C Series")
    end

    it "narrows to one kind" do
      board(product: chip)
      board(slug: "t33-sample", name: "T33 Sample", kind: "sample", product: chip)

      get "/ingenic/boards.json?kind=sample"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["t33-sample"])
    end

    it "ignores an unknown kind rather than showing an empty catalogue" do
      board(product: chip)

      get "/ingenic/boards.json?kind=module"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["halley5"])
    end

    it "narrows to one chip" do
      board(product: chip)
      board(slug: "halley3", name: "Halley3", product: other_chip)

      get "/ingenic/boards.json?chip=c100"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["halley3"])
    end

    it "still offers both kinds while one is filtered, so the choice can be undone" do
      board(product: chip, kind: "sample")

      get "/ingenic/boards.json?kind=sample"

      expect(response.parsed_body["filters"]["kinds"]).to contain_exactly("board", "sample")
    end

    it "leaves a withdrawn board out of the catalogue" do
      board(product: chip, published: false)

      get "/ingenic/boards.json"

      expect(response.parsed_body["boards"]).to be_empty
    end

    it "shows one card for a board that has both locales, preferring the reader's" do
      SiteSetting.ingenic_default_locale = "zh_CN"
      board(product: chip, locale: "en", name: "Halley5")
      board(product: chip, locale: "zh_CN", name: "Halley5 中文")

      get "/ingenic/boards.json"

      expect(response.parsed_body["boards"].length).to eq(1)
      expect(response.parsed_body["boards"].first["name"]).to eq("Halley5")
    end
  end
end
