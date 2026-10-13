# frozen_string_literal: true

require "digest"
require "fileutils"

module Ingenic
  # Where uploaded SDKs and firmware live on disk.
  #
  # The root defaults to a directory beside the application rather than under
  # `public/`, because that is the difference between a permission check and a
  # decoration: a file the web server will serve to anyone who guesses its URL
  # cannot be gated by anything this plugin does. Delivery streams the bytes
  # through the controller instead of handing back a path, so the two stay
  # consistent wherever the root points.
  module DownloadStorage
    DEFAULT_DIRECTORY = "ingenic-downloads"
    CHUNK = 256.kilobytes

    module_function

    def root
      configured = SiteSetting.ingenic_download_storage_path.to_s.strip
      Pathname.new(configured.presence || Rails.root.join(DEFAULT_DIRECTORY).to_s)
    end

    # Writes the upload and returns what the row has to remember: where it went,
    # what it hashes to, and how big it is. The digest is computed while writing
    # so a large firmware image is never read twice.
    def store(uploaded)
      digest = Digest::SHA256.new
      byte_size = 0
      relative = relative_path_for(uploaded.original_filename)

      target = absolute_path(relative)
      FileUtils.mkdir_p(target.dirname)

      File.open(target, "wb") do |file|
        while (chunk = uploaded.read(CHUNK))
          digest.update(chunk)
          byte_size += chunk.bytesize
          file.write(chunk)
        end
      end

      { path: relative, sha256: digest.hexdigest, size: byte_size }
    end

    def absolute_path(relative)
      candidate = root.join(relative).cleanpath
      root_path = root.cleanpath

      unless candidate.to_s.start_with?("#{root_path}/")
        raise Discourse::InvalidParameters.new("storage path escapes the configured root")
      end

      candidate
    end

    def exist?(relative)
      relative.present? && absolute_path(relative).file?
    end

    def delete(relative)
      return if relative.blank?

      path = absolute_path(relative)
      File.delete(path) if path.file?
    end

    def writable?
      FileUtils.mkdir_p(root)
      File.writable?(root)
    rescue StandardError
      false
    end

    # Names come from a random token plus the extension, never from what the
    # uploader called the file: a filename arrives from a browser, and a value
    # from a browser is not something to build a filesystem path out of. The
    # original name is kept on the row for the download dialog instead.
    def relative_path_for(original_filename)
      extension = File.extname(original_filename.to_s).slice(0, 12).to_s.gsub(/[^A-Za-z0-9.]/, "")
      token = SecureRandom.hex(16)

      # Two levels so one directory does not accumulate every file ever uploaded.
      File.join(token[0, 2], "#{token}#{extension}")
    end
  end
end
