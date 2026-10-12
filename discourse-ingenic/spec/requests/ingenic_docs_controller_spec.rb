# frozen_string_literal: true

require "rails_helper"

describe IngenicDocsController do
  fab!(:product) do
    IngenicDocProduct.create!(slug: "t32pro", name: "T32Pro", locale: "en", position: 0)
  end

  fab!(:latest_version) do
    IngenicDocVersion.create!(
      product: product,
      slug: "2.1.0",
      label: "2.1.0",
      locale: "en",
      latest: true,
      position: 0,
    )
  end

  fab!(:older_version) do
    IngenicDocVersion.create!(
      product: product,
      slug: "2.0.0",
      label: "2.0.0",
      locale: "en",
      position: 1,
    )
  end

  fab!(:overview) do
    IngenicDocPage.create!(
      version: latest_version,
      slug: "overview",
      title: "Overview",
      locale: "en",
      position: 0,
      body: "Chip introduction.",
    )
  end

  fab!(:quick_start) do
    IngenicDocPage.create!(
      version: latest_version,
      slug: "quick-start",
      title: "Quick Start",
      locale: "en",
      position: 1,
      body: "Build your first image.",
    )
  end

  before { SiteSetting.ingenic_enabled = true }

  describe "GET /ingenic/docs" do
    it "resolves the first published product so navigation can link to one URL" do
      IngenicDocProduct.create!(
        slug: "x2000",
        name: "X2000",
        locale: "en",
        position: 1,
      )

      get "/ingenic/docs.json"

      json = response.parsed_body
      expect(response.status).to eq(200)
      expect(json["product"]["slug"]).to eq("t32pro")
      expect(json["version"]["slug"]).to eq("2.1.0")
      expect(json["pages"].map { |page| page["slug"] }).to contain_exactly(
        "overview",
        "quick-start",
      )
    end

    it "skips unpublished products" do
      product.update!(published: false)

      get "/ingenic/docs.json"

      expect(response.status).to eq(404)
    end

    it "404s when there is no documentation at all" do
      IngenicDocProduct.destroy_all

      get "/ingenic/docs.json"

      expect(response.status).to eq(404)
    end
  end

  describe "GET /ingenic/docs/:product" do
    it "returns the latest version and its page tree" do
      get "/ingenic/docs/t32pro.json"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["version"]["slug"]).to eq("2.1.0")
      expect(json["pages"].map { |page| page["slug"] }).to contain_exactly(
        "overview",
        "quick-start",
      )
    end

    it "404s for an unknown product" do
      get "/ingenic/docs/does-not-exist.json"
      expect(response.status).to eq(404)
    end
  end

  describe "GET /ingenic/docs/:product/:version" do
    it "resolves an explicit version" do
      get "/ingenic/docs/t32pro/2.0.0.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["version"]["slug"]).to eq("2.0.0")
    end

    it "treats latest as an alias for the version flagged latest" do
      get "/ingenic/docs/t32pro/latest.json"
      expect(response.parsed_body["version"]["slug"]).to eq("2.1.0")
    end
  end

  describe "GET /ingenic/docs/:product/:version/:page" do
    it "returns the page with previous and next navigation" do
      get "/ingenic/docs/t32pro/2.1.0/overview.json"

      json = response.parsed_body
      expect(json["page"]["slug"]).to eq("overview")
      expect(json["navigation"]["next"]["slug"]).to eq("quick-start")
      expect(json["navigation"]["previous"]).to be_nil
    end

    it "404s for a page that does not exist in that version" do
      get "/ingenic/docs/t32pro/2.0.0/overview.json"
      expect(response.status).to eq(404)
    end
  end

  describe "unpublished content" do
    it "hides unpublished pages" do
      overview.update!(published: false)

      get "/ingenic/docs/t32pro/2.1.0/overview.json"

      expect(response.status).to eq(404)
    end
  end

  describe "browser navigation" do
    it "serves the app shell so opening or refreshing the URL does not 404" do
      get "/ingenic/docs/t32pro/2.1.0/overview"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    it "serves the app shell for a product URL with no version or page" do
      get "/ingenic/docs/t32pro"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    it "serves the app shell for the bare documentation URL" do
      get "/ingenic/docs"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end

  describe "translated content" do
    fab!(:translated_overview) do
      IngenicDocPage.create!(
        version: latest_version,
        slug: "overview",
        title: "概述",
        locale: "zh_CN",
        position: 0,
        body: "芯片介绍。",
      )
    end

    before { SiteSetting.default_locale = "zh_CN" }

    it "serves the reader's language and lists each page once" do
      get "/ingenic/docs/t32pro/2.1.0/overview.json"

      json = response.parsed_body
      expect(json["page"]["title"]).to eq("概述")
      expect(json["pages"].map { |page| page["slug"] }).to contain_exactly(
        "overview",
        "quick-start",
      )
    end

    it "falls back to the default locale for pages with no translation" do
      get "/ingenic/docs/t32pro/2.1.0/quick-start.json"

      expect(response.parsed_body["page"]["title"]).to eq("Quick Start")
    end

    it "opens a product that has no translated row at all" do
      get "/ingenic/docs/t32pro/2.1.0.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["product"]["slug"]).to eq("t32pro")
    end
  end

  describe "discuss in forum link" do
    it "uses the page's own topic when it has one" do
      overview.update!(topic_url: "/t/overview/12")

      get "/ingenic/docs/t32pro/2.1.0/overview.json"

      expect(response.parsed_body["page"]["discussion_url"]).to eq("/t/overview/12")
    end

    it "falls back to the configured category" do
      SiteSetting.ingenic_docs_discussion_category = "documentation"

      get "/ingenic/docs/t32pro/2.1.0/overview.json"

      expect(response.parsed_body["page"]["discussion_url"]).to eq("/c/documentation")
    end

    it "omits the link when neither is available" do
      get "/ingenic/docs/t32pro/2.1.0/overview.json"

      expect(response.parsed_body["page"]["discussion_url"]).to be_nil
    end
  end
end
