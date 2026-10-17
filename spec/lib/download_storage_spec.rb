# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# Uploaded SDKs and firmware, on disk.
#
# The two properties worth testing are that a filename from a browser never
# becomes a filesystem path, and that a stored path can never point outside the
# configured root — the first is how a name gets in, the second is what stops it
# mattering if one ever does.
describe Ingenic::DownloadStorage do
  around do |example|
    directory = Dir.mktmpdir("ingenic-storage")
    SiteSetting.ingenic_download_storage_path = directory
    example.run
  ensure
    FileUtils.remove_entry(directory)
  end

  def uploaded(filename, content)
    file = Tempfile.new(["ingenic", File.extname(filename)])
    file.binmode
    file.write(content)
    file.rewind

    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: filename)
  end

  it "writes the upload and reports what the row has to remember" do
    stored = described_class.store(uploaded("firmware.img", "binary"))

    expect(stored[:size]).to eq(6)
    expect(stored[:sha256]).to eq(Digest::SHA256.hexdigest("binary"))
    expect(described_class.exist?(stored[:path])).to eq(true)
  end

  it "names the file itself rather than trusting the uploader" do
    stored = described_class.store(uploaded("../../etc/passwd", "x"))

    expect(stored[:path]).not_to include("passwd")
    expect(stored[:path]).not_to include("..")
  end

  it "keeps the extension so the file identifies itself when it is served" do
    expect(described_class.store(uploaded("sdk.tar.gz", "x"))[:path]).to end_with(".gz")
  end

  it "refuses a stored path that climbs out of the root" do
    expect { described_class.absolute_path("../../etc/passwd") }.to raise_error(
      Discourse::InvalidParameters,
    )
  end

  it "deletes what it wrote" do
    stored = described_class.store(uploaded("a.bin", "x"))
    described_class.delete(stored[:path])

    expect(described_class.exist?(stored[:path])).to eq(false)
  end

  it "treats a file that is no longer there as missing rather than an error" do
    expect(described_class.exist?("00/not-a-real-file.bin")).to eq(false)
  end
end
