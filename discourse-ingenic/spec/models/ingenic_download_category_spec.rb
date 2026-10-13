# frozen_string_literal: true

require "rails_helper"

# The classification list, which used to be a constant in the download model.
describe IngenicDownloadCategory do
  def category(attrs = {})
    IngenicDownloadCategory.create!({ name: "sdk", locale: "en" }.merge(attrs))
  end

  it "requires a name" do
    expect(IngenicDownloadCategory.new(name: "", locale: "en")).not_to be_valid
  end

  it "refuses the same name twice in one locale" do
    category

    expect(IngenicDownloadCategory.new(name: "sdk", locale: "en")).not_to be_valid
  end

  it "allows the same name in another locale" do
    category
    other = IngenicDownloadCategory.new(name: "sdk", locale: "zh_CN")

    expect(other).to be_valid
  end

  it "orders by position and then by name" do
    second = category(name: "manual", position: 1)
    first = category(name: "firmware", position: 0)

    expect(described_class.ordered.to_a).to eq([first, second])
  end

  it "counts the resources filed under it" do
    record = category
    IngenicDownload.create!(
      name: "T33 SDK",
      product_slug: "t33",
      category: record,
      locale: "en",
      file_url: "https://example.com/sdk.tgz",
    )

    expect(record.download_count).to eq(1)
  end

  it "leaves a resource unfiled rather than deleting it when the category goes" do
    record = category
    download =
      IngenicDownload.create!(
        name: "T33 SDK",
        product_slug: "t33",
        category: record,
        locale: "en",
        file_url: "https://example.com/sdk.tgz",
      )

    record.destroy!

    expect(download.reload.category_id).to be_nil
    expect(download.category_name).to be_nil
  end
end
