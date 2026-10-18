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
      expect(response.parsed_body["series"].first["slug"]).to eq("t-series")
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

  describe "POST /admin/plugins/discourse-ingenic/documentation/versions" do
    fab!(:chip) do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )
    end

    # A version has no `published` column, and `published` is what every other
    # form in this controller sends. Permitting it made the request raise
    # `UnknownAttributeError` — a 500 where a row should have been written — so
    # the parameter list is the thing under test, not the version.
    it "creates a version even when the request carries a published flag" do
      expect {
        post "/admin/plugins/discourse-ingenic/documentation/versions.json",
             params: {
               product_id: chip.id,
               slug: "v1",
               label: "v1.0",
               locale: "en",
               published: true,
             }
      }.to change(IngenicDocVersion, :count).by(1)

      expect(response.status).to eq(200)
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/boards" do
    it "offers the chips a board can be filed against, with their series" do
      IngenicDocProduct.create!(
        slug: "t33",
        name: "T33",
        kind: IngenicDocProduct::CHIP,
        parent: product,
        locale: "en",
      )

      get "/admin/plugins/discourse-ingenic/boards.json"

      expect(response.status).to eq(200)
      chip = response.parsed_body["chips"].first
      expect(chip["slug"]).to eq("t33")
      expect(chip["series_name"]).to eq("T Series")
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/boards/:id" do
    it "updates a board" do
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: { name: "Updated Board" }

      expect(response.status).to eq(200)
      expect(board.reload.name).to eq("Updated Board")
    end

    it "turns the sold-out switch on without touching the links" do
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            sold_out: "true",
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["board"]["sold_out"]).to eq(true)
      expect(board.reload.sold_out).to eq(true)
      expect(board.reload.application_url).to eq("https://example.com")
    end

    it "files the board against a chip and reads the name back from the tree" do
      chip =
        IngenicDocProduct.create!(
          slug: "t33",
          name: "T33",
          kind: IngenicDocProduct::CHIP,
          parent: product,
          locale: "en",
        )

      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            product_id: chip.id,
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["board"]["chip_name"]).to eq("T33")
      expect(response.parsed_body["board"]["series_name"]).to eq("T Series")
      expect(board.reload.product).to eq(chip)
    end

    it "unfiles the board when the chip picker is cleared" do
      chip =
        IngenicDocProduct.create!(
          slug: "t33",
          name: "T33",
          kind: IngenicDocProduct::CHIP,
          parent: product,
          locale: "en",
        )
      board.update!(product: chip)

      # The picker posts an empty string for its blank option, which the foreign
      # key would refuse as a value.
      put "/admin/plugins/discourse-ingenic/boards/#{board.id}.json",
          params: {
            product_id: "",
          }

      expect(response.status).to eq(200)
      expect(board.reload.product_id).to be_nil
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/permissions" do
    it "is restricted to admins" do
      get "/admin/plugins/discourse-ingenic/permissions.json"

      expect(response.status).to eq(200)
    end
  end

  # The admin-editable lists. Each one is a table the screens read and write, so
  # an edit that renders "Saved." over an unchanged row is the failure these
  # cover.
  describe "GET /admin/plugins/discourse-ingenic/site" do
    it "returns every list the site screen draws" do
      IngenicPromotion.create!(title: "Spring campaign", locale: "en")
      IngenicSocialLink.create!(label: "GitHub", kind: IngenicSocialLink::LINK, href: "https://github.com")
      IngenicHeaderLink.create!(label: "Ingenic", href: "https://www.ingenic.com")
      IngenicSectionCard.create!(label: "Docs", href: "/ingenic/docs")
      column = IngenicFooterColumn.create!(title: "Developers")
      IngenicFooterLink.create!(column: column, label: "Downloads", href: "/ingenic/downloads")

      get "/admin/plugins/discourse-ingenic/site.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["promotions"].first["title"]).to eq("Spring campaign")
      expect(response.parsed_body["social_links"].first["label"]).to eq("GitHub")
      expect(response.parsed_body["header_links"].first["label"]).to eq("Ingenic")
      expect(response.parsed_body["section_cards"].first["label"]).to eq("Docs")
      column_json = response.parsed_body["footer_columns"].first
      expect(column_json["title"]).to eq("Developers")
      expect(column_json["links"].first["label"]).to eq("Downloads")
      expect(response.parsed_body["homepage_blocks"]).to eq([])
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/homepage-blocks" do
    it "saves the list in the order it was sent" do
      blocks = [
        { type: "categories", limit: 3, categories: "engineering, announcements" },
        { type: "latest", limit: 8, layout: "main" },
        { type: "hot", limit: 5, layout: "side" },
      ]

      put "/admin/plugins/discourse-ingenic/homepage-blocks.json", params: { blocks: blocks.to_json }

      expect(response.status).to eq(200)
      saved = DiscourseIngenic::ConfigParser.homepage_blocks
      expect(saved.map { |block| block["type"] }).to eq(%w[categories latest hot])
      expect(saved.map { |block| block["position"] }).to eq([0, 1, 2])
      expect(saved.first["categories"]).to eq(%w[engineering announcements])
      expect(saved.last["layout"]).to eq("side")
    end

    it "refuses a type the home page cannot draw, and writes nothing" do
      put "/admin/plugins/discourse-ingenic/homepage-blocks.json",
          params: { blocks: [{ type: "latest" }, { type: "weather" }].to_json }

      expect(response.status).to eq(422)
      expect(SiteSetting.ingenic_homepage_blocks).to eq("")
    end

    it "refuses a body that is not a list" do
      put "/admin/plugins/discourse-ingenic/homepage-blocks.json", params: { blocks: "not json" }

      expect(response.status).to eq(422)
      expect(SiteSetting.ingenic_homepage_blocks).to eq("")
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/promotions/:id" do
    it "persists the form and reports whether the slot is showing" do
      promotion = IngenicPromotion.create!(title: "Old headline", locale: "en")

      put "/admin/plugins/discourse-ingenic/promotions/#{promotion.id}.json",
          params: { title: "New headline", published: "true" }

      expect(response.status).to eq(200)
      expect(promotion.reload.title).to eq("New headline")
      expect(response.parsed_body["promotion"]["live"]).to eq(true)
    end

    it "clears a date the editor emptied rather than storing a blank string" do
      promotion =
        IngenicPromotion.create!(title: "Timed", locale: "en", starts_at: 1.day.from_now)

      put "/admin/plugins/discourse-ingenic/promotions/#{promotion.id}.json",
          params: { title: "Timed", starts_at: "" }

      expect(response.status).to eq(200)
      expect(promotion.reload.starts_at).to be_nil
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/promotions/:id" do
    it "removes the slot" do
      promotion = IngenicPromotion.create!(title: "Old campaign", locale: "en")

      expect {
        delete "/admin/plugins/discourse-ingenic/promotions/#{promotion.id}.json"
      }.to change(IngenicPromotion, :count).by(-1)

      expect(response.status).to eq(204)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/social-links/:id" do
    it "moves a platform from a QR code to a link" do
      # A QR entry needs its code; a link entry needs an address. Switching kinds
      # therefore has to arrive with the address in the same request.
      record =
        IngenicSocialLink.create!(
          label: "WeChat",
          kind: IngenicSocialLink::QR,
          qr_image_url: "/uploads/wechat.png",
        )

      put "/admin/plugins/discourse-ingenic/social-links/#{record.id}.json",
          params: { kind: IngenicSocialLink::LINK, href: "https://wechat.example.com" }

      expect(response.status).to eq(200)
      expect(record.reload.kind).to eq(IngenicSocialLink::LINK)
      expect(record.href).to eq("https://wechat.example.com")
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/header-links" do
    it "creates a header button and reports it back" do
      expect {
        post "/admin/plugins/discourse-ingenic/header-links.json",
             params: { label: "GitHub", href: "https://github.com", icon: "fab-github" }
      }.to change(IngenicHeaderLink, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["header_link"]["label"]).to eq("GitHub")
    end

    it "refuses an icon-only button with nothing to draw" do
      post "/admin/plugins/discourse-ingenic/header-links.json",
           params: { label: "GitHub", href: "https://github.com", show_label: "false" }

      expect(response.status).to eq(422)
      expect(IngenicHeaderLink.count).to eq(0)
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/header-links/:id" do
    it "removes the button" do
      record = IngenicHeaderLink.create!(label: "GitHub", href: "https://github.com")

      expect {
        delete "/admin/plugins/discourse-ingenic/header-links/#{record.id}.json"
      }.to change(IngenicHeaderLink, :count).by(-1)

      expect(response.status).to eq(204)
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/section-cards" do
    it "creates a card that points somewhere other than a category" do
      expect {
        post "/admin/plugins/discourse-ingenic/section-cards.json",
             params: { label: "Docs", href: "/ingenic/docs", icon: "book" }
      }.to change(IngenicSectionCard, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["section_card"]["href"]).to eq("/ingenic/docs")
    end

    it "refuses a card with nowhere to go" do
      post "/admin/plugins/discourse-ingenic/section-cards.json",
           params: { label: "Docs" }

      expect(response.status).to eq(422)
      expect(IngenicSectionCard.count).to eq(0)
    end
  end

  describe "POST /admin/plugins/discourse-ingenic/footer-links" do
    it "files a link under the column it was added to" do
      column = IngenicFooterColumn.create!(title: "Company")

      expect {
        post "/admin/plugins/discourse-ingenic/footer-links.json",
             params: { column_id: column.id, label: "About", href: "/about" }
      }.to change(IngenicFooterLink, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["footer_link"]["column_id"]).to eq(column.id)
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/footer-columns/:id" do
    it "takes the column's links with it" do
      column = IngenicFooterColumn.create!(title: "Company")
      IngenicFooterLink.create!(column: column, label: "About", href: "/about")

      expect {
        delete "/admin/plugins/discourse-ingenic/footer-columns/#{column.id}.json"
      }.to change(IngenicFooterLink, :count).by(-1)

      expect(response.status).to eq(204)
    end
  end

  describe "PUT /admin/plugins/discourse-ingenic/download-categories/:id" do
    it "renames a category" do
      category = IngenicDownloadCategory.create!(name: "SDK", locale: "en")

      put "/admin/plugins/discourse-ingenic/download-categories/#{category.id}.json",
          params: { name: "Software development kits" }

      expect(response.status).to eq(200)
      expect(category.reload.name).to eq("Software development kits")
    end
  end

  describe "DELETE /admin/plugins/discourse-ingenic/download-categories/:id" do
    it "leaves the resources filed under it in place, unfiled" do
      category = IngenicDownloadCategory.create!(name: "SDK", locale: "en")
      download =
        IngenicDownload.create!(
          name: "T33 SDK",
          product_slug: "t33",
          locale: "en",
          category: category,
          file_url: "https://example.com/sdk.tgz",
        )

      delete "/admin/plugins/discourse-ingenic/download-categories/#{category.id}.json"

      expect(response.status).to eq(204)
      expect(download.reload.category_id).to be_nil
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/download-logs" do
    it "lists what was taken, newest first" do
      download = IngenicDownload.create!(
        name: "T33 SDK",
        product_slug: "t33",
        locale: "en",
        file_url: "https://example.com/sdk.tgz",
      )
      IngenicDownloadLog.create!(user: admin, download: download, resource_name: download.name)

      get "/admin/plugins/discourse-ingenic/download-logs.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["logs"].first["resource_name"]).to eq("T33 SDK")
      expect(response.parsed_body["total"]).to eq(1)
    end

    it "is closed to a scoped content manager" do
      # The log names accounts, so it is an administrator's even though the rest
      # of the downloads page is not.
      sign_in(Fabricate(:moderator))

      get "/admin/plugins/discourse-ingenic/download-logs.json"

      expect(response.status).to eq(404)
    end
  end

  # An application outlives the account that made it: deleting a member blanks
  # the applicant on their rows rather than taking the rows with them, and the
  # queue then has a row with nobody to name. Two things have to hold — the
  # screen still draws, and access cannot be granted to an account that is not
  # there.
  describe "the access queue, with an applicant who has been deleted" do
    fab!(:applicant) { Fabricate(:user) }
    fab!(:gated_download) do
      IngenicDownload.create!(
        name: "T33 SDK",
        product_slug: "t33",
        locale: "en",
        access_level: IngenicDownload::APPROVAL_REQUIRED,
        file_url: "https://example.com/sdk.tgz",
      )
    end
    fab!(:application) do
      IngenicDownloadRequest.create!(user: applicant, download: gated_download, message: "Board bring-up")
    end

    before do
      # What the nullifying foreign key does to the row when the account is
      # destroyed.
      IngenicDownloadRequest.where(id: application.id).update_all(user_id: nil)
      application.reload
    end

    it "lists the application without a name instead of failing" do
      get "/admin/plugins/discourse-ingenic/download-requests.json"

      expect(response.status).to eq(200)
      row = response.parsed_body["requests"].first
      expect(row["id"]).to eq(application.id)
      expect(row["username"]).to be_nil
      expect(row["message"]).to eq("Board bring-up")
    end

    it "refuses to approve it, because there is no account to let in" do
      put "/admin/plugins/discourse-ingenic/download-requests/#{application.id}/approve.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.admin_errors.applicant_deleted"),
      )
      expect(IngenicDownloadGrant.count).to eq(0)
      expect(application.reload.status).to eq(IngenicDownloadRequest::PENDING)
    end

    it "still records a decision to decline it" do
      put "/admin/plugins/discourse-ingenic/download-requests/#{application.id}/reject.json",
          params: { note: "no account" }

      expect(response.status).to eq(200)
      expect(application.reload.status).to eq(IngenicDownloadRequest::REJECTED)
    end
  end

  describe "GET /admin/plugins/discourse-ingenic/downloads" do
    it "offers the record tab to an administrator" do
      get "/admin/plugins/discourse-ingenic/downloads.json"

      expect(response.parsed_body["can_read_log"]).to eq(true)
    end

    it "tells a scoped content manager not to offer the record tab" do
      # A scoped manager reaches the page — the route admits anyone who manages
      # something, and the log is not something they manage. The flag is what the
      # page reads before it draws the tab, so a manager is never offered a tab
      # whose request would be refused.
      manager = Fabricate(:user)
      download = IngenicDownload.create!(
        name: "T33 SDK",
        product_slug: "t33",
        locale: "en",
        file_url: "https://example.com/sdk.tgz",
      )
      IngenicPermission.create!(
        user: manager,
        resource_type: "IngenicDownload",
        resource_id: download.id,
      )
      sign_in(manager)

      get "/admin/plugins/discourse-ingenic/downloads.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["downloads"].map { |row| row["id"] }).to eq([download.id])
      expect(response.parsed_body["can_read_log"]).to eq(false)
    end
  end
end
