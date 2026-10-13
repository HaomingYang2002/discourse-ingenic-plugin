# frozen_string_literal: true

require "rails_helper"

describe Admin::IngenicController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:product) { IngenicDocProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:board) do
    IngenicBoard.create!(slug: "board-one", name: "Board One", locale: "en", application_url: "https://example.com")
  end

  before { sign_in(admin) }

  describe "GET /admin/plugins/discourse-ingenic/documentation" do
    it "returns products" do
      get "/admin/plugins/discourse-ingenic/documentation.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["products"].first["slug"]).to eq("t-series")
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/documentation/products" do
    it "creates a product" do
      expect {
        post "/admin/plugins/discourse-ingenic/documentation/products.json",
             params: { slug: "c-series", name: "C Series", locale: "en" }
      }.to change(IngenicDocProduct, :count).by(1)

      expect(response.status).to eq(200)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/boards/:id" do
    it "updates a board" do
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: { name: "Updated Board" }

      expect(response.status).to eq(200)
      expect(board.reload.name).to eq("Updated Board")
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/permissions" do
    it "is restricted to admins" do
      get "/admin/plugins/discourse-ingenic/permissions.json"

      expect(response.status).to eq(200)
    end
  end
end
