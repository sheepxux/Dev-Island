#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "tmpdir"

ROOT = File.expand_path("../..", __dir__)
MAXIMUM_INPUT_BYTES = 20 * 1024 * 1024
SCREENSHOTS = [
  ["02-welcome-step.png", "Welcome"],
  ["20-priority-panel.png", "Priority panel"],
  ["31-session-history.png", "Session History"],
  ["61-agent-brand-badges.png", "All Agent badges"],
].freeze

def fail!(message, status = 1)
  warn "error: #{message}"
  exit status
end

def usage!
  warn <<~TEXT
    Usage: generate-trademark-review-packet.rb \
      --screenshots-dir DIR --output-dir DIR
  TEXT
  exit 64
end

def regular_directory!(path, label)
  stat = File.lstat(path)
  fail!("#{label} must be a regular non-symlink directory: #{path}") unless stat.directory? && !stat.symlink?
rescue Errno::ENOENT
  fail!("#{label} is missing: #{path}")
end

def regular_file!(path, label, maximum_bytes: MAXIMUM_INPUT_BYTES)
  stat = File.lstat(path)
  unless stat.file? && !stat.symlink?
    fail!("#{label} must be a regular non-symlink file: #{path}")
  end
  unless stat.size.between?(1, maximum_bytes)
    fail!("#{label} is empty or exceeds the size limit: #{path}")
  end
rescue Errno::ENOENT
  fail!("#{label} is missing: #{path}")
end

def read_regular_file(path, label, maximum_bytes: MAXIMUM_INPUT_BYTES)
  regular_file!(path, label, maximum_bytes: maximum_bytes)
  File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
    file.binmode
    before = file.stat
    unless before.file? && before.size.between?(1, maximum_bytes)
      fail!("#{label} changed before it was read: #{path}")
    end
    bytes = file.read(maximum_bytes + 1)
    after = file.stat
    unless bytes.bytesize == before.size && after.size == before.size &&
           after.ino == before.ino && after.dev == before.dev
      fail!("#{label} changed while it was being read: #{path}")
    end
    bytes
  end
rescue Errno::ELOOP
  fail!("#{label} must be a regular non-symlink file: #{path}")
end

def write_file(path, bytes)
  File.binwrite(path, bytes)
  File.chmod(0o644, path)
end

def copy_regular_file(source, destination, label)
  write_file(destination, read_regular_file(source, label))
end

options = {}
arguments = ARGV.dup
until arguments.empty?
  key = arguments.shift
  usage! unless %w[--screenshots-dir --output-dir].include?(key)
  usage! if options.key?(key) || arguments.empty?
  options[key] = arguments.shift
end
usage! unless options.keys.sort == %w[--output-dir --screenshots-dir]

screenshots_dir = File.expand_path(options.fetch("--screenshots-dir"))
output_dir = File.expand_path(options.fetch("--output-dir"))
output_parent = File.dirname(output_dir)
output_basename = File.basename(output_dir)

regular_directory!(screenshots_dir, "screenshots directory")
regular_directory!(output_parent, "output parent")
fail!("output directory name is invalid") if [".", "..", "/"].include?(output_basename)

begin
  File.lstat(output_dir)
  fail!("output directory already exists; refusing to overwrite: #{output_dir}")
rescue Errno::ENOENT
  # Expected. The packet is committed atomically only after every check passes.
end

manifest_path = File.join(ROOT, "scripts/assets/agent-logos/manifest.json")
reviews_path = File.join(ROOT, "scripts/assets/agent-logos/trademark-reviews.json")
source_dir = File.join(ROOT, "scripts/assets/agent-logos")
bundle_dir = File.join(ROOT, "IslandApp/Resources")
licenses_dir = File.join(ROOT, "scripts/licenses")
verifier = File.join(ROOT, "scripts/release/verify-brand-assets.rb")
version_path = File.join(ROOT, "VERSION")

[manifest_path, reviews_path, verifier, version_path].each do |path|
  regular_file!(path, "repository input", maximum_bytes: 1_048_576)
end
[source_dir, bundle_dir, licenses_dir].each do |path|
  regular_directory!(path, "repository input directory")
end

verified = system(
  verifier,
  "--manifest", manifest_path,
  "--trademark-reviews", reviews_path,
  "--source-dir", source_dir,
  "--bundle-dir", bundle_dir,
  "--licenses-dir", licenses_dir,
)
fail!("repository brand asset inventory failed") unless verified

begin
  manifest_bytes = read_regular_file(manifest_path, "brand manifest", maximum_bytes: 1_048_576)
  reviews_bytes = read_regular_file(reviews_path, "trademark reviews", maximum_bytes: 1_048_576)
  manifest = JSON.parse(manifest_bytes)
  review_document = JSON.parse(reviews_bytes)
