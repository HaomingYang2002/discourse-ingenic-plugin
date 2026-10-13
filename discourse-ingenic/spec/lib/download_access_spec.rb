# frozen_string_literal: true

require "rails_helper"

# The three tiers, and every state a visitor can be in on the way through them.
#
# This is the one place the rules are written down, so it is the one place they
# are tested: the listing asks this object which control to draw, and the file
# endpoint asks it whether to serve. A tier that is wrong here is wrong in both
# places at once, which is the point.
describe Ingenic::DownloadAccess do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { IngenicDownloadCategory.find_or_create_by!(name: "sdk", locale: "en") }

  def resource(level, name: "SDK")
    IngenicDownload.create!(
      name: name,
      product_slug: "t33",
      category: category,
      locale: "en",
      access_level: level,
      file_url: "https://example.com/sdk.tgz",
    )
  end

  def with_profile(user)
    IngenicDeveloperProfile.create!(user: user, data: { "full_name" => "Ada" })
    user
  end

  def state_for(user, download)
    described_class.new(user, download).result.state
  end

  describe "the sign-in tier" do
    it "asks a visitor to sign in, whichever tier the resource is" do
      expect(state_for(nil, resource(IngenicDownload::LOGIN_ONLY))).to eq(:anonymous)
      expect(state_for(nil, resource(IngenicDownload::APPROVAL_REQUIRED))).to eq(:anonymous)
    end

    it "lets any signed-in account have a login-only resource" do
      expect(state_for(user, resource(IngenicDownload::LOGIN_ONLY))).to eq(:granted)
    end
  end

  describe "the information tier" do
    it "asks for the developer information once" do
      download = resource(IngenicDownload::FORM_REQUIRED)

      expect(state_for(user, download)).to eq(:needs_profile)
      expect(state_for(with_profile(user), download)).to eq(:granted)
    end

    it "does not accept information in place of approval on the tier above" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)

      expect(state_for(with_profile(user), download)).to eq(:needs_request)
    end
  end

  describe "the approval tier" do
    it "walks an application from pending to granted" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      request = IngenicDownloadRequest.create!(user: user, download: download)

      expect(state_for(user, download)).to eq(:pending)

      request.approve!(admin)
      expect(state_for(user, download)).to eq(:granted)
    end

    it "keeps a rejection, so the applicant is not sent back to Apply" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadRequest.create!(user: user, download: download).reject!(admin, note: "no")

      expect(state_for(user, download)).to eq(:rejected)
    end

    it "ignores a grant that has been revoked" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadGrant.issue!(user, download).revoke!(admin)

      expect(state_for(user, download)).to eq(:needs_request)
    end

    it "ignores a grant whose time has run out" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadGrant.issue!(user, download, expires_at: 1.day.ago)

      expect(state_for(user, download)).to eq(:needs_request)
    end

    it "answers one applicant about one resource, not about the tier in general" do
      mine = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Mine")
      IngenicDownloadGrant.issue!(user, mine)
      theirs = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Theirs")
      other = Fabricate(:user)
      IngenicDownloadGrant.issue!(other, theirs)

      expect(state_for(user, mine)).to eq(:granted)
      expect(state_for(user, theirs)).to eq(:needs_request)
    end
  end

  # The listing decides every resource on the page at once. Loading the three
  # facts it depends on up front is what keeps the page's cost from growing with
  # its length, so the batch path has to give the same answers as the single one.
  describe ".for_list" do
    it "decides a whole page the same way it decides one resource" do
      open_resource = resource(IngenicDownload::LOGIN_ONLY, name: "Open")
      filled_in = resource(IngenicDownload::FORM_REQUIRED, name: "Form")
      applied_for = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Applied")
      declined = resource(IngenicDownload::APPROVAL_REQUIRED, name: "Declined")

      with_profile(user)
      IngenicDownloadRequest.create!(user: user, download: applied_for)
      IngenicDownloadRequest.create!(user: user, download: declined).reject!(admin)

      results = described_class.for_list(user, [open_resource, filled_in, applied_for, declined])

      expect(results.map(&:download)).to eq([open_resource, filled_in, applied_for, declined])
      expect(results.map(&:state)).to eq(%i[granted granted pending rejected])

      # The same four, asked one at a time. If the batch ever drifts from the
      # single-resource path, the button and the file endpoint stop agreeing.
      one_at_a_time = [open_resource, filled_in, applied_for, declined].map { |d| state_for(user, d) }
      expect(results.map(&:state)).to eq(one_at_a_time)
    end

    it "sees a grant it was loaded after" do
      download = resource(IngenicDownload::APPROVAL_REQUIRED)
      with_profile(user)
      IngenicDownloadGrant.issue!(user, download)

      expect(described_class.for_list(user, [download]).map(&:state)).to eq([:granted])
    end

    it "decides an anonymous listing without touching the account tables" do
      download = resource(IngenicDownload::LOGIN_ONLY)

      expect(described_class.for_list(nil, [download]).map(&:state)).to eq([:anonymous])
    end
  end
end
