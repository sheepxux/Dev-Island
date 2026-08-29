#!/usr/bin/env ruby

require "digest"
require "json"
require "time"
require "uri"

def fail!(message)
  warn "error: #{message}"
  exit 1
end

def usage!
  warn <<~TEXT
    Usage: verify-brand-assets.rb --manifest FILE --source-dir DIR \
      --bundle-dir DIR --licenses-dir DIR --trademark-reviews FILE \
      [--require-release-reviewed]
  TEXT
  exit 64
end

options = {}
require_release_reviewed = false
arguments = ARGV.dup
until arguments.empty?
  key = arguments.shift
  if key == "--require-release-reviewed"
    usage! if require_release_reviewed
    require_release_reviewed = true
    next
  end
  usage! unless %w[--manifest --source-dir --bundle-dir --licenses-dir --trademark-reviews].include?(key)
  usage! if options.key?(key) || arguments.empty?
  options[key] = arguments.shift
end
usage! unless options.keys.sort == %w[--bundle-dir --licenses-dir --manifest --source-dir --trademark-reviews]

def regular_file!(path, maximum_bytes:)
  stat = File.lstat(path)
  fail!("input must be a regular non-symlink file: #{path}") unless stat.file? && !stat.symlink?
  fail!("input is empty or exceeds the size limit: #{path}") unless stat.size.between?(1, maximum_bytes)
rescue Errno::ENOENT
  fail!("required input is missing: #{path}")
end

def regular_directory!(path)
  stat = File.lstat(path)
  fail!("input must be a regular non-symlink directory: #{path}") unless stat.directory? && !stat.symlink?
rescue Errno::ENOENT
  fail!("required directory is missing: #{path}")
end

manifest_path = File.expand_path(options.fetch("--manifest"))
trademark_reviews_path = File.expand_path(options.fetch("--trademark-reviews"))
source_dir = File.expand_path(options.fetch("--source-dir"))
bundle_dir = File.expand_path(options.fetch("--bundle-dir"))
licenses_dir = File.expand_path(options.fetch("--licenses-dir"))
regular_file!(manifest_path, maximum_bytes: 1_048_576)
regular_file!(trademark_reviews_path, maximum_bytes: 1_048_576)
[source_dir, bundle_dir, licenses_dir].each { |directory| regular_directory!(directory) }

begin
  manifest = JSON.parse(File.binread(manifest_path))
rescue JSON::ParserError
  fail!("brand asset manifest is not valid JSON")
end
fail!("brand asset manifest root is invalid") unless manifest.is_a?(Hash) && manifest.keys.sort == %w[assets schemaVersion]
fail!("brand asset manifest schema is unsupported") unless manifest["schemaVersion"] == 3
assets = manifest["assets"]
fail!("brand asset manifest must contain 1...64 entries") unless assets.is_a?(Array) && assets.length.between?(1, 64)
fail!("brand asset manifest entries must be objects") unless assets.all? { |asset| asset.is_a?(Hash) }

begin
  trademark_document = JSON.parse(File.binread(trademark_reviews_path))
rescue JSON::ParserError
  fail!("trademark review record is not valid JSON")
end
expected_trademark_root_keys = %w[reviews schemaVersion usage]
fail!("trademark review record root is invalid") unless trademark_document.is_a?(Hash) && trademark_document.keys.sort == expected_trademark_root_keys
fail!("trademark review schema is unsupported") unless trademark_document["schemaVersion"] == 1
usage = trademark_document["usage"]
expected_usage = {
  "purpose" => "identify-user-selected-agent",
  "affiliation" => "no-affiliation-or-endorsement",
  "surfaces" => %w[island-panel onboarding session-history settings],
  "treatment" => "monochrome-template-on-neutral-badge",
}
fail!("trademark presentation contract is invalid") unless usage == expected_usage
reviews = trademark_document["reviews"]
fail!("trademark review record count is invalid") unless reviews.is_a?(Array) && reviews.length.between?(1, 64)
fail!("trademark review entries must be objects") unless reviews.all? { |review| review.is_a?(Hash) }

expected_review_keys = %w[
  assetFingerprintSHA256 authorityReference conditions decision distributionChannels
  evidenceReference expiresAt id reviewedAt reviewedBy reviewerRole salesRegions
].sort
reviews.each do |review|
  fail!("trademark review entry has unknown or missing fields") unless review.keys.sort == expected_review_keys
end

