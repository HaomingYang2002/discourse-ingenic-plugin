# frozen_string_literal: true

require "rails_helper"

# The partner strip in the footer. The two shapes carry different requirements,
# so what is tested here is that an entry which would render as a dead icon is
# refused at the point it is typed rather than discovered on the page.
describe IngenicSocialLink do
  def link(attrs = {})
    IngenicSocialLink.new({ label: "GitHub", kind: IngenicSocialLink::LINK }.merge(attrs))
  end

  it "accepts a link that has somewhere to go" do
    expect(link(href: "https://github.com/ingenic-official")).to be_valid
  end

  it "refuses a link with no destination" do
    record = link(href: "")

    expect(record).not_to be_valid
    expect(record.errors[:href]).to be_present
  end

  it "accepts a QR entry that has an image" do
    record = link(kind: IngenicSocialLink::QR, qr_image_url: "/uploads/wechat.png")

    expect(record).to be_valid
    expect(record).to be_qr
  end

  it "refuses a QR entry with no image, because there is nothing to show" do
    record = link(kind: IngenicSocialLink::QR, href: "https://example.com")

    expect(record).not_to be_valid
    expect(record.errors[:qr_image_url]).to be_present
  end

  it "refuses a kind it does not know" do
    expect(link(href: "https://example.com", kind: "video")).not_to be_valid
  end

  it "requires a label" do
    expect(link(label: "", href: "https://example.com")).not_to be_valid
  end

  it "orders by position and then by id" do
    second = IngenicSocialLink.create!(label: "WeChat", kind: IngenicSocialLink::QR, qr_image_url: "/a.png", position: 1)
    first = IngenicSocialLink.create!(label: "GitHub", kind: IngenicSocialLink::LINK, href: "https://example.com", position: 0)

    expect(described_class.ordered.to_a).to eq([first, second])
  end

  it "leaves unpublished entries out of the published set" do
    IngenicSocialLink.create!(label: "GitHub", kind: IngenicSocialLink::LINK, href: "https://example.com", published: false)

    expect(described_class.published.count).to eq(0)
  end
end
