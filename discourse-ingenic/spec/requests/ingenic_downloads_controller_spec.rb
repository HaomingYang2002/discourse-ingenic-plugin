# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

describe IngenicDownloadsController do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en") }

  before { SiteSetting.ingenic_download_admin_email = "team@example.com" }

  def resource(level, name: "SDK", **attrs)
    IngenicDownload.create!(
      {
        name: name,
        product_slug: "t33",
        category: category,
        locale: "en",
        access_level: level,
        file_url: "https://example.com/sdk.tgz",
      }.merge(attrs),
    )
  end

  def with_profile(owner = nil)
    IngenicDeveloperProfile.create!(
      user: owner || user,
      data: {
        "full_name" => "Ada",
        "company" => "Acme",
        "country" => "UK",
        "contact_email" => "ada@example.com",
        "use_case" => "Set-top boxes",
      },
    )
  end

  describe "GET /ingenic/downloads" do
    it "says which state each resource is in for the reader" do
      resource(IngenicDownload::LOGIN_ONLY, name: "Open")
      resource(IngenicDownload::APPROVAL_REQUIRED, name: "Gated")

      get "/ingenic/downloads.json"

      states = response.parsed_body["downloads"].to_h { |d| [d["name"], d["access_state"]] }
      expect(states).to eq("Open" => "anonymous", "Gated" => "anonymous")
      expect(response.parsed_body["signed_in"]).to eq(false)
    end

    it "never puts the resource's own address in the listing" do
      resource(IngenicDownload::LOGIN_ONLY)

      get "/ingenic/downloads.json"

      expect(response.body).not_to include("example.com")
      expect(response.parsed_body["downloads"].first["file_path"]).to end_with("/file")
    end

    it "reports a granted resource for the account that holds the grant" do
      resource(IngenicDownload::LOGIN_ONLY)
      sign_in(user)

      get "/ingenic/downloads.json"

      expect(response.parsed_body["downloads"].first["access_state"]).to eq("granted")
      expect(response.parsed_body["signed_in"]).to eq(true)
    end

    it "serves the app shell for a direct navigation" do
      get "/ingenic/downloads"

      expect(response.status).to eq(200)
    end

    # The two levels of the product filter. The options come from the product
    # tree rather than from the slugs on the resources, so a chip is offered
    # under its name and not as the string that happens to be in the row.
    describe "the product filters" do
      fab!(:series) do
        IngenicDocProduct.create!(slug: "t-series", name: "T Series", locale: "en")
      end

      fab!(:chip) do
        IngenicDocProduct.create!(
          slug: "t33",
          name: "T33",
          kind: IngenicDocProduct::CHIP,
          parent: series,
          locale: "en",
        )
      end

      it "offers the series, and each chip under the series it belongs to" do
        chip

        get "/ingenic/downloads.json"

        filters = response.parsed_body["filters"]
        expect(filters["series"]).to eq([{ "slug" => "t-series", "name" => "T Series" }])
        expect(filters["chips"]).to eq(
          [{ "slug" => "t33", "name" => "T33", "series_slug" => "t-series" }],
        )
      end

      it "matches a resource filed against a chip when its series is chosen" do
        chip
        resource(IngenicDownload::LOGIN_ONLY, name: "Chip SDK", product_slug: "t33")
        resource(IngenicDownload::LOGIN_ONLY, name: "Other SDK", product_slug: "c-series")

        get "/ingenic/downloads.json?series=t-series"

        expect(response.parsed_body["downloads"].map { |row| row["name"] }).to eq(["Chip SDK"])
      end

      # A series-wide SDK has no single chip to be filed under, and an editor who
      # filed it that way cannot be expected to know the page would not honour it.
      it "matches a resource filed against the series itself" do
        chip
        resource(IngenicDownload::LOGIN_ONLY, name: "Series-wide SDK", product_slug: "t-series")

        get "/ingenic/downloads.json?series=t-series"

        expect(response.parsed_body["downloads"].map { |row| row["name"] }).to eq(
          ["Series-wide SDK"],
        )
      end

      it "still narrows by a named chip" do
        chip
        resource(IngenicDownload::LOGIN_ONLY, name: "Chip SDK", product_slug: "t33")
        resource(IngenicDownload::LOGIN_ONLY, name: "Other SDK", product_slug: "c-series")

        get "/ingenic/downloads.json?product=t33"

        expect(response.parsed_body["downloads"].map { |row| row["name"] }).to eq(["Chip SDK"])
      end
    end
  end

  describe "POST /ingenic/downloads/profile" do
    before { sign_in(user) }

    it "stores the answers" do
      expect {
        post "/ingenic/downloads/profile.json",
             params: {
               profile: {
                 full_name: "Ada",
                 company: "Acme",
                 country: "UK",
                 contact_email: "ada@example.com",
                 use_case: "Set-top boxes",
               },
             }
      }.to change(IngenicDeveloperProfile, :count).by(1)

      expect(response.status).to eq(200)
      expect(response.parsed_body["form"]["completed"]).to eq(true)
      expect(IngenicDeveloperProfile.for(user).value_for("company")).to eq("Acme")
    end

    it "refuses a form with a required answer missing" do
      post "/ingenic/downloads/profile.json", params: { profile: { full_name: "Ada" } }

      expect(response.status).to eq(422)
      expect(IngenicDeveloperProfile.for(user)).to be_nil
    end

    it "keeps only the answers the form asks for" do
      post "/ingenic/downloads/profile.json",
           params: {
             profile: {
               full_name: "Ada",
               company: "Acme",
               country: "UK",
               contact_email: "ada@example.com",
               use_case: "Set-top boxes",
               admin: "true",
               injected: "<script>",
             },
           }

      expect(IngenicDeveloperProfile.for(user).data.keys).not_to include("admin", "injected")
    end
  end

  describe "POST /ingenic/downloads/:id/request" do
    before { sign_in(user) }

    it "records the application and emails the team" do
      Jobs.run_immediately!
      with_profile
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect {
        post "/ingenic/downloads/#{download.id}/request.json",
             params: {
               message: "Building a camera",
             }
      }.to change(IngenicDownloadRequest, :count).by(1).and change {
              ActionMailer::Base.deliveries.size
            }.by(1)

      expect(response.status).to eq(200)
      expect(ActionMailer::Base.deliveries.last.to).to contain_exactly("team@example.com")
      expect(IngenicDownloadRequest.last.message).to eq("Building a camera")
    end

    it "asks for the developer information instead of filing an application" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect { post "/ingenic/downloads/#{download.id}/request.json" }.not_to change(
        IngenicDownloadRequest,
        :count,
      )

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.profile_required"),
      )
    end

    it "answers a second application with the first one still open" do
      Jobs.run_immediately!
      with_profile
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      post "/ingenic/downloads/#{download.id}/request.json"

      expect { post "/ingenic/downloads/#{download.id}/request.json" }.not_to change(
        IngenicDownloadRequest,
        :count,
      )

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.already_requested"),
      )
    end
  end

  describe "GET /ingenic/downloads/:id/file" do
    it "turns away a visitor who has not signed in" do
      download = resource(IngenicDownload::LOGIN_ONLY)

      get "/ingenic/downloads/#{download.id}/file.json"

      expect(response.status).to eq(403)
    end

    it "sends a browser navigation back to the centre rather than a wall of JSON" do
      download = resource(IngenicDownload::FORM_REQUIRED)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
      expect(response.location).to end_with("/ingenic/downloads")
    end

    it "sends the browser to an external address once access is settled" do
      download = resource(IngenicDownload::LOGIN_ONLY)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
      expect(response.location).to eq("https://example.com/sdk.tgz")
    end

    it "does not send the browser to a value that is not a web address" do
      download = resource(IngenicDownload::LOGIN_ONLY, file_url: "javascript:alert(1)")
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.location).not_to include("javascript")
    end

    it "serves an uploaded file to an account that holds a grant" do
      directory = Dir.mktmpdir("ingenic-download")
      SiteSetting.ingenic_download_storage_path = directory

      tempfile = Tempfile.new("sdk")
      tempfile.binmode
      tempfile.write("firmware")
      tempfile.rewind

      stored =
        Ingenic::DownloadStorage.store(
          ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: "sdk.bin"),
        )

      download =
        resource(
          IngenicDownload::APPROVAL_REQUIRED,
          storage_path: stored[:path],
          original_filename: "sdk.bin",
          file_url: nil,
        )

      with_profile
      IngenicDownloadGrant.issue!(user, download)
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(200)
      expect(response.headers["Content-Type"]).to eq("application/octet-stream")
      expect(response.headers["Content-Disposition"]).to include("attachment", "sdk.bin")
      # The body is handed back as an Enumerator so a firmware image is never
      # read into memory, so what the response promises about it is the length.
      expect(response.headers["Content-Length"]).to eq("8")
    ensure
      FileUtils.remove_entry(directory) if directory
    end

    it "refuses the file to a signed-in account without a grant" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file"

      expect(response.status).to eq(302)
    end

    it "reports a resource that has gone missing from storage instead of failing" do
      directory = Dir.mktmpdir("ingenic-download")
      SiteSetting.ingenic_download_storage_path = directory

      download =
        resource(
          IngenicDownload::LOGIN_ONLY,
          storage_path: "aa/gone.bin",
          original_filename: "gone.bin",
          file_url: nil,
        )
      sign_in(user)

      get "/ingenic/downloads/#{download.id}/file.json"

      expect(response.status).to eq(404)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("ingenic.downloads.not_available"),
      )
    ensure
      FileUtils.remove_entry(directory) if directory
    end
  end

  describe "the admin queue" do
    before { sign_in(admin) }

    it "lists a waiting application with the applicant's information" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      IngenicDownloadRequest.create!(user: user, download: download, message: "hello")

      get "/admin/plugins/discourse-ingenic/download-requests"

      expect(response.status).to eq(200)
      entry = response.parsed_body["requests"].first
      expect(entry["status"]).to eq("pending")
      expect(entry["profile_summary"]).to include("Ada")
      expect(response.parsed_body["pending_count"]).to eq(1)
    end

    it "grants access and tells the applicant when an application is approved" do
      Jobs.run_immediately!
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      request = IngenicDownloadRequest.create!(user: user, download: download)

      expect {
        put "/admin/plugins/discourse-ingenic/download-requests/#{request.id}/approve",
            params: {
              note: "welcome",
            }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response.status).to eq(200)
      expect(IngenicDownloadGrant.active.find_by(user: user, download: download)).to be_present
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:granted)
    end

    it "withdraws access when a grant is revoked" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile
      grant = IngenicDownloadGrant.issue!(user, download, granted_by: admin)
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:granted)

      delete "/admin/plugins/discourse-ingenic/download-grants/#{grant.id}"

      expect(response.status).to eq(200)
      expect(response.parsed_body["grant"]["active"]).to eq(false)
      expect(Ingenic::DownloadAccess.new(user, download).result.state).to eq(:needs_request)
    end

    it "is out of reach for an ordinary account" do
      sign_in(user)

      # The management routes sit behind a routing constraint, so for an account
      # that manages nothing they are not in the table at all. Whether that
      # surfaces as an unrouted request or as Discourse's 404 page depends on
      # the exception settings in play; neither reaches the controller.
      outcome =
        begin
          get "/admin/plugins/discourse-ingenic/download-requests"
          response.status
        rescue ActionController::RoutingError
          :unrouted
        end

      expect([:unrouted, 404]).to include(outcome)
    end
  end
end