expected_asset_keys = %w[
  assetLicense bundleFiles bundledNotice bundledNoticeSHA256 displayName id provenanceReview
  sourceFile sourceSHA256 trademarkReview upstream
].sort
expected_upstream_keys = %w[path repository revision sha256 transform version]
expected_bundle_keys = %w[name sha256]
sha_pattern = /\A[0-9a-f]{64}\z/
id_pattern = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
safe_path_pattern = /\A(?!\/)(?!.*(?:\A|\/)\.\.?\/)[A-Za-z0-9._@+\/-]+\z/
safe_notice_pattern = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/

def trademark_asset_fingerprint(asset, usage)
  components = [
    usage.fetch("purpose"),
    usage.fetch("affiliation"),
    usage.fetch("treatment"),
    *usage.fetch("surfaces"),
    asset.fetch("id"),
    asset.fetch("sourceSHA256"),
  ]
  asset.fetch("bundleFiles").each do |item|
    components.concat([item.fetch("name"), item.fetch("sha256")])
  end
  upstream = asset.fetch("upstream")
  components.concat(
    %w[repository revision path sha256 transform version].map { |key| upstream.fetch(key) }
  )
  components.concat(
    [
      asset.fetch("assetLicense"),
      asset.fetch("bundledNotice"),
      asset.fetch("bundledNoticeSHA256"),
    ]
  )

  bytes = "DevIsland.TrademarkReview\0v1\0"
  components.each { |component| bytes << component << "\0" }
  Digest::SHA256.hexdigest(bytes)
end

def valid_review_text?(value, maximum_bytes:)
  value.is_a?(String) && value.bytesize.between?(1, maximum_bytes) &&
    !value.match?(/[\x00-\x1f\x7f]/)
end

def parse_utc_time(value, label)
  fail!("#{label} is invalid") unless value.is_a?(String) && value.end_with?("Z")
  parsed = Time.iso8601(value)
  fail!("#{label} must be UTC") unless parsed.utc_offset.zero?
  parsed
rescue ArgumentError
  fail!("#{label} is invalid")
end

ids = assets.map { |asset| asset["id"] }
fail!("brand asset IDs must be unique and sorted") unless ids == ids.sort && ids.uniq.length == ids.length
review_ids = reviews.map { |review| review["id"] }
fail!("trademark review IDs must exactly match sorted brand assets") unless review_ids == ids
reviews_by_id = reviews.to_h { |review| [review.fetch("id"), review] }
expected_sources = []
expected_bundles = []
release_blockers = []

