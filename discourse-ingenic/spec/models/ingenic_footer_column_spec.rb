# frozen_string_literal: true

require "rails_helper"

# A footer column and the links under it. The two associations over one table are
# the point: the management screen shows everything, the page shows what is
# published, and neither has to filter in Ruby.
describe IngenicFooterColumn do
  fab!(:column) { IngenicFooterColumn.create!(title: "Developer Services", position: 0) }

  def link(attrs = {})
    IngenicFooterLink.create!(
      { column: column, label: "Downloads", href: "/ingenic/downloads" }.merge(attrs),
    )
  end

  it "requires a heading" do
    expect(IngenicFooterColumn.new(title: "")).not_to be_valid
  end

  it "keeps every link for the management screen" do
    shown = link(label: "Shown")
    hidden = link(label: "Hidden", published: false)

    expect(column.links.reload.to_a).to eq([shown, hidden])
  end

  it "offers only published links to the page" do
    shown = link(label: "Shown")
    link(label: "Hidden", published: false)

    expect(column.published_links.to_a).to eq([shown])
  end

  it "orders links by position" do
    second = link(label: "Second", position: 1)
    first = link(label: "First", position: 0)

    expect(column.published_links.to_a).to eq([first, second])
  end

  it "removes the links with the column" do
    link

    expect { column.destroy! }.to change(IngenicFooterLink, :count).by(-1)
  end

  it "requires a label and a destination on a link" do
    expect(IngenicFooterLink.new(column: column, label: "", href: "/x")).not_to be_valid
    expect(IngenicFooterLink.new(column: column, label: "X", href: "")).not_to be_valid
  end

  it "records whether a link leaves the site" do
    expect(link(external: true)).to be_external
    expect(link).not_to be_external
  end
end
