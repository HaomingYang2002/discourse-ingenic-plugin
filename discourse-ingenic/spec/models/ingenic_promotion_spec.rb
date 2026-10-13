# frozen_string_literal: true

require "rails_helper"

# The homepage promotion slots. What matters here is the window: a campaign with
# dates must take itself off the page, because the alternative is someone
# remembering to unpublish it.
describe IngenicPromotion do
  def promotion(attrs = {})
    IngenicPromotion.create!({ title: "GitHub", locale: "en" }.merge(attrs))
  end

  it "shows an entry with no dates" do
    expect(promotion).to be_live
    expect(described_class.live.count).to eq(1)
  end

  it "hides an entry that has not started" do
    record = promotion(starts_at: 2.days.from_now)

    expect(record).not_to be_live
    expect(described_class.live.count).to eq(0)
  end

  it "hides an entry whose window has closed" do
    record = promotion(ends_at: 2.days.ago)

    expect(record).not_to be_live
    expect(described_class.live.count).to eq(0)
  end

  it "shows an entry inside its window" do
    record = promotion(starts_at: 1.day.ago, ends_at: 1.day.from_now)

    expect(record).to be_live
    expect(described_class.live.count).to eq(1)
  end

  it "leaves an unpublished entry out of the live set even inside its window" do
    record = promotion(published: false, starts_at: 1.day.ago, ends_at: 1.day.from_now)

    expect(described_class.live.count).to eq(0)
    expect(record.live?).to eq(false)
  end

  it "orders by position and then by id, so equal positions are stable" do
    second = promotion(title: "Docs", position: 1)
    first = promotion(title: "Downloads", position: 0)

    expect(described_class.ordered.to_a).to eq([first, second])
  end

  it "requires a title" do
    expect(described_class.new(title: "", locale: "en")).not_to be_valid
  end

  it "reports whether the button leaves the site" do
    expect(promotion(button_external: true)).to be_external
  end
end
