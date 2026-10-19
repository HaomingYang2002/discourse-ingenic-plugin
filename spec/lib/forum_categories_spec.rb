# frozen_string_literal: true

require "rails_helper"

# The forum sections the navigation links to, and the two of them that differ
# only in who may post.
#
# What is worth testing here is not that a category can be created — Discourse
# does that — but the two things a reader would notice and a log would not: that
# Open Source has two sub-forums rather than none, and that "anyone may publish"
# and "only an administrator may publish" are actually different permissions on
# the two of them. A seeder that quietly granted `everyone: :full` to both would
# pass every other check in this suite.
describe Ingenic::ForumCategories do
  # What the forum actually holds, in the shape the permission columns are
  # stored in: Discourse writes "everyone may post" by writing no row at all, so
  # a category with no permission rows is not one nobody may use — it is the
  # ordinary case, and reading it back as an empty hash is what made the two
  # sub-forums look identical to a section.
  def permissions(category)
    rows =
      category.category_groups.each_with_object({}) do |row, result|
        result[row.group_name] = row.permission_type
      end

    return rows if rows.present?
    return {} if category.read_restricted

    { "everyone" => CategoryGroup.permission_types[:full] }
  end

  def actions(report)
    report.map { |row| row[:action] }
  end

  it "creates every section the navigation links to" do
    report = described_class.seed!

    expect(actions(report)).to all(eq(:created))
    described_class.slugs.each do |slug|
      expect(Category.find_by(slug: slug)).to be_present, "#{slug} was not created"
    end
  end

  it "reports nothing missing once it has run" do
    expect(described_class.missing).to contain_exactly(*described_class.slugs)

    described_class.seed!

    expect(described_class.missing).to be_empty
  end

  it "files both sub-forums under Open Source" do
    described_class.seed!
    section = Category.find_by(slug: "open-source")

    %w[third-party official].each do |slug|
      expect(Category.find_by(slug: slug).parent_category_id).to eq(section.id)
    end
  end

  it "leaves Open Source at the top level, after Technical Discussions" do
    described_class.seed!

    open_source = Category.find_by(slug: "open-source")
    expect(open_source.parent_category_id).to be_nil
    expect(open_source.position).to eq(2)
  end

  it "puts a chip under its series under Technical Discussions" do
    described_class.seed!

    technical = Category.find_by(slug: "technical-discussions")
    series = Category.find_by(slug: "t-series")
    chip = Category.find_by(slug: "t33")

    expect(series.parent_category_id).to eq(technical.id)
    expect(chip.parent_category_id).to eq(series.id)
  end

  it "turns on the nesting level the tree needs" do
    SiteSetting.max_category_nesting = 2

    described_class.seed!

    expect(SiteSetting.max_category_nesting).to eq(3)
  end

  it "moves a section that is still at the old address instead of copying it" do
    # The address this section is moving away from was three levels deep.
    SiteSetting.max_category_nesting = 3

    technical = Fabricate(:category, slug: "technical-discussions")
    old = Fabricate(:category, slug: "open-source", parent_category: technical)
    Fabricate(:category, slug: "third-party", parent_category: old)

    report = described_class.seed!
    row = report.find { |entry| entry[:slug] == "open-source" }

    expect(row[:action]).to eq(:moved)
    expect(row[:detail]).to include("top level")
    expect(old.reload.parent_category_id).to be_nil
    expect(old.position).to eq(2)
    expect(Category.where(slug: "open-source").count).to eq(1)
    expect(Category.find_by(slug: "third-party").parent_category_id).to eq(old.id)
  end

  it "takes no topics in the section itself, only in its sub-forums" do
    described_class.seed!

    expect(permissions(Category.find_by(slug: "open-source"))).to eq(
      "everyone" => CategoryGroup.permission_types[:readonly],
    )
  end

  it "lets anyone post a third-party project and only administrators an official one" do
    described_class.seed!

    expect(permissions(Category.find_by(slug: "third-party"))).to eq(
      "everyone" => CategoryGroup.permission_types[:full],
    )

    expect(permissions(Category.find_by(slug: "official"))).to eq(
      "everyone" => CategoryGroup.permission_types[:readonly],
      "admins" => CategoryGroup.permission_types[:full],
    )
  end

  it "keeps announcements readable by everyone and postable by staff" do
    described_class.seed!

    expect(permissions(Category.find_by(slug: "official-announcements"))).to eq(
      "everyone" => CategoryGroup.permission_types[:readonly],
      "staff" => CategoryGroup.permission_types[:full],
    )
  end

  it "leaves a category that is already there as the forum has it" do
    category = Fabricate(:category, name: "In-house name", slug: "technical-discussions")

    report = described_class.seed!
    row = report.find { |entry| entry[:slug] == "technical-discussions" }

    expect(row[:action]).to eq(:kept)
    expect(category.reload.name).to eq("In-house name")
  end

  it "says so when a category's permissions are not the ones it asks for" do
    Fabricate(:category, slug: "technical-discussions", permissions: { everyone: :readonly })

    row = described_class.seed!.find { |entry| entry[:slug] == "technical-discussions" }

    expect(row[:action]).to eq(:kept)
    expect(row[:detail]).to include("everyone: readonly", "everyone: full")
  end

  it "does not call permissions different when they already match" do
    described_class.seed!

    row = described_class.seed!.find { |entry| entry[:slug] == "technical-discussions" }

    expect(row[:action]).to eq(:kept)
    expect(row[:detail]).to be_nil
  end

  it "puts the asked-for permissions back when told to" do
    # Official Open Source is a sub-forum, so the one already on the forum has
    # to be filed under the section too — the seeder looks a sub-forum up inside
    # its section, and a top-level category of the same slug would be moved
    # under it rather than left beside it.
    section = Fabricate(:category, slug: "open-source", permissions: { everyone: :readonly })
    category =
      Fabricate(
        :category,
        slug: "official",
        parent_category: section,
        permissions: { everyone: :full },
      )

    report = described_class.seed!(permissions: true)
    row = report.find { |entry| entry[:slug] == "official" }

    expect(row[:action]).to eq(:repermissioned)
    expect(permissions(category.reload)).to eq(
      "everyone" => CategoryGroup.permission_types[:readonly],
      "admins" => CategoryGroup.permission_types[:full],
    )
  end

  it "does not create a sub-forum whose section is not there" do
    allow(Category).to receive(:find_by).and_call_original
    allow(Category).to receive(:find_by).with(slug: "open-source").and_return(nil)

    row = described_class.seed!.find { |entry| entry[:slug] == "third-party" }

    expect(row[:action]).to eq(:skipped)
    expect(row[:detail]).to include("open-source")
  end

  it "gives each section a description topic rather than a category nobody can open" do
    described_class.seed!

    described_class.slugs.each do |slug|
      category = Category.find_by(slug: slug)
      expect(category.topic_id).to be_present, "#{slug} has no about topic"
    end
  end

  context "with content localization on" do
    before do
      SiteSetting.content_localization_enabled = true
      SiteSetting.content_localization_supported_locales = "zh_CN"
    end

    it "names the sections in Chinese as well as in English" do
      described_class.seed!
      category = Category.find_by(slug: "open-source")

      localization = category.category_localizations.find_by(locale: "zh_CN")

      expect(category.locale).to eq("en")
      expect(localization.name).to eq("开源版块")
      expect(localization.name).not_to eq(category.name)
      expect(localization.description).to eq("基于君正芯片的开源项目，包括官方与第三方。")
    end

    it "names and describes every section, not only the one a test happened to open" do
      described_class.seed!

      described_class::SPECS.each do |spec|
        localization =
          Category.find_by(slug: spec[:slug]).category_localizations.find_by(locale: "zh_CN")

        expect(localization.name).to eq(spec[:zh_name]), "#{spec[:slug]} is still English"
        expect(localization.description).to eq(spec[:zh_description]),
                                             "#{spec[:slug]} still describes itself in English"
      end
    end

    it "still creates every section" do
      expect(actions(described_class.seed!).uniq).to eq([:created])
    end

    it "adds the names to sections seeded before the feature was switched on" do
      SiteSetting.content_localization_enabled = false
      described_class.seed!

      expect(Category.find_by(slug: "technical-discussions").category_localizations).to be_empty

      SiteSetting.content_localization_enabled = true
      report = described_class.seed!

      expect(actions(report).uniq).to eq([:kept])
      category = Category.find_by(slug: "technical-discussions")
      expect(category.locale).to eq("en")
      localization = category.category_localizations.find_by(locale: "zh_CN")
      expect(localization.name).to eq("技术讨论")
      expect(localization.description).to eq("关于君正芯片的问题、解答与实践经验。")
    end

    it "does not add a second row for a name it has already written" do
      described_class.seed!
      described_class.seed!

      category = Category.find_by(slug: "official-announcements")
      expect(category.category_localizations.where(locale: "zh_CN").count).to eq(1)
      expect(category.category_localizations.find_by(locale: "zh_CN").name).to eq("官方公告")
    end

    it "adds a description to a translation row that was seeded without one" do
      described_class.seed!
      category = Category.find_by(slug: "open-source")
      localization = category.category_localizations.find_by(locale: "zh_CN")
      localization.update_columns(description: nil)

      described_class.seed!

      expect(
        category.category_localizations.find_by(locale: "zh_CN").description,
      ).to eq("基于君正芯片的开源项目，包括官方与第三方。")
    end

    it "leaves a Chinese name an administrator has changed" do
      described_class.seed!
      category = Category.find_by(slug: "official-announcements")
      category.category_localizations.find_by(locale: "zh_CN").update!(name: "站务公告")

      described_class.seed!

      expect(
        category.category_localizations.find_by(locale: "zh_CN").name,
      ).to eq("站务公告")
    end

    it "leaves a Chinese description an administrator has changed" do
      described_class.seed!
      category = Category.find_by(slug: "official-announcements")
      category.category_localizations.find_by(locale: "zh_CN").update!(
        description: "站务组发布的通知。",
      )

      described_class.seed!

      expect(
        category.category_localizations.find_by(locale: "zh_CN").description,
      ).to eq("站务组发布的通知。")
    end
  end

  context "with content localization off" do
    before { SiteSetting.content_localization_enabled = false }

    it "does not build localizations nothing would read" do
      described_class.seed!

      expect(Category.find_by(slug: "open-source").category_localizations).to be_empty
    end
  end
end
