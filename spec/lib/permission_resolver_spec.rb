# frozen_string_literal: true

require "rails_helper"

describe Ingenic::PermissionResolver do
  fab!(:user) { Fabricate(:user) }
  fab!(:group) { Fabricate(:group) }
  # A grant on a series reaches everything filed under it, so the fixture is the
  # tree the plugin actually builds: a series, the chips beneath it, and the
  # versions and pages that hang off a chip. Only a chip may have a parent —
  # `kind` defaults to `series`, and a series with a parent is refused.
  fab!(:family) { IngenicDocProduct.create!(slug: "t-series", name: "T Series", locale: "en") }
  fab!(:child) do
    IngenicDocProduct.create!(
      slug: "t33",
      name: "T33",
      kind: IngenicDocProduct::CHIP,
      locale: "en",
      parent: family,
    )
  end
  fab!(:other_family) { IngenicDocProduct.create!(slug: "c-series", name: "C Series", locale: "en") }
  fab!(:version) do
    IngenicDocVersion.create!(product: child, slug: "latest", label: "Latest", locale: "en")
  end
  fab!(:page) do
    IngenicDocPage.create!(version: version, slug: "overview", title: "Overview", locale: "en")
  end

  it "inherits product grants through versions and pages" do
    IngenicPermission.create!(user: user, resource_type: "IngenicDocProduct", resource_id: family.id)
    resolver = described_class.new(user)

    expect(resolver.can_manage?(child)).to eq(true)
    expect(resolver.can_manage?(version)).to eq(true)
    expect(resolver.can_manage?(page)).to eq(true)
    expect(resolver.can_manage?(other_family)).to eq(false)
  end

  it "supports group grants" do
    group.add(user)
    IngenicPermission.create!(group: group, resource_type: "IngenicDocProduct", resource_id: family.id)

    expect(described_class.new(user).can_manage?(child)).to eq(true)
  end

  it "limits a page grant to that page subtree" do
    IngenicPermission.create!(user: user, resource_type: "IngenicDocPage", resource_id: page.id)

    expect(described_class.new(user).can_manage?(page)).to eq(true)
    expect(described_class.new(user).can_manage?(family)).to eq(false)
  end

  it "lets administrators manage every record" do
    user.update!(admin: true)

    expect(described_class.new(user).can_manage?(other_family)).to eq(true)
    expect(described_class.new(user).can_manage_permissions?).to eq(true)
  end

  describe "group feature grants" do
    it "lets a group manage every record on the screen it was given" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "documentation")

      resolver = described_class.new(user)

      expect(resolver.can_manage_feature?("documentation")).to eq(true)
      expect(resolver.can_manage?(family)).to eq(true)
      expect(resolver.can_manage?(other_family)).to eq(true)
      expect(resolver.visible_ids(IngenicDocProduct)).to contain_exactly(family, other_family, child)
    end

    it "keeps the other screens out of the grant" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "documentation")

      resolver = described_class.new(user)

      expect(resolver.can_manage_feature?("boards")).to eq(false)
      expect(resolver.can_manage_feature?("downloads")).to eq(false)
    end

    it "leaves a user outside the group with nothing" do
      other = Fabricate(:user)
      IngenicGroupPermission.create!(group: group, feature: "documentation")

      expect(described_class.new(other).can_manage?(family)).to eq(false)
    end

    it "counts as content management for the navigation" do
      group.add(user)
      IngenicGroupPermission.create!(group: group, feature: "points")

      expect(described_class.new(user).can_manage_any_content?).to eq(true)
    end
  end
end
