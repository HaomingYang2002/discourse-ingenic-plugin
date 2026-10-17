# frozen_string_literal: true

require "rails_helper"

describe IngenicDownload do
  def download(**attrs)
    IngenicDownload.new(
      {
        name: "SDK",
        family: "chip",
        product_slug: "t33",
        locale: "en",
        access_level: IngenicDownload::LOGIN_ONLY,
        file_url: "https://example.com/sdk.tgz",
      }.merge(attrs),
    )
  end

  it "requires a part number for a chip resource" do
    expect(download(product_slug: nil)).not_to be_valid
  end

  # An algorithm runs across chips; requiring a slug would either invent an
  # attachment or keep algorithms out of the catalogue.
  it "accepts an algorithm without a part number" do
    expect(download(family: "algorithm", product_slug: nil)).to be_valid
  end

  # A row switched from chip to algorithm after it had a slug must not keep it:
  # otherwise a product filter would still draw the algorithm.
  it "clears a part number when the resource is an algorithm" do
    record = download(family: "algorithm", product_slug: "t33")

    expect(record).to be_valid
    expect(record.product_slug).to be_nil
  end
end
