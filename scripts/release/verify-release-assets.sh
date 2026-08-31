#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRAND_ASSET_MANIFEST="$ROOT/scripts/assets/agent-logos/manifest.json"
VERSION_VALIDATOR="$ROOT/scripts/release/validate-product-version.rb"
SPARKLE_SIGNATURE_VERIFIER="$ROOT/scripts/release/verify-sparkle-ed25519-signatures.swift"

fail() {
  echo "error: $1" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: verify-release-assets.sh --tag vX.Y.Z --asset-dir DIR [--source-revision SHA]

Verifies one complete, already-downloaded Dev Island GitHub Release without
network access. The asset directory must contain exactly the eight files
published by the release workflow and no symbolic links or extra entries.
EOF
  exit 64
}

TAG=""
ASSET_DIR=""
SOURCE_REVISION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 && -z "$TAG" ]] || usage
      TAG="$2"
      shift 2
      ;;
    --asset-dir)
      [[ $# -ge 2 && -z "$ASSET_DIR" ]] || usage
      ASSET_DIR="$2"
      shift 2
      ;;
    --source-revision)
      [[ $# -ge 2 && -z "$SOURCE_REVISION" ]] || usage
      SOURCE_REVISION="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$TAG" == v* ]] || fail "tag must begin with v"
test -x "$VERSION_VALIDATOR" || fail "product-version validator is missing"
VERSION="$("$VERSION_VALIDATOR" --version "${TAG#v}")"
if [[ -n "$SOURCE_REVISION" ]]; then
  [[ "$SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]] \
    || fail "source revision must be a lowercase 40-character Git SHA"
fi
[[ -n "$ASSET_DIR" && -d "$ASSET_DIR" && ! -L "$ASSET_DIR" ]] \
  || fail "asset directory must be a regular non-symlink directory"
[[ -f "$BRAND_ASSET_MANIFEST" && ! -L "$BRAND_ASSET_MANIFEST" ]] \
  || fail "reviewed brand asset manifest is missing or unsafe"
[[ -f "$SPARKLE_SIGNATURE_VERIFIER" && ! -L "$SPARKLE_SIGNATURE_VERIFIER" ]] \
  || fail "Sparkle Ed25519 signature verifier is missing or unsafe"
ASSET_DIR="$(cd "$ASSET_DIR" && pwd -P)"

EXPECTED_ASSETS=(
  "Dev-Island.dmg"
  "Dev-Island-${VERSION}.dmg"
  "Dev-Island.zip"
  "Dev-Island-${VERSION}.zip"
  "Dev-Island.spdx.json"
  "SHA256SUMS"
  "appcast.xml"
  "dev-island.rb"
)

is_expected_asset() {
  local candidate="$1"
  local expected
  for expected in "${EXPECTED_ASSETS[@]}"; do
    [[ "$candidate" == "$expected" ]] && return 0
  done
  return 1
}

entry_count=0
while IFS= read -r -d '' entry; do
  name="${entry##*/}"
  is_expected_asset "$name" \
    || fail "unexpected release asset or directory: $name"
  [[ -f "$entry" && ! -L "$entry" ]] \
    || fail "release asset must be a regular non-symlink file: $name"
  entry_count=$((entry_count + 1))
done < <(find "$ASSET_DIR" -mindepth 1 -maxdepth 1 -print0)

missing=()
for asset in "${EXPECTED_ASSETS[@]}"; do
  [[ -f "$ASSET_DIR/$asset" && ! -L "$ASSET_DIR/$asset" ]] \
    || missing+=("$asset")
done
if [[ ${#missing[@]} -ne 0 ]]; then
  fail "legacy or incomplete release; missing required assets: ${missing[*]}"
fi
[[ "$entry_count" -eq "${#EXPECTED_ASSETS[@]}" ]] \
  || fail "release asset count is not exactly ${#EXPECTED_ASSETS[@]}"

# Keep metadata inputs bounded before handing them to parsers. DMG/ZIP sizes
# are verified by their manifest and attestations, while these small files
# should never need to grow without an intentional contract change.
check_maximum_size() {
  local path="$1"
  local maximum="$2"
  local size
  size="$(stat -f '%z' "$path")"
  [[ "$size" -gt 0 && "$size" -le "$maximum" ]] \
    || fail "release metadata size is invalid: ${path##*/}"
}
check_maximum_size "$ASSET_DIR/SHA256SUMS" 65536
check_maximum_size "$ASSET_DIR/appcast.xml" 2097152
check_maximum_size "$ASSET_DIR/Dev-Island.spdx.json" 16777216
check_maximum_size "$ASSET_DIR/dev-island.rb" 1048576

cmp -s "$ASSET_DIR/Dev-Island.dmg" "$ASSET_DIR/Dev-Island-${VERSION}.dmg" \
  || fail "stable and versioned DMG bytes differ"
cmp -s "$ASSET_DIR/Dev-Island.zip" "$ASSET_DIR/Dev-Island-${VERSION}.zip" \
  || fail "stable and versioned ZIP bytes differ"

SIGNATURE_TEMP_ROOT="$(mktemp -d -t dev-island-release-signatures)"
case "$SIGNATURE_TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-release-signatures.*|/var/folders/*/T/dev-island-release-signatures.*|/tmp/dev-island-release-signatures.*) ;;
  *) fail "temporary signature-verification directory is unsafe" ;;
esac
chmod 0700 "$SIGNATURE_TEMP_ROOT"
cleanup_signature_temp() {
  case "$SIGNATURE_TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-release-signatures.*|/var/folders/*/T/dev-island-release-signatures.*|/tmp/dev-island-release-signatures.*)
      rm -rf "$SIGNATURE_TEMP_ROOT"
      ;;
  esac
}
trap cleanup_signature_temp EXIT INT TERM

# Bind verification to the key users will actually trust. Extract only the
# exact Info.plist entry rather than expanding an untrusted archive tree; the
# output is private and bounded before plutil reads SUPublicEDKey.
APP_INFO_PLIST="$SIGNATURE_TEMP_ROOT/Info.plist"
(
  umask 077
  ulimit -f 2048
  /usr/bin/unzip -p \
    "$ASSET_DIR/Dev-Island-${VERSION}.zip" \
    'Dev Island.app/Contents/Info.plist' \
    >"$APP_INFO_PLIST" 2>/dev/null
) || fail "signed App Info.plist could not be extracted safely from the versioned ZIP"
check_maximum_size "$APP_INFO_PLIST" 1048576
if ! SPARKLE_PUBLIC_KEY="$(
  /usr/bin/plutil -extract SUPublicEDKey raw -o - "$APP_INFO_PLIST" 2>/dev/null
)"; then
  fail "signed App does not contain a readable SUPublicEDKey"
fi
[[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
  || fail "signed App SUPublicEDKey is not canonical base64 for 32 bytes"

ASSET_DIR="$ASSET_DIR" VERSION="$VERSION" SOURCE_REVISION="$SOURCE_REVISION" \
  BRAND_ASSET_MANIFEST="$BRAND_ASSET_MANIFEST" \
  SPARKLE_SIGNATURE_VERIFIER="$SPARKLE_SIGNATURE_VERIFIER" \
  SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
  ruby <<'RUBY'
require "base64"
require "digest"
require "json"
require "rexml/document"
require "uri"

def fail(message)
  warn "error: #{message}"
  exit 1
end

directory = ENV.fetch("ASSET_DIR")
version = ENV.fetch("VERSION")
expected_source_revision = ENV.fetch("SOURCE_REVISION")
brand_asset_manifest_path = ENV.fetch("BRAND_ASSET_MANIFEST")
signature_verifier_path = ENV.fetch("SPARKLE_SIGNATURE_VERIFIER")
sparkle_public_key = ENV.fetch("SPARKLE_PUBLIC_KEY")
path = ->(name) { File.join(directory, name) }
expected_artifacts = [
  "Dev-Island.dmg",
  "Dev-Island-#{version}.dmg",
  "Dev-Island.zip",
  "Dev-Island-#{version}.zip",
  "Dev-Island.spdx.json",
  "appcast.xml",
  "dev-island.rb",
].sort

# Parse the checksum inventory before invoking shasum so a malicious filename
# cannot escape the verified directory or be interpreted as an option.
manifest = File.binread(path.call("SHA256SUMS"))
fail("SHA256SUMS must end with one newline") unless manifest.end_with?("\n")
manifest_lines = manifest.lines
fail("SHA256SUMS must cover exactly seven non-manifest assets") unless manifest_lines.length == 7
manifest_entries = {}
manifest_lines.each do |line|
  match = line.match(/\A([0-9a-f]{64})  ([A-Za-z0-9.-]+)\n\z/)
  fail("SHA256SUMS contains a malformed entry") unless match
  digest, name = match.captures
  fail("SHA256SUMS contains a duplicate entry: #{name}") if manifest_entries.key?(name)
  manifest_entries[name] = digest
end
fail("SHA256SUMS does not contain the exact release asset set") unless manifest_entries.keys.sort == expected_artifacts
fail("SHA256SUMS entries are not in deterministic filename order") unless manifest_entries.keys == expected_artifacts
manifest_entries.each do |name, expected_digest|
  actual_digest = Digest::SHA256.file(path.call(name)).hexdigest
  fail("SHA256SUMS digest mismatch: #{name}") unless actual_digest == expected_digest
end

zip_digest = Digest::SHA256.file(path.call("Dev-Island.zip")).hexdigest
cask = File.binread(path.call("dev-island.rb"))
fail("Homebrew Cask is not UTF-8") unless cask.force_encoding(Encoding::UTF_8).valid_encoding?
version_matches = cask.scan(/^  version "([^"]+)"$/).flatten
sha_matches = cask.scan(/^  sha256 "([0-9a-f]+)"$/).flatten
url_matches = cask.scan(/^  url "([^"]+)"$/).flatten
fail("Homebrew Cask must contain exactly one pinned version") unless version_matches == [version]
fail("Homebrew Cask ZIP SHA-256 does not match Dev-Island.zip") unless sha_matches == [zip_digest]
expected_cask_url = "https://github.com/sheepxux/Dev-Island/releases/download/v\#{version}/Dev-Island.zip"
fail("Homebrew Cask URL is not pinned to the versioned GitHub Release") unless url_matches == [expected_cask_url]
[
  /:no_check/,
  %r{/releases/latest/},
  /^\s*(preflight|postflight)\b/,
  /^\s*system\b/,
  /^[ \t]*`[^`]*`/,
  /^[ \t]*%x[({\[]/,
].each do |forbidden|
  fail("Homebrew Cask contains a forbidden executable or mutable construct") if cask.match?(forbidden)
end

appcast = File.binread(path.call("appcast.xml"))
fail("appcast must not contain a DTD or entity declaration") if appcast.match?(/<!DOCTYPE|<!ENTITY/i)
begin
  document = REXML::Document.new(appcast)
rescue REXML::ParseException
  fail("appcast is not well-formed XML")
end
items = REXML::XPath.match(document, "/rss/channel/item")
fail("appcast must contain exactly one update item") unless items.length == 1
item = items.first
sparkle_version = item.elements["sparkle:version"]&.text
short_version = item.elements["sparkle:shortVersionString"]&.text
fail("appcast version does not match the Release tag") unless sparkle_version == version && short_version == version
enclosures = item.get_elements("enclosure")
fail("appcast must contain exactly one enclosure") unless enclosures.length == 1
enclosure = enclosures.first
expected_archive = "Dev-Island-#{version}.zip"
expected_url = "https://github.com/sheepxux/Dev-Island/releases/download/v#{version}/#{expected_archive}"
fail("appcast enclosure URL is not immutable or does not match the tag") unless enclosure.attributes["url"] == expected_url
fail("appcast enclosure content type is unexpected") unless enclosure.attributes["type"] == "application/octet-stream"
archive_length = enclosure.attributes["length"]
fail("appcast enclosure length is malformed") unless archive_length&.match?(/\A[1-9][0-9]*\z/)
fail("appcast enclosure length does not match the versioned ZIP") unless archive_length.to_i == File.size(path.call(expected_archive))
archive_signature = enclosure.attributes["sparkle:edSignature"]
begin
  decoded_archive_signature = Base64.strict_decode64(archive_signature.to_s)
rescue ArgumentError
  fail("appcast archive Ed25519 signature is malformed")
end
fail("appcast archive Ed25519 signature must decode to 64 bytes") unless decoded_archive_signature.bytesize == 64

feed_match = appcast.match(/<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+\/=]+)\nlength: ([0-9]+)\n-->\n?\z/)
fail("appcast signed-feed block is missing or malformed") unless feed_match
begin
  decoded_feed_signature = Base64.strict_decode64(feed_match[1])
rescue ArgumentError
  fail("appcast feed Ed25519 signature is malformed")
end
fail("appcast feed Ed25519 signature must decode to 64 bytes") unless decoded_feed_signature.bytesize == 64
feed_marker_offset = appcast.index("<!-- sparkle-signatures:")
fail("appcast signed-feed length does not match the signed byte prefix") unless feed_marker_offset && feed_match[2].to_i == feed_marker_offset

signature_verified = system(
  { "PATH" => "/usr/bin:/bin", "LANG" => "C", "LC_ALL" => "C" },
  "/usr/bin/swift",
  signature_verifier_path,
  "verify-sparkle",
  "--public-key-base64", sparkle_public_key,
  "--archive-file", path.call(expected_archive),
  "--archive-signature-base64", archive_signature,
  "--feed-file", path.call("appcast.xml"),
  "--feed-signature-base64", feed_match[1],
  "--feed-prefix-length", feed_match[2],
  out: File::NULL,
  unsetenv_others: true
)
fail("appcast Ed25519 cryptographic verification failed") unless signature_verified

begin
  sbom = JSON.parse(File.binread(path.call("Dev-Island.spdx.json")))
rescue JSON::ParserError
  fail("SPDX SBOM is not valid JSON")
end
fail("SPDX SBOM root must be a JSON object") unless sbom.is_a?(Hash)
fail("SPDX SBOM version must be SPDX-2.3") unless sbom["spdxVersion"] == "SPDX-2.3"
fail("SPDX SBOM data license must be CC0-1.0") unless sbom["dataLicense"] == "CC0-1.0"
fail("SPDX SBOM document ID is invalid") unless sbom["SPDXID"] == "SPDXRef-DOCUMENT"
fail("SPDX SBOM name does not match the Release version") unless sbom["name"] == "Dev-Island-#{version}-SBOM"
namespace_pattern = %r{\Ahttps://devisland\.app/spdx/dev-island/#{Regexp.escape(version)}/([0-9a-f]{40})/[0-9a-f]{64}\z}
namespace_match = sbom["documentNamespace"].to_s.match(namespace_pattern)
fail("SPDX SBOM namespace is not bound to the version and source revision") unless namespace_match
source_revision = namespace_match[1]
if !expected_source_revision.empty? && source_revision != expected_source_revision
  fail("SPDX SBOM source revision does not match the tagged commit")
end

packages = sbom["packages"]
fail("SPDX SBOM packages must be a non-empty bounded array") unless packages.is_a?(Array) && packages.length.between?(3, 512)
fail("SPDX SBOM contains a non-object package") unless packages.all? { |package| package.is_a?(Hash) }
ids = packages.map { |package| package["SPDXID"] }
fail("SPDX SBOM package IDs must be unique strings") unless ids.all? { |id| id.is_a?(String) && id.match?(/\ASPDXRef-Package-[A-Za-z0-9.-]+\z/) } && ids.uniq.length == ids.length
root_packages = packages.select { |package| package["SPDXID"] == "SPDXRef-Package-Dev-Island" }
fail("SPDX SBOM must contain exactly one Dev Island root package") unless root_packages.length == 1
root = root_packages.first
root_contract = root["name"] == "Dev Island" &&
  root["versionInfo"] == version &&
  root["downloadLocation"] == "https://github.com/sheepxux/Dev-Island" &&
  root["filesAnalyzed"] == false &&
  root["primaryPackagePurpose"] == "APPLICATION" &&
  root["sourceInfo"] == "Git revision #{source_revision}"
fail("SPDX SBOM Dev Island root package contract is invalid") unless root_contract
root_refs = root["externalRefs"]
root_purl = "pkg:github/sheepxux/Dev-Island@#{version}"
fail("SPDX SBOM Dev Island package URL is missing") unless root_refs.is_a?(Array) && root_refs.any? { |reference| reference.is_a?(Hash) && reference["referenceLocator"] == root_purl }

relationships = sbom["relationships"]
fail("SPDX SBOM relationships must be a non-empty bounded array") unless relationships.is_a?(Array) && relationships.length.between?(2, 2048)
triples = relationships.map do |relationship|
  fail("SPDX SBOM contains a non-object relationship") unless relationship.is_a?(Hash)
  [relationship["spdxElementId"], relationship["relationshipType"], relationship["relatedSpdxElement"]]
end
fail("SPDX SBOM relationships must be unique") unless triples.uniq.length == triples.length
describes = triples.select { |triple| triple == ["SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-Package-Dev-Island"] }
fail("SPDX SBOM must describe the Dev Island root exactly once") unless describes.length == 1
known_ids = ids + ["SPDXRef-DOCUMENT"]
fail("SPDX SBOM relationship references an unknown element") unless triples.all? { |triple| known_ids.include?(triple[0]) && known_ids.include?(triple[2]) }
root_dependencies = triples.select { |triple| triple[0] == "SPDXRef-Package-Dev-Island" && triple[1] == "DEPENDS_ON" }
fail("SPDX SBOM must relate Dev Island to its dependencies") if root_dependencies.empty?
swift_toml = packages.find { |package| package["name"] == "swift-toml" }
tomlplusplus = packages.find { |package| package["name"] == "tomlplusplus" }
fail("SPDX SBOM must inventory swift-toml and its vendored toml++ component") unless swift_toml && tomlplusplus
toml_relationship = [swift_toml["SPDXID"], "DEPENDS_ON", tomlplusplus["SPDXID"]]
fail("SPDX SBOM must relate swift-toml to vendored toml++") unless triples.include?(toml_relationship)

begin
  brand_manifest = JSON.parse(File.binread(brand_asset_manifest_path))
rescue JSON::ParserError
  fail("reviewed brand asset manifest is not valid JSON")
end
brand_assets = brand_manifest["assets"]
fail("reviewed brand asset manifest contract is invalid") unless brand_manifest["schemaVersion"] == 3 && brand_assets.is_a?(Array) && brand_assets.length == 9
expected_brand_ids = brand_assets.map { |asset| asset["id"] }
fail("reviewed brand asset manifest IDs are invalid") unless expected_brand_ids == expected_brand_ids.sort && expected_brand_ids.uniq.length == 9
expected_brand_package_ids = brand_assets.map do |asset|
  asset["id"] == "opencode" ? "SPDXRef-Package-opencode-brand-square" : "SPDXRef-Package-agent-brand-#{asset["id"]}"
end
actual_brand_packages = packages.select { |package| expected_brand_package_ids.include?(package["SPDXID"]) }
fail("SPDX SBOM must inventory all nine reviewed Agent brand assets exactly once") unless actual_brand_packages.length == 9

brand_assets.each do |asset|
  id = asset.fetch("id")
  package_id = id == "opencode" ? "SPDXRef-Package-opencode-brand-square" : "SPDXRef-Package-agent-brand-#{id}"
  matches = packages.select { |package| package["SPDXID"] == package_id }
  fail("SPDX SBOM brand asset is missing or duplicated: #{id}") unless matches.length == 1
  package = matches.first
  upstream = asset.fetch("upstream")
  asserted = upstream.fetch("repository") != "NOASSERTION"
  expected_name = id == "opencode" ? "opencode-logo-dark-square" : "#{id}-agent-brand-assets"
  contract = package["name"] == expected_name &&
    package["downloadLocation"] == (asserted ? upstream.fetch("repository") : "NOASSERTION") &&
    package["filesAnalyzed"] == false &&
    package["licenseConcluded"] == asset.fetch("assetLicense") &&
    package["licenseDeclared"] == asset.fetch("assetLicense") &&
    package["primaryPackagePurpose"] == "FILE"
  expected_version = upstream.fetch("version")
  contract &&= expected_version == "NOASSERTION" ? !package.key?("versionInfo") : package["versionInfo"] == expected_version
  fail("SPDX SBOM brand asset contract is invalid: #{id}") unless contract

  source_info = package["sourceInfo"].to_s
  fail("SPDX SBOM brand source hash is missing: #{id}") unless source_info.include?("source SVG SHA-256 #{asset.fetch("sourceSHA256")}")
  asset.fetch("bundleFiles").each do |bundle|
    expected_hash = "#{bundle.fetch("name")}=#{bundle.fetch("sha256")}"
    fail("SPDX SBOM packaged brand hash is missing: #{bundle.fetch("name")}") unless source_info.include?(expected_hash)
  end
  if asserted
    upstream_contract = source_info.include?("Git revision #{upstream.fetch("revision")}") &&
      source_info.include?("path #{upstream.fetch("path")}") &&
      source_info.include?("upstream SVG SHA-256 #{upstream.fetch("sha256")}") &&
      source_info.include?("transform #{upstream.fetch("transform")}")
    fail("SPDX SBOM brand upstream revision/path/hash/transform is missing: #{id}") unless upstream_contract
    owner, repository = URI.parse(upstream.fetch("repository")).path.split("/").reject(&:empty?)
    expected_purl = "pkg:github/#{owner}/#{repository}@#{upstream.fetch("revision")}"
    refs = package["externalRefs"]
    fail("SPDX SBOM brand package URL is missing: #{id}") unless refs.is_a?(Array) && refs.any? { |reference| reference.is_a?(Hash) && reference["referenceLocator"] == expected_purl }
  else
    fail("SPDX SBOM unasserted brand must not claim a package URL: #{id}") if package.key?("externalRefs")
  end
  comment = package["comment"].to_s
  [
    "Bundled notice: #{asset.fetch("bundledNotice")} SHA-256 #{asset.fetch("bundledNoticeSHA256")}",
    "provenanceReview=#{asset.fetch("provenanceReview")}",
    "trademarkReview=#{asset.fetch("trademarkReview")}",
  ].each do |required|
    fail("SPDX SBOM brand review metadata is missing: #{id}") unless comment.include?(required)
  end
  relationship = ["SPDXRef-Package-Dev-Island", "CONTAINS", package_id]
  fail("SPDX SBOM must relate Dev Island to contained brand asset: #{id}") unless triples.include?(relationship)
end

open_code_assets = packages.select { |package| package["name"] == "opencode-logo-dark-square" }
fail("SPDX SBOM must inventory the reviewed OpenCode brand asset exactly once") unless open_code_assets.length == 1
open_code = open_code_assets.first
open_code_revision = "13c27598d35f6f91fa4763a0b61a220ab7fcb263"
open_code_sha256 = "d6a0e3b8a295f413543f41cb73957e670351b5cb088c8d9dbd186b9e9d633cca"
open_code_contract = open_code["SPDXID"] == "SPDXRef-Package-opencode-brand-square" &&
  open_code["versionInfo"] == "1.18.23" &&
  open_code["downloadLocation"] == "https://github.com/anomalyco/opencode" &&
  open_code["filesAnalyzed"] == false &&
  open_code["licenseConcluded"] == "MIT" &&
  open_code["licenseDeclared"] == "MIT" &&
  open_code["primaryPackagePurpose"] == "FILE" &&
  open_code["sourceInfo"].to_s.include?("Git revision #{open_code_revision}") &&
  open_code["sourceInfo"].to_s.include?("SHA-256 #{open_code_sha256}") &&
  open_code["comment"].to_s.include?("opencode-MIT-LICENSE")
fail("SPDX SBOM OpenCode brand asset contract is invalid") unless open_code_contract
open_code_purl = "pkg:github/anomalyco/opencode@#{open_code_revision}"
open_code_refs = open_code["externalRefs"]
fail("SPDX SBOM OpenCode brand asset package URL is missing") unless open_code_refs.is_a?(Array) && open_code_refs.any? { |reference| reference.is_a?(Hash) && reference["referenceLocator"] == open_code_purl }
open_code_relationship = ["SPDXRef-Package-Dev-Island", "CONTAINS", open_code["SPDXID"]]
fail("SPDX SBOM must relate Dev Island to the contained OpenCode brand asset") unless triples.include?(open_code_relationship)
RUBY

(
  cd "$ASSET_DIR"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "SHA256SUMS verification failed"

ruby -c "$ASSET_DIR/dev-island.rb" >/dev/null \
  || fail "Homebrew Cask is not valid Ruby"

echo "Release asset contract: PASS (${TAG}, ${entry_count} assets)"
