#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "optparse"

# This module deliberately returns the verified bytes, rather than only a
# Boolean result. A caller that needs to execute the tool can therefore carry
# the exact descriptor-read closure forward without reopening any tool path.
module PinnedCreateDMGTool
  class ValidationError < StandardError; end

  EXPECTED_MANIFEST = <<~MANIFEST.b.freeze
    fb2494eb10146a84bbb20ebb198c2a09fb72aed119706dc55b6ec3644018383f  .this-is-the-create-dmg-repo
    bb9ea3194e55f2f76a821e87541513748d0fedc69f45cf4f0951cad15ae0cae5  create-dmg
    a804e533e9c99491a74cb4502c435b00d902dc7a45d3693057a29674e584a70b  support/eula-resources-template.xml
    b5dd7c55ddaa5db1884ac5cf523c4413d452a75df967daf55b8d45ba501fe457  support/template.applescript
  MANIFEST
  EXPECTED_MANIFEST_SHA256 = "35565e6e5d1086014d94fdddd246b8daa4b33bf3d6b9b49a1a9dac2d3a57526f"
  EXPECTED_FILES = {
    ".this-is-the-create-dmg-repo" => {
      mode: 0o400,
      size: 128,
      sha256: "fb2494eb10146a84bbb20ebb198c2a09fb72aed119706dc55b6ec3644018383f"
    },
    "create-dmg" => {
      mode: 0o500,
      size: 22_377,
      sha256: "bb9ea3194e55f2f76a821e87541513748d0fedc69f45cf4f0951cad15ae0cae5"
    },
    "support/eula-resources-template.xml" => {
      mode: 0o400,
      size: 2_372,
      sha256: "a804e533e9c99491a74cb4502c435b00d902dc7a45d3693057a29674e584a70b"
    },
    "support/template.applescript" => {
      mode: 0o400,
      size: 1_819,
      sha256: "b5dd7c55ddaa5db1884ac5cf523c4413d452a75df967daf55b8d45ba501fe457"
    }
  }.freeze
  STAT_FIELDS = %i[dev ino uid mode nlink size mtime ctime].freeze

  module_function

  def fail_closed(reason)
    raise ValidationError, reason
  end

  def stable_signature(stat)
    STAT_FIELDS.map do |field|
      value = stat.public_send(field)
      value.is_a?(Time) ? value.to_r : value
    end
  end

  def valid_absolute_path?(path)
    path.is_a?(String) &&
      path.start_with?("/") &&
      path == File.expand_path(path) &&
      !path.match?(/[\0\r\n\t]/)
  end

  def open_no_follow(path)
    File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK)
  rescue SystemCallError
    fail_closed("unsafe or unavailable input")
  end

  def verify_path_still_names_descriptor(path, descriptor_stat)
    path_stat = File.lstat(path)
    unless path_stat.dev == descriptor_stat.dev &&
           path_stat.ino == descriptor_stat.ino &&
           path_stat.ftype == descriptor_stat.ftype
      fail_closed("input identity changed during verification")
    end
  rescue SystemCallError
    fail_closed("input identity became unavailable")
  end

  def with_verified_directory(path, expected_mode, expected_entries)
    descriptor = open_no_follow(path)
    before = descriptor.stat
    fail_closed("expected directory") unless before.directory?
    fail_closed("directory owner mismatch") unless before.uid == Process.uid
    fail_closed("directory mode mismatch") unless (before.mode & 0o7777) == expected_mode

    actual_entries = Dir.children(path).sort
    fail_closed("directory closure mismatch") unless actual_entries == expected_entries.sort
    result = yield

    after = descriptor.stat
    fail_closed("directory changed during verification") unless stable_signature(before) == stable_signature(after)
    verify_path_still_names_descriptor(path, after)
    result
  ensure
    descriptor&.close
  end

  def read_verified_file(path, expected_mode:, expected_size:, expected_sha256:)
    descriptor = open_no_follow(path)
    before = descriptor.stat
    fail_closed("expected regular file") unless before.file?
    fail_closed("file owner mismatch") unless before.uid == Process.uid
    fail_closed("file hard-link count mismatch") unless before.nlink == 1
    fail_closed("file mode mismatch") unless (before.mode & 0o7777) == expected_mode
    fail_closed("file size mismatch") unless before.size == expected_size

    bytes = +"".b
    while (chunk = descriptor.read(16_384))
      bytes << chunk
      fail_closed("file exceeded its reviewed size") if bytes.bytesize > expected_size
    end
    fail_closed("file size changed while reading") unless bytes.bytesize == expected_size
    fail_closed("file digest mismatch") unless Digest::SHA256.hexdigest(bytes) == expected_sha256

    after = descriptor.stat
    fail_closed("file changed during verification") unless stable_signature(before) == stable_signature(after)
    verify_path_still_names_descriptor(path, after)
    bytes.freeze
  ensure
    descriptor&.close
  end

  def verify(root:, manifest:)
    fail_closed("root path is invalid") unless valid_absolute_path?(root)
    fail_closed("manifest path is invalid") unless valid_absolute_path?(manifest)

    begin
      fail_closed("root path is not physical") unless File.realpath(root) == root
      fail_closed("manifest path is not physical") unless File.realpath(manifest) == manifest
    rescue SystemCallError
      fail_closed("tool closure is unavailable")
    end

    parent = File.dirname(root)
    fail_closed("unexpected tool-root name") unless File.basename(root) == "tool"
    fail_closed("manifest must be adjacent to the tool root") unless manifest == File.join(parent, "runtime.SHA256")

    verified_files = {}
    with_verified_directory(parent, 0o700, ["runtime.SHA256", "tool"]) do
      manifest_bytes = read_verified_file(
        manifest,
        expected_mode: 0o400,
        expected_size: EXPECTED_MANIFEST.bytesize,
        expected_sha256: EXPECTED_MANIFEST_SHA256
      )
      fail_closed("runtime manifest content mismatch") unless manifest_bytes == EXPECTED_MANIFEST

      with_verified_directory(root, 0o500, [".this-is-the-create-dmg-repo", "create-dmg", "support"]) do
        support = File.join(root, "support")
        with_verified_directory(
          support,
          0o500,
          ["eula-resources-template.xml", "template.applescript"]
        ) do
          EXPECTED_FILES.each do |relative_path, expected|
            verified_files[relative_path] = read_verified_file(
              File.join(root, relative_path),
              expected_mode: expected.fetch(:mode),
              expected_size: expected.fetch(:size),
              expected_sha256: expected.fetch(:sha256)
            )
          end
        end
      end
    end
    verified_files.freeze
  end

  def cli(argv)
    options = {}
    parser = OptionParser.new do |config|
      config.on("--root PATH") { |value| options[:root] = value }
      config.on("--manifest PATH") { |value| options[:manifest] = value }
    end
    parser.parse!(argv)
    fail_closed("unexpected trailing arguments") unless argv.empty?
    verify(root: options[:root], manifest: options[:manifest])
    0
  rescue OptionParser::ParseError, ValidationError => error
    warn "verify-pinned-create-dmg-tool: #{error.message}"
    1
  end
end

exit PinnedCreateDMGTool.cli(ARGV) if $PROGRAM_NAME == __FILE__
