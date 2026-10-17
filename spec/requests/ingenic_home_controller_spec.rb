# frozen_string_literal: true

require "rails_helper"

describe IngenicHomeController do
  describe "GET /ingenic/home" do
    it "serves the app shell, so the page has an address of its own" do
      get "/ingenic/home"

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end

    it "serves it to a signed-out visitor as well" do
      get "/ingenic/home"

      expect(response.status).to eq(200)
    end

    it "answers the same way for a fetch, rather than an empty body" do
      get "/ingenic/home", headers: { "X-Requested-With" => "XMLHttpRequest" }

      expect(response.status).to eq(200)
      expect(response.body).to include('id="data-preloaded"')
    end
  end

  # The front page is a registered homepage rather than a block drawn over a
  # topic list. These four things are what that means, and each of them is
  # something the earlier arrangement got wrong.
  describe "the homepage option" do
    it "is offered to the default_homepage setting" do
      option =
        DiscoursePluginRegistry.homepage_options.find { |entry| entry[:id] == "ingenic-home" }

      expect(option).to be_present
      expect(option[:path]).to eq("/ingenic/home")
      expect(HomepageSiteSetting.choices).to include("ingenic-home")
    end

    it "becomes the site's homepage when it is selected" do
      SiteSetting.default_homepage = "ingenic-home"

      expect(SiteSetting.homepage).to eq("ingenic-home")
    end

    it "stops being offered when the plugin is switched off" do
      SiteSetting.ingenic_enabled = false

      expect(HomepageSiteSetting.choices).not_to include("ingenic-home")
    end

    it "falls back to the ordinary homepage for a site that had it selected" do
      SiteSetting.default_homepage = "ingenic-home"
      SiteSetting.ingenic_enabled = false

      expect(SiteSetting.homepage).not_to eq("ingenic-home")
    end

    it "is a homepage a signed-out visitor may have" do
      SiteSetting.default_homepage = "ingenic-home"

      expect(SiteSetting.anonymous_homepage).to eq("ingenic-home")
    end
  end
end
