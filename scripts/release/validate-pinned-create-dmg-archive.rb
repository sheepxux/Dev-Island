#!/usr/bin/env ruby

require "digest"
require "optparse"
require "rubygems/package"
require "zlib"

module PinnedCreateDMGArchive
  class ValidationError < StandardError; end

  MAX_COMPRESSED_BYTES = 1_048_576
  ARCHIVE_HASH_CHUNK_BYTES = 65_536
  MAX_ENTRY_BYTES = 524_288
  MAX_LOGICAL_BYTES = 1_048_576
  MAX_PATH_BYTES = 512
  MAX_COMPONENT_BYTES = 255
  MAX_PATH_DEPTH = 5
  EXPECTED_RECORD_COUNT = 28
  EXPECTED_FILESYSTEM_ENTRY_COUNT = 27
  EXPECTED_REGULAR_FILE_COUNT = 17
  EXPECTED_DIRECTORY_COUNT = 10
  EXPECTED_FILESYSTEM_LOGICAL_BYTES = 74_666
  EXPECTED_TOTAL_LOGICAL_BYTES = 74_718
  MAX_TRAILING_TAR_PADDING_BYTES = 10_240

  # The exact v1.3.0 codeload inventory after removing the commit-specific
  # top-level directory. Sizes are declared tar sizes, not extracted sizes.
  EXPECTED_ENTRIES = {
    "." => [:directory, 0],
    ".editorconfig" => [:file, 373],
    ".gitignore" => [:file, 30],
    ".this-is-the-create-dmg-repo" => [:file, 128],
    "LICENSE" => [:file, 1_120],
    "Makefile" => [:file, 885],
    "README.md" => [:file, 6_675],
    "builder" => [:directory, 0],
    "builder/create-dmg.builder" => [:file, 516],
    "create-dmg" => [:file, 22_377],
    "doc-project" => [:directory, 0],
    "doc-project/Developer Notes.md" => [:file, 1_412],
    "doc-project/Release Checklist.md" => [:file, 325],
    "examples" => [:directory, 0],
    "examples/01-main-example" => [:directory, 0],
    "examples/01-main-example/installer_background.png" => [:file, 35_656],
    "examples/01-main-example/sample" => [:file, 811],
    "examples/01-main-example/source_folder" => [:directory, 0],
    "examples/01-main-example/source_folder/Application.app" => [:file, 0],
    "support" => [:directory, 0],
    "support/eula-resources-template.xml" => [:file, 2_372],
    "support/template.applescript" => [:file, 1_819],
    "tests" => [:directory, 0],
    "tests/007-space-in-dir-name" => [:directory, 0],
    "tests/007-space-in-dir-name/my files" => [:directory, 0],
    "tests/007-space-in-dir-name/my files/hello.txt" => [:file, 12],
    "tests/007-space-in-dir-name/run-test" => [:file, 155]
  }.freeze

  RUNTIME_SIZES = {
    ".this-is-the-create-dmg-repo" => 128,
    "create-dmg" => 22_377,
    "support/eula-resources-template.xml" => 2_372,
    "support/template.applescript" => 1_819
  }.freeze

  METADATA_FIELDS = %i[dev ino uid mode nlink size mtime ctime].freeze

  module_function

  def reject!(message)
    raise ValidationError, message
  end

  def same_metadata?(left, right)
    METADATA_FIELDS.all? { |field| left.public_send(field) == right.public_send(field) }
  end

  def validate_archive_path!(path)
    reject!("archive path must be absolute") unless path.start_with?(File::SEPARATOR)
    reject!("archive path contains a control character") if path.bytes.any? { |byte| byte < 32 || byte == 127 }
  end

  def validate_path!(name, prefix)
    reject!("archive member path is empty") if name.empty?
    reject!("archive member path is not ASCII") unless name.ascii_only?
    reject!("archive member path is absolute: #{name.inspect}") if name.start_with?(File::SEPARATOR)
    reject!("archive member path contains a backslash: #{name.inspect}") if name.include?("\\")
    reject!("archive member path contains a control character") if name.bytes.any? { |byte| byte < 32 || byte == 127 }
    reject!("archive member path is too long") if name.bytesize > MAX_PATH_BYTES

    trimmed = name.end_with?("/") ? name[0...-1] : name
    components = trimmed.split("/", -1)
    reject!("archive member path contains an empty component") if components.any?(&:empty?)
    reject!("archive member path traverses outside its root") if components.any? { |component| component == "." || component == ".." }
    reject!("archive member path component is too long") if components.any? { |component| component.bytesize > MAX_COMPONENT_BYTES }
    reject!("archive member path is too deep") if components.length > MAX_PATH_DEPTH

    expected_root = "create-dmg-#{prefix}"
    unless trimmed == expected_root || trimmed.start_with?("#{expected_root}/")
      reject!("archive member escapes the expected commit root: #{name.inspect}")
    end
    if trimmed == expected_root && name != "#{expected_root}/"
      reject!("archive commit root must be a directory entry")
    end
  end

  def relative_path(name, commit)
    root = "create-dmg-#{commit}"
    return "." if name == "#{root}/"

    relative = name[(root.bytesize + 1)..-1]
    relative.end_with?("/") ? relative[0...-1] : relative
  end

  def read_entry(entry)
    bytes = +""
    while (chunk = entry.read(16_384)) && !chunk.empty?
      bytes << chunk
    end
    bytes
  end

  def hash_entry(entry)
    digest = Digest::SHA256.new
    while (chunk = entry.read(16_384)) && !chunk.empty?
      digest.update(chunk)
    end
    digest.hexdigest
  end

  class Validator
    def initialize(archive:, archive_sha256:, commit:, runtime_hashes:)
      @archive = archive
      @archive_sha256 = archive_sha256
      @commit = commit
      @runtime_hashes = runtime_hashes
    end

    def validate!
      PinnedCreateDMGArchive.validate_archive_path!(@archive)
      @archive = File.expand_path(@archive)
      unless @archive_sha256.match?(/\A[0-9a-f]{64}\z/)
        PinnedCreateDMGArchive.reject!("archive SHA-256 must be lowercase 64hex")
      end
      PinnedCreateDMGArchive.reject!("commit must be one lowercase full SHA") unless @commit.match?(/\A[0-9a-f]{40}\z/)
      unless @runtime_hashes.keys.sort == RUNTIME_SIZES.keys.sort
        PinnedCreateDMGArchive.reject!("runtime hash inventory is incomplete")
      end
      @runtime_hashes.each do |path, digest|
        unless digest.match?(/\A[0-9a-f]{64}\z/)
          PinnedCreateDMGArchive.reject!("runtime SHA-256 is invalid: #{path}")
        end
      end

      path_before = File.lstat(@archive)
      PinnedCreateDMGArchive.reject!("archive must be a regular file") unless path_before.file?
      PinnedCreateDMGArchive.reject!("archive must be owned by the current user") unless path_before.uid == Process.euid
      PinnedCreateDMGArchive.reject!("archive must have exactly one hard link") unless path_before.nlink == 1
      PinnedCreateDMGArchive.reject!("archive must not be group/other writable") unless (path_before.mode & 0o022).zero?
      PinnedCreateDMGArchive.reject!("archive is empty") unless path_before.size.positive?
      PinnedCreateDMGArchive.reject!("compressed archive is too large") if path_before.size > MAX_COMPRESSED_BYTES

      flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
      File.open(@archive, flags) do |archive_io|
        opened_before = archive_io.stat
        unless PinnedCreateDMGArchive.same_metadata?(path_before, opened_before)
          PinnedCreateDMGArchive.reject!("archive identity changed while opening")
        end

        archive_digest = Digest::SHA256.new
        while (chunk = archive_io.read(ARCHIVE_HASH_CHUNK_BYTES))
          archive_digest.update(chunk)
        end
        unless archive_digest.hexdigest == @archive_sha256
          PinnedCreateDMGArchive.reject!("compressed archive SHA-256 mismatch")
        end
        archive_io.rewind

        validate_tar_stream!(archive_io)

        opened_after = archive_io.stat
        path_after = File.lstat(@archive)
        unless PinnedCreateDMGArchive.same_metadata?(opened_before, opened_after) &&
               PinnedCreateDMGArchive.same_metadata?(opened_after, path_after)
          PinnedCreateDMGArchive.reject!("archive identity changed while validating")
        end
      end
    rescue Errno::ELOOP
      PinnedCreateDMGArchive.reject!("archive must not be a symbolic link")
    rescue Errno::ENOENT
      PinnedCreateDMGArchive.reject!("archive does not exist")
    end

    private

    def validate_tar_stream!(archive_io)
      record_count = 0
      filesystem_count = 0
      regular_count = 0
      directory_count = 0
      filesystem_logical_bytes = 0
      total_logical_bytes = 0
      seen_names = {}
      seen_relative = {}
      runtime_seen = {}

      gzip = Zlib::GzipReader.new(archive_io)
      begin
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            record_count += 1
            PinnedCreateDMGArchive.reject!("archive contains too many records") if record_count > EXPECTED_RECORD_COUNT

            header = entry.header
            size = header.size
            PinnedCreateDMGArchive.reject!("archive member has a negative size") if size.negative?
            PinnedCreateDMGArchive.reject!("archive member is too large") if size > MAX_ENTRY_BYTES
            total_logical_bytes += size
            PinnedCreateDMGArchive.reject!("archive logical payload is too large") if total_logical_bytes > MAX_LOGICAL_BYTES

            name = entry.full_name
            if record_count == 1
              validate_global_pax!(entry, name)
              next
            end

            if header.typeflag == "g" || header.typeflag == "x"
              PinnedCreateDMGArchive.reject!("archive contains an unexpected PAX header")
            end
            unless header.typeflag == "0" || header.typeflag == "5"
              PinnedCreateDMGArchive.reject!("archive contains a link or special entry type #{header.typeflag.inspect}")
            end
            PinnedCreateDMGArchive.reject!("archive member has a link target") unless header.linkname.to_s.empty?

            PinnedCreateDMGArchive.validate_path!(name, @commit)
            PinnedCreateDMGArchive.reject!("archive contains a duplicate member: #{name.inspect}") if seen_names.key?(name)
            seen_names[name] = true

            relative = PinnedCreateDMGArchive.relative_path(name, @commit)
            PinnedCreateDMGArchive.reject!("archive contains a duplicate normalized member: #{relative.inspect}") if seen_relative.key?(relative)
            seen_relative[relative] = true

            filesystem_count += 1
            PinnedCreateDMGArchive.reject!("archive contains too many filesystem entries") if filesystem_count > EXPECTED_FILESYSTEM_ENTRY_COUNT
            filesystem_logical_bytes += size

            expected = EXPECTED_ENTRIES[relative]
            PinnedCreateDMGArchive.reject!("archive contains an unexpected member: #{relative.inspect}") unless expected
            expected_type, expected_size = expected
            actual_type = header.typeflag == "5" ? :directory : :file
            PinnedCreateDMGArchive.reject!("archive member type mismatch: #{relative}") unless actual_type == expected_type
            PinnedCreateDMGArchive.reject!("archive directory name must end in '/': #{name.inspect}") if actual_type == :directory && !name.end_with?("/")
            PinnedCreateDMGArchive.reject!("archive file name must not end in '/': #{name.inspect}") if actual_type == :file && name.end_with?("/")
            PinnedCreateDMGArchive.reject!("archive member size mismatch: #{relative}") unless size == expected_size

            if actual_type == :directory
              directory_count += 1
            else
              regular_count += 1
            end

            next unless RUNTIME_SIZES.key?(relative)

            PinnedCreateDMGArchive.reject!("runtime member size mismatch: #{relative}") unless size == RUNTIME_SIZES.fetch(relative)
            actual_digest = PinnedCreateDMGArchive.hash_entry(entry)
            expected_digest = @runtime_hashes.fetch(relative)
            PinnedCreateDMGArchive.reject!("runtime member SHA-256 mismatch: #{relative}") unless actual_digest == expected_digest
            runtime_seen[relative] = true
          end
        end

        trailing_tar_bytes = gzip.read(MAX_TRAILING_TAR_PADDING_BYTES + 1) || ""
        unless trailing_tar_bytes.bytesize <= MAX_TRAILING_TAR_PADDING_BYTES &&
               trailing_tar_bytes.bytes.all?(&:zero?)
          PinnedCreateDMGArchive.reject!("archive has invalid trailing tar padding")
        end
        PinnedCreateDMGArchive.reject!("archive has excessive trailing tar padding") if gzip.read(1)
        unused = gzip.unused
        PinnedCreateDMGArchive.reject!("archive has trailing compressed data") if unused && !unused.empty?
      ensure
        gzip.finish unless gzip.closed?
      end

      PinnedCreateDMGArchive.reject!("archive contains the wrong number of records") unless record_count == EXPECTED_RECORD_COUNT
      unless filesystem_count == EXPECTED_FILESYSTEM_ENTRY_COUNT && seen_relative.keys.sort == EXPECTED_ENTRIES.keys.sort
        PinnedCreateDMGArchive.reject!("archive filesystem inventory is incomplete")
      end
      PinnedCreateDMGArchive.reject!("archive regular-file count mismatch") unless regular_count == EXPECTED_REGULAR_FILE_COUNT
      PinnedCreateDMGArchive.reject!("archive directory count mismatch") unless directory_count == EXPECTED_DIRECTORY_COUNT
      unless filesystem_logical_bytes == EXPECTED_FILESYSTEM_LOGICAL_BYTES &&
             total_logical_bytes == EXPECTED_TOTAL_LOGICAL_BYTES
        PinnedCreateDMGArchive.reject!("archive logical byte count mismatch")
      end
      unless runtime_seen.keys.sort == RUNTIME_SIZES.keys.sort
        PinnedCreateDMGArchive.reject!("archive runtime member inventory is incomplete")
      end
      PinnedCreateDMGArchive.reject!("gzip reader did not consume the complete archive") unless archive_io.pos == archive_io.stat.size
    rescue Zlib::GzipFile::Error, Gem::Package::TarInvalidError, ArgumentError => error
      PinnedCreateDMGArchive.reject!("malformed gzip/tar archive: #{error.message}")
    end

    def validate_global_pax!(entry, name)
      header = entry.header
      PinnedCreateDMGArchive.reject!("first archive record must be the reviewed global PAX header") unless header.typeflag == "g"
      PinnedCreateDMGArchive.reject!("global PAX header has an unexpected name") unless name == "pax_global_header"
      PinnedCreateDMGArchive.reject!("global PAX header must not have a link target") unless header.linkname.to_s.empty?
      expected = "52 comment=#{@commit}\n"
      PinnedCreateDMGArchive.reject!("global PAX header has the wrong size") unless header.size == expected.bytesize
      actual = PinnedCreateDMGArchive.read_entry(entry)
      PinnedCreateDMGArchive.reject!("global PAX header does not bind the reviewed commit") unless actual == expected
    end
  end

  def parse_options(arguments)
    options = { runtime_hashes: {} }
    parser = OptionParser.new do |config|
      config.banner = "Usage: validate-pinned-create-dmg-archive.rb --archive PATH --archive-sha256 SHA --commit SHA [runtime SHA options]"
      config.on("--archive PATH") { |value| options[:archive] = value }
      config.on("--archive-sha256 SHA") { |value| options[:archive_sha256] = value }
      config.on("--commit SHA") { |value| options[:commit] = value }
      config.on("--script-sha256 SHA") { |value| options[:runtime_hashes]["create-dmg"] = value }
      config.on("--sentinel-sha256 SHA") { |value| options[:runtime_hashes][".this-is-the-create-dmg-repo"] = value }
      config.on("--template-sha256 SHA") { |value| options[:runtime_hashes]["support/template.applescript"] = value }
      config.on("--eula-template-sha256 SHA") { |value| options[:runtime_hashes]["support/eula-resources-template.xml"] = value }
    end
    parser.parse!(arguments)
    reject!("unexpected positional arguments") unless arguments.empty?
    reject!("--archive is required") unless options[:archive]
    reject!("--archive-sha256 is required") unless options[:archive_sha256]
    reject!("--commit is required") unless options[:commit]
    options
  rescue OptionParser::ParseError => error
    reject!(error.message)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = PinnedCreateDMGArchive.parse_options(ARGV)
    PinnedCreateDMGArchive::Validator.new(**options).validate!
    puts "Pinned create-dmg archive: PASS"
  rescue PinnedCreateDMGArchive::ValidationError => error
    warn "validate-pinned-create-dmg-archive: #{error.message}"
    exit 1
  rescue StandardError => error
    warn "validate-pinned-create-dmg-archive: unexpected #{error.class}: #{error.message}"
    exit 1
  end
end