rescue JSON::ParserError
  fail!("validated brand records could not be parsed")
end

assets = manifest.fetch("assets")
reviews = review_document.fetch("reviews")
usage = review_document.fetch("usage")
reviews_by_id = reviews.to_h { |review| [review.fetch("id"), review] }
version_bytes = read_regular_file(version_path, "product version", maximum_bytes: 64)
version_match = version_bytes.match(/\A((?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]?)\.(?:0|[1-9][0-9]?))\n\z/)
fail!("product version must be one canonical numeric line") unless version_match
version = version_match[1]
fail!("product version is invalid") unless version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?\z/)

screenshot_bytes = {}
SCREENSHOTS.each do |filename, _label|
  path = File.join(screenshots_dir, filename)
  bytes = read_regular_file(path, "review screenshot")
  fail!("review screenshot is not a PNG: #{filename}") unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)
  screenshot_bytes[filename] = bytes
end

temporary_dir = Dir.mktmpdir(".#{output_basename}.", output_parent)
begin
  %w[assets/source assets/rendered notices records screenshots].each do |relative|
    path = File.join(temporary_dir, relative)
    FileUtils.mkdir_p(path, mode: 0o755)
  end

  assets.each do |asset|
    source_name = asset.fetch("sourceFile")
    copy_regular_file(
      File.join(source_dir, source_name),
      File.join(temporary_dir, "assets/source", source_name),
      "brand source",
    )
    asset.fetch("bundleFiles").each do |bundle|
      name = bundle.fetch("name")
      copy_regular_file(
        File.join(bundle_dir, name),
        File.join(temporary_dir, "assets/rendered", name),
        "rendered brand asset",
      )
    end
  end

  assets.map { |asset| asset.fetch("bundledNotice") }.uniq.sort.each do |notice|
    fail!("brand notice remains unasserted: #{notice}") if notice == "NOASSERTION"
    copy_regular_file(
      File.join(licenses_dir, notice),
      File.join(temporary_dir, "notices", notice),
      "brand notice",
    )
  end

  write_file(File.join(temporary_dir, "records/manifest.json"), manifest_bytes)
  write_file(File.join(temporary_dir, "records/trademark-reviews.json"), reviews_bytes)
  screenshot_bytes.each do |filename, bytes|
    write_file(File.join(temporary_dir, "screenshots", filename), bytes)
  end

  copied_inventory_verified = system(
    verifier,
    "--manifest", File.join(temporary_dir, "records/manifest.json"),
    "--trademark-reviews", File.join(temporary_dir, "records/trademark-reviews.json"),
    "--source-dir", File.join(temporary_dir, "assets/source"),
    "--bundle-dir", File.join(temporary_dir, "assets/rendered"),
    "--licenses-dir", File.join(temporary_dir, "notices"),
  )
  fail!("copied packet brand asset inventory failed") unless copied_inventory_verified

  packet_manifest = {
    "schemaVersion" => 1,
    "product" => { "name" => "Dev Island", "version" => version },
    "status" => "review-input-not-approval",
    "presentation" => usage,
    "records" => {
      "manifestSHA256" => Digest::SHA256.hexdigest(manifest_bytes),
      "trademarkReviewsSHA256" => Digest::SHA256.hexdigest(reviews_bytes),
    },
    "screenshots" => SCREENSHOTS.map do |filename, label|
      {
        "name" => filename,
        "surface" => label,
        "sha256" => Digest::SHA256.hexdigest(screenshot_bytes.fetch(filename)),
      }
    end,
    "assets" => assets.map do |asset|
      review = reviews_by_id.fetch(asset.fetch("id"))
      {
        "id" => asset.fetch("id"),
        "displayName" => asset.fetch("displayName"),
        "assetFingerprintSHA256" => review.fetch("assetFingerprintSHA256"),
        "decision" => review.fetch("decision"),
      }
    end,
  }
  packet_manifest_bytes = JSON.pretty_generate(packet_manifest) + "\n"
  write_file(File.join(temporary_dir, "PACKET-MANIFEST.json"), packet_manifest_bytes)

  screenshot_rows = packet_manifest.fetch("screenshots").map do |item|
    "| #{item.fetch("surface")} | `#{item.fetch("name")}` | `#{item.fetch("sha256")}` |"
  end.join("\n")
  pending_count = reviews.count { |review| review.fetch("decision") != "approved" }
  notices_count = assets.map { |asset| asset.fetch("bundledNotice") }.uniq.length
  readme = <<~MARKDOWN
    # Dev Island Trademark Review Packet

    Product version: `#{version}`

    Status: review input only. This packet is not trademark approval. It contains
    #{assets.length} Agent marks and currently has #{pending_count} non-approved decisions.

    ## Presentation being reviewed

    - Purpose: identify the Agent selected by the user.
    - Affiliation statement: no affiliation or endorsement is claimed.
    - Surfaces: island panel, onboarding, session history, and settings.
    - Treatment: monochrome template artwork on a neutral badge.
    - Requested commercial scope: `WORLDWIDE` through `direct-download`,
      `github-release`, and `homebrew`.

    ## Contents

    - `assets/source/`: #{assets.length} exact SVG inputs.
    - `assets/rendered/`: #{assets.sum { |asset| asset.fetch("bundleFiles").length }} exact bundled PNGs.
    - `notices/`: #{notices_count} exact asset-license/notice files.
    - `records/`: the exact repository manifest and trademark decision record.
    - `screenshots/`: the four declared product surfaces.
    - `PACKET-MANIFEST.json`: deterministic record and screenshot hashes.
    - `TRADEMARK_REVIEW_FORM.md`: owner/legal decision worksheet.
    - `SHA256SUMS`: integrity inventory for every other packet file.

    ## Screenshot evidence

    | Surface | File | SHA-256 |
    | --- | --- | --- |
    #{screenshot_rows}

    Asset copyright/license evidence and trademark permission are separate. The
    included notices do not by themselves approve trademark use. Engineering must
    not switch a manifest flag without a complete matching human decision record.
  MARKDOWN
  write_file(File.join(temporary_dir, "README.md"), readme)

  asset_rows = assets.map do |asset|
    review = reviews_by_id.fetch(asset.fetch("id"))
    "| #{asset.fetch("displayName")} | `#{asset.fetch("id")}` | `#{review.fetch("assetFingerprintSHA256")}` | #{review.fetch("decision")} |"
  end.join("\n")
  form = <<~MARKDOWN
    # Dev Island Per-Mark Trademark Review Form

    This form is for the product owner or qualified counsel. It is not legal advice.
    Review the exact files and hashes in this packet. A fingerprint change requires
    a new decision.

    ## Common presentation contract

    - Use: identifying a user-selected third-party Agent.
    - Claim: no affiliation with or endorsement by the Agent vendor.
    - Locations: island panel, onboarding, session history, settings.
    - Visual treatment: monochrome template artwork on a neutral badge.
    - Requested territory: `WORLDWIDE`.
    - Requested channels: `direct-download`, `github-release`, `homebrew`.

    ## Per-mark decisions

    | Mark | Record ID | Asset fingerprint SHA-256 | Current decision |
    | --- | --- | --- | --- |
    #{asset_rows}

    For every record ID, state approve / reject / keep under review, sales regions,
    channels, conditions, expiry (if any), and the authority basis.

    ## Reviewer attestation

    - Reviewed by:
    - Reviewer role:
    - Authority reference:
    - Reviewed at (UTC):
    - Decision artifact filename:
    - Decision artifact SHA-256:
    - Conditions/notes:

    I confirm that each decision applies only to the exact fingerprint and
    presentation contract stated in this packet. Asset copyright/license provenance
    and trademark approval are separate decisions.

    Signature / authoritative confirmation:

    Date:
  MARKDOWN
  write_file(File.join(temporary_dir, "TRADEMARK_REVIEW_FORM.md"), form)

  relative_files = Dir.chdir(temporary_dir) do
    Dir.glob("**/*", File::FNM_DOTMATCH).select do |relative|
      next false if [".", "..", "SHA256SUMS"].include?(relative)
      stat = File.lstat(relative)
      fail!("generated packet contains a symbolic link: #{relative}") if stat.symlink?
      stat.file?
    end.sort
  end
  checksum_lines = relative_files.map do |relative|
    digest = Digest::SHA256.file(File.join(temporary_dir, relative)).hexdigest
    "#{digest}  #{relative}"
  end
  write_file(File.join(temporary_dir, "SHA256SUMS"), checksum_lines.join("\n") + "\n")

  checksum_lines.each do |line|
    expected, relative = line.split("  ", 2)
    actual = Digest::SHA256.file(File.join(temporary_dir, relative)).hexdigest
    fail!("generated packet checksum did not verify: #{relative}") unless actual == expected
  end

  File.chmod(0o755, temporary_dir)
  begin
    File.lstat(output_dir)
    fail!("output directory appeared during generation; refusing to overwrite: #{output_dir}")
  rescue Errno::ENOENT
    # Expected immediately before the atomic same-parent rename.
  end
  File.rename(temporary_dir, output_dir)
  temporary_dir = nil
rescue SystemCallError => error
  fail!("could not generate review packet: #{error.class}")
ensure
  FileUtils.remove_entry(temporary_dir) if temporary_dir && File.exist?(temporary_dir)
end

puts "Trademark review packet: #{output_dir}"
