# frozen_string_literal: true

require "rails_helper"

# The official identity badge: Discourse's own group flair, handed out on
# membership rather than by making the group somebody's primary group.
#
# Most of what follows is about what must *not* happen. A badge a member chose
# for themselves survives being added to an official group, and a badge from a
# group that is not on the list is never touched. Those are the cases a
# careless version of this gets wrong, and they are the cases that would be
# noticed by the member rather than by an admin.
describe Ingenic::OfficialFlair do
  fab!(:member) { Fabricate(:user) }
  fab!(:official) { Fabricate(:group, name: "ingenic-official", flair_icon: "fab-github") }
  fab!(:second) { Fabricate(:group, name: "ingenic-staff", flair_icon: "fab-discourse") }
  fab!(:plain) { Fabricate(:group, name: "ingenic-fans", flair_icon: "fab-github") }

  before do
    SiteSetting.ingenic_enabled = true
    SiteSetting.ingenic_official_groups = "ingenic-official"
  end

  # Read back from the database rather than from the object under test: the
  # question is what the member is wearing, and the answer has to survive the
  # request that wrote it.
  def badge(user)
    user.reload.flair_group_id
  end

  describe "a member joining a listed group" do
    it "wears that group's badge" do
      official.add(member)

      expect(badge(member)).to eq(official.id)
    end

    it "wears nothing for a listed group that has no badge to give" do
      awaiting = Fabricate(:group, name: "ingenic-partners")
      SiteSetting.ingenic_official_groups = "ingenic-partners"

      awaiting.add(member)

      expect(badge(member)).to be_nil
    end

    it "wears nothing for a group that is not on the list" do
      plain.add(member)

      expect(badge(member)).to be_nil
    end

    # A group is named "T Series" on its own page, and an admin typing it into
    # the setting has no way to know whether a stray capital matters. It does
    # not.
    it "wears the badge however the group was spelled in the setting" do
      SiteSetting.ingenic_official_groups = "  Ingenic-Official "

      official.add(member)

      expect(badge(member)).to eq(official.id)
    end
  end

  # Discourse's own preferences page offers a member every flair they are
  # entitled to, so a member can be wearing a badge from a group with nothing to
  # do with this list. That badge is a choice they made, and being added to an
  # official group is not a reason to take it away.
  describe "a badge the member chose for themselves" do
    before { member.update!(flair_group_id: plain.id) }

    it "survives being added to a listed group" do
      official.add(member)

      expect(badge(member)).to eq(plain.id)
    end

    it "survives a re-check that finds them in no listed group" do
      described_class.sync_user(member)

      expect(badge(member)).to eq(plain.id)
    end
  end

  describe "a member leaving" do
    it "wears nothing once they are in no listed group" do
      official.add(member)
      expect(badge(member)).to eq(official.id)

      official.remove(member)

      expect(badge(member)).to be_nil
    end

    # The badge they leave with is not the only one they are entitled to, and
    # losing a badge should not mean losing all of them.
    it "takes up the badge of the listed group they are still in" do
      SiteSetting.ingenic_official_groups = "ingenic-official|ingenic-staff"
      official.add(member)
      second.add(member)
      expect(badge(member)).to eq(official.id)

      official.remove(member)

      expect(badge(member)).to eq(second.id)
    end
  end

  describe "a member of more than one listed group" do
    # Both memberships are in place before either assertion, so only the order
    # of the list can decide which of the two badges is worn.
    it "wears the badge of the group listed first" do
      second.add(member)
      official.add(member)

      SiteSetting.ingenic_official_groups = "ingenic-staff|ingenic-official"
      described_class.sync_user(member)
      expect(badge(member)).to eq(second.id)

      SiteSetting.ingenic_official_groups = "ingenic-official|ingenic-staff"
      described_class.sync_user(member)
      expect(badge(member)).to eq(official.id)
    end
  end

  describe "a group taken off the list" do
    it "has its badges taken back" do
      official.add(member)
      SiteSetting.ingenic_official_groups = ""

      described_class.sync_all(retired: [official.id])

      expect(badge(member)).to be_nil
    end

    it "hands them out again when the group is listed once more" do
      SiteSetting.ingenic_official_groups = ""
      official.add(member)
      expect(badge(member)).to be_nil

      Jobs.run_immediately!
      SiteSetting.ingenic_official_groups = "ingenic-official"

      expect(badge(member)).to eq(official.id)
    end

    # The list names groups, so renaming one takes it off the list without
    # announcing anything. The id it is being renamed away from is the only
    # record that the badge it handed out was ever this plugin's doing, which is
    # why the handler passes it along.
    it "takes its badges back when it is renamed out from under the list" do
      official.add(member)
      official.update!(name: "ingenic-official-renamed")

      described_class.sync_all(retired: [official.id])

      expect(badge(member)).to be_nil
    end

    # The other half of the same fact, written down because it is the cost of
    # the design rather than a bug in it: a badge this plugin handed out is
    # indistinguishable from one the member picked, so a re-check that is not
    # told which group to look for cannot take it back.
    it "would keep them if the re-check did not know which group to look for" do
      official.add(member)
      official.update!(name: "ingenic-official-renamed")

      described_class.sync_all

      expect(badge(member)).to eq(official.id)
    end
  end

  describe "a badge uploaded after the members were added" do
    it "reaches members the moment the group has one" do
      awaiting = Fabricate(:group, name: "ingenic-partners")
      SiteSetting.ingenic_official_groups = "ingenic-partners"
      awaiting.add(member)
      expect(badge(member)).to be_nil

      Jobs.run_immediately!
      awaiting.update!(flair_icon: "fab-github")

      expect(badge(member)).to eq(awaiting.id)
    end

    # A recoloured badge is the same badge: it changes how it looks to everyone
    # already wearing it and nothing about who wears it.
    it "does not treat a recolouring as a badge arriving" do
      official.update!(flair_bg_color: "FF0000")

      expect(described_class.flair_gained_or_lost?(official)).to eq(false)
    end

    it "treats a group gaining an icon as a badge arriving" do
      awaiting = Fabricate(:group, name: "ingenic-partners")

      awaiting.update!(flair_icon: "fab-github")

      expect(described_class.flair_gained_or_lost?(awaiting)).to eq(true)
    end
  end
end
