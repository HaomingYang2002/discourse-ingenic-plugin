# frozen_string_literal: true

require "rails_helper"

# A row here says "this group may manage this whole screen". The screen
# vocabulary is closed, so a typo is a validation failure rather than a grant
# that silently matches nothing.
describe IngenicGroupPermission do
  fab!(:group) { Fabricate(:group) }

  it "requires a known feature" do
    expect(described_class.new(group: group, feature: "documentation")).to be_valid
    expect(described_class.new(group: group, feature: "everything")).not_to be_valid
  end

  it "refuses the same group and feature twice" do
    described_class.create!(group: group, feature: "downloads")

    expect(described_class.new(group: group, feature: "downloads")).not_to be_valid
  end

  it "allows one group to hold several screens" do
    described_class.create!(group: group, feature: "downloads")
    described_class.create!(group: group, feature: "points")

    expect(described_class.where(group: group).count).to eq(2)
  end

  it "offers only groups an administrator can meaningfully tick" do
    names = described_class.assignable_groups.map(&:name)

    expect(names).to include(group.name)
    expect(names).not_to include("everyone")
    expect(names).not_to include("admins")
    expect(names).not_to include("trust_level_0")
  end
end
