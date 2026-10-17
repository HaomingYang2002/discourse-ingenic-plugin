# frozen_string_literal: true

require "rails_helper"

# The row of buttons in the middle of the header. The one shape that would
# render as an empty clickable gap — no name, no icon, no picture — is refused
# where it is typed rather than left to be noticed on the page.
describe IngenicHeaderLink do
  def link(attrs = {})
    IngenicHeaderLink.new({ label: "Ingenic", href: "https://www.ingenic.com" }.merge(attrs))
  end

  it "accepts a button with a name and somewhere to go" do
    expect(link).to be_valid
  end

  it "requires a name" do
    record = link(label: "")

    expect(record).not_to be_valid
    expect(record.errors[:label]).to be_present
  end

  it "requires a destination" do
    record = link(href: "")

    expect(record).not_to be_valid
    expect(record.errors[:href]).to be_present
  end

  it "accepts an icon-only button drawn with a built-in icon" do
    expect(link(show_label: false, icon: "fab-github")).to be_valid
  end

  it "accepts an icon-only button drawn with an image" do
    expect(link(show_label: false, image_url: "/uploads/logo.svg")).to be_valid
  end

  it "refuses an icon-only button that has nothing to draw" do
    record = link(show_label: false, icon: "", image_url: "")

    expect(record).not_to be_valid
    expect(record.errors[:icon]).to be_present
  end

  it "orders by position and then by id" do
    second = IngenicHeaderLink.create!(label: "GitHub", href: "https://github.com", position: 1)
    first = IngenicHeaderLink.create!(label: "Ingenic", href: "https://www.ingenic.com", position: 0)

    expect(described_class.ordered.to_a).to eq([first, second])
  end

  it "leaves unpublished buttons out of the published set" do
    IngenicHeaderLink.create!(label: "Ingenic", href: "https://www.ingenic.com", published: false)

    expect(described_class.published.count).to eq(0)
  end
end
