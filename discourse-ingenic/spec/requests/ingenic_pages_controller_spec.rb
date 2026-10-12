# frozen_string_literal: true

require "rails_helper"

# The download centre and development board pages are served by the same action
# that answers their JSON: a browser navigation gets the Ember app shell, the
# component's fetch gets data. These specs pin that contract, because breaking it
# turns a shared link into a 404 without breaking any in-app navigation.
describe "Ingenic pages" do
  before { SiteSetting.ingenic_enabled = true }

  fab!(:download) do
    IngenicDownload.create!(
      product_slug: "t32pro",
      kind: "sdk",
      version: "2.1.0",
      locale: "en",
      name: "T32Pro SDK",
      file_url: "https://example.com/sdk.tar.gz",
    )
  end

  fab!(:board) do
    IngenicBoard.create!(
      slug: "halley5",
      name: "Halley5",
      locale: "en",
      chip: "T32",
      application_url: "https://example.com/apply",
    )
  end

  describe "GET /ingenic/downloads" do
    it "returns the resources and filter options as JSON" do
      get "/ingenic/downloads.json"

      json = response.parsed_body
      expect(json["downloads"].map { |item| item["name"] }).to eq(["T32Pro SDK"])
      expect(json["filters"]["kinds"]).to include("sdk")
    end

    it "serves the app shell on browser navigation" do
      get "/ingenic/downloads"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end

  describe "GET /ingenic/boards" do
    it "returns the published boards as JSON" do
      get "/ingenic/boards.json"

      expect(response.parsed_body["boards"].map { |item| item["slug"] }).to eq(["halley5"])
    end

    it "serves the app shell on browser navigation" do
      get "/ingenic/boards"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end
end