assets.each do |asset|
  fail!("brand asset entry has unknown or missing fields") unless asset.keys.sort == expected_asset_keys
  id = asset["id"]
  fail!("brand asset ID is invalid") unless id.is_a?(String) && id.match?(id_pattern)
  fail!("brand asset display name is invalid: #{id}") unless asset["displayName"].is_a?(String) && asset["displayName"].match?(/\A[^\x00-\x1f]{1,80}\z/)

  source_file = asset["sourceFile"]
  expected_source = "#{id}.svg"
  fail!("brand source filename must be canonical: #{id}") unless source_file == expected_source
  fail!("brand source hash is invalid: #{id}") unless asset["sourceSHA256"].is_a?(String) && asset["sourceSHA256"].match?(sha_pattern)
  expected_sources << source_file
  source_path = File.join(source_dir, source_file)
  regular_file!(source_path, maximum_bytes: 1_048_576)
  source_bytes = File.binread(source_path)
  fail!("brand source SHA-256 mismatch: #{id}") unless Digest::SHA256.hexdigest(source_bytes) == asset["sourceSHA256"]

  bundle_files = asset["bundleFiles"]
  canonical_bundles = ["AgentLogo-#{id}.png", "AgentLogo-#{id}@2x.png"]
  fail!("brand bundle inventory must contain canonical 1x and 2x PNGs: #{id}") unless bundle_files.is_a?(Array) && bundle_files.map { |item| item["name"] } == canonical_bundles
  bundle_files.each do |item|
    fail!("brand bundle entry has unknown or missing fields: #{id}") unless item.is_a?(Hash) && item.keys.sort == expected_bundle_keys
    fail!("brand bundle hash is invalid: #{item["name"]}") unless item["sha256"].is_a?(String) && item["sha256"].match?(sha_pattern)
    expected_bundles << item["name"]
    bundle_path = File.join(bundle_dir, item["name"])
    regular_file!(bundle_path, maximum_bytes: 1_048_576)
    fail!("brand bundle SHA-256 mismatch: #{item["name"]}") unless Digest::SHA256.file(bundle_path).hexdigest == item["sha256"]
  end

  upstream = asset["upstream"]
  fail!("brand upstream entry has unknown or missing fields: #{id}") unless upstream.is_a?(Hash) && upstream.keys.sort == expected_upstream_keys
  repository = upstream["repository"]
  revision = upstream["revision"]
  path = upstream["path"]
  version = upstream["version"]
  upstream_sha256 = upstream["sha256"]
  transform = upstream["transform"]
  upstream_identity = [repository, revision, path, upstream_sha256, transform]
  asserted_upstream = upstream_identity.none? { |value| value == "NOASSERTION" }
  unasserted_upstream = upstream_identity.all? { |value| value == "NOASSERTION" }
  fail!("brand upstream must be fully asserted or fully NOASSERTION: #{id}") unless asserted_upstream || unasserted_upstream
  if asserted_upstream
    begin
      uri = URI.parse(repository)
    rescue URI::InvalidURIError
      fail!("brand upstream repository is invalid: #{id}")
    end
    fail!("brand upstream repository must be credential-free GitHub HTTPS: #{id}") unless uri.scheme == "https" && uri.host&.downcase == "github.com" && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    fail!("brand upstream revision is invalid: #{id}") unless revision.is_a?(String) && revision.match?(/\A[0-9a-f]{40}\z/)
    fail!("brand upstream path is invalid: #{id}") unless path.is_a?(String) && path.match?(safe_path_pattern)
    fail!("brand upstream SHA-256 is invalid: #{id}") unless upstream_sha256.is_a?(String) && upstream_sha256.match?(sha_pattern)

    upstream_bytes = case transform
    when "identity"
      source_bytes
    when "append-trailing-lf"
      fail!("brand append-trailing-lf transform is invalid: #{id}") unless source_bytes.end_with?("\n")
      source_bytes.byteslice(0, source_bytes.bytesize - 1)
    when "octicons-template-v1"
      fail!("brand transform is not valid for this asset: #{id}") unless id == "copilot-cli"
      local_prefix = '<svg fill="currentColor" height="1em" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>GitHub Copilot CLI</title>'
      upstream_prefix = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
      fail!("brand octicons-template-v1 transform is invalid: #{id}") unless source_bytes.start_with?(local_prefix) && source_bytes.end_with?("\n")
      upstream_prefix + source_bytes.byteslice(local_prefix.bytesize, source_bytes.bytesize - local_prefix.bytesize - 1)
    when "qwen-template-v1"
      fail!("brand transform is not valid for this asset: #{id}") unless id == "qwen-code"
      marker = 'fill="currentColor"'
      fail!("brand qwen-template-v1 transform is invalid: #{id}") unless source_bytes.scan(marker).length == 1
      source_bytes.sub(marker, 'fill="#6D44E8"')
    else
      fail!("brand upstream transform is invalid: #{id}")
    end
    fail!("brand upstream SHA-256 mismatch after transform: #{id}") unless Digest::SHA256.hexdigest(upstream_bytes) == upstream_sha256
  end
  fail!("brand upstream version is invalid: #{id}") unless version == "NOASSERTION" || (version.is_a?(String) && version.match?(/\A[0-9A-Za-z][0-9A-Za-z.+-]{0,63}\z/))

  license = asset["assetLicense"]
  fail!("brand asset license is invalid: #{id}") unless license == "NOASSERTION" || (license.is_a?(String) && license.match?(/\A[A-Za-z0-9.+-]{1,64}\z/))
  notice = asset["bundledNotice"]
  notice_sha256 = asset["bundledNoticeSHA256"]
  fail!("brand notice is invalid: #{id}") unless notice == "NOASSERTION" || (notice.is_a?(String) && notice.match?(safe_notice_pattern))
  fail!("brand notice SHA-256 is invalid: #{id}") unless notice_sha256 == "NOASSERTION" || (notice_sha256.is_a?(String) && notice_sha256.match?(sha_pattern))
  fail!("brand license and notice assertion state must match: #{id}") unless (license == "NOASSERTION") == (notice == "NOASSERTION" && notice_sha256 == "NOASSERTION")
  if notice != "NOASSERTION"
    notice_path = File.join(licenses_dir, notice)
    regular_file!(notice_path, maximum_bytes: 1_048_576)
    fail!("brand notice SHA-256 mismatch: #{id}") unless Digest::SHA256.file(notice_path).hexdigest == notice_sha256
  end
  fail!("reviewed brand provenance requires asserted upstream: #{id}") if asset["provenanceReview"] == "reviewed" && !asserted_upstream
  fail!("brand provenance review state is invalid: #{id}") unless %w[required reviewed].include?(asset["provenanceReview"])
  fail!("brand trademark review state is invalid: #{id}") unless %w[approved required].include?(asset["trademarkReview"])

  review = reviews_by_id.fetch(id)
  expected_fingerprint = trademark_asset_fingerprint(asset, usage)
  unless review["assetFingerprintSHA256"].is_a?(String) &&
         review["assetFingerprintSHA256"].match?(sha_pattern) &&
         review["assetFingerprintSHA256"] == expected_fingerprint
    fail!("trademark review asset fingerprint mismatch: #{id}")
  end

  decision = review["decision"]
  fail!("trademark review decision is invalid: #{id}") unless %w[approved rejected required].include?(decision)
  expected_manifest_state = decision == "approved" ? "approved" : "required"
  unless asset["trademarkReview"] == expected_manifest_state
    fail!("brand manifest and trademark review decision disagree: #{id}")
  end

  review_fields = %w[
    reviewedAt reviewedBy reviewerRole authorityReference evidenceReference
    conditions expiresAt
  ]
  channels = review["distributionChannels"]
  regions = review["salesRegions"]
  fail!("trademark review channels are invalid: #{id}") unless channels.is_a?(Array)
  fail!("trademark review regions are invalid: #{id}") unless regions.is_a?(Array)

  expected_channels = %w[direct-download github-release homebrew]
  unless channels.length <= expected_channels.length &&
         channels.all? { |channel| expected_channels.include?(channel) } &&
         channels == channels.sort && channels.uniq.length == channels.length
    fail!("trademark review channels are invalid: #{id}")
  end
  unless regions.length <= 64 &&
         regions.all? { |region| region.is_a?(String) && (region == "WORLDWIDE" || region.match?(/\A[A-Z]{2}\z/)) } &&
         regions == regions.sort && regions.uniq.length == regions.length &&
         (!regions.include?("WORLDWIDE") || regions == ["WORLDWIDE"])
    fail!("trademark review regions are invalid: #{id}")
  end

  review_expired = false
  if decision == "required"
    unless review_fields.all? { |field| review[field].nil? } && channels.empty? && regions.empty?
      fail!("pending trademark review must not carry approval evidence: #{id}")
    end
  else
    %w[reviewedBy reviewerRole authorityReference].each do |field|
      fail!("trademark review evidence is incomplete: #{id}") unless valid_review_text?(review[field], maximum_bytes: 240)
    end
    unless review["evidenceReference"].is_a?(String) &&
           review["evidenceReference"].match?(/\Asha256:[0-9a-f]{64}\z/)
      fail!("trademark review evidence reference is invalid: #{id}")
    end
    reviewed_at = parse_utc_time(review["reviewedAt"], "trademark review timestamp for #{id}")
    unless review["conditions"].nil? || valid_review_text?(review["conditions"], maximum_bytes: 1_000)
      fail!("trademark review conditions are invalid: #{id}")
    end
    if review["expiresAt"]
      expires_at = parse_utc_time(review["expiresAt"], "trademark review expiry for #{id}")
      fail!("trademark review expiry must follow review time: #{id}") unless expires_at > reviewed_at
      review_expired = Time.now.utc >= expires_at
    end

    if decision == "approved"
      fail!("approved trademark review requires reviewed provenance: #{id}") unless asset["provenanceReview"] == "reviewed"
      fail!("approved trademark review must name at least one sales region: #{id}") if regions.empty?
      unless channels == expected_channels
        fail!("approved trademark review must cover every release channel: #{id}")
      end
    else
      unless valid_review_text?(review["conditions"], maximum_bytes: 1_000)
        fail!("rejected trademark review must record conditions: #{id}")
      end
    end
  end

  release_scope_ready = decision == "approved" && regions == ["WORLDWIDE"] &&
    channels == expected_channels && !review_expired
  unless asset["provenanceReview"] == "reviewed" &&
         asset["trademarkReview"] == "approved" && release_scope_ready
    scope = review_expired ? "expired" : decision
    release_blockers << "#{id}(provenance=#{asset["provenanceReview"]},trademark=#{asset["trademarkReview"]},record=#{scope})"
  end
end

actual_sources = Dir.children(source_dir).select { |name| name.end_with?(".svg") }.sort
fail!("brand source directory is not exactly represented by the manifest") unless actual_sources == expected_sources.sort
actual_bundles = Dir.children(bundle_dir).select { |name| name.match?(/\AAgentLogo-.*\.png\z/) }.sort
fail!("brand bundle directory is not exactly represented by the manifest") unless actual_bundles == expected_bundles.sort

if require_release_reviewed && !release_blockers.empty?
  fail!("commercial Release blocked by unreviewed brand assets: #{release_blockers.join(", ")}")
end

puts "Brand asset inventory: PASS (#{assets.length} sources, #{expected_bundles.length} bundled PNGs, #{release_blockers.length} release blockers)"
