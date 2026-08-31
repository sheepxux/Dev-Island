#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

VERIFIER="$ROOT/scripts/release/verify-release-assets.sh"
METADATA_VALIDATOR="$ROOT/scripts/release/validate-published-release-metadata.rb"
INTEGRITY_GENERATOR="$ROOT/scripts/release/generate-release-integrity-manifest.sh"
SPARKLE_SIGN_TOOL="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
SPARKLE_SIGNATURE_VERIFIER="$ROOT/scripts/release/verify-sparkle-ed25519-signatures.swift"
VERSION="$(cat VERSION)"
TAG="v${VERSION}"
SOURCE_REVISION="$(printf 'a%.0s' {1..40})"

# RFC 8032 test-vector seed/public keys. These are public fixture material,
# never production credentials. The second public key is intentionally
# unrelated so the extracted-App trust binding can be attacked deterministically.
FIXTURE_PRIVATE_KEY="$(
  printf '%s' '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
    | xxd -r -p | base64 | tr -d '\n'
)"
FIXTURE_PUBLIC_KEY='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
MISMATCHED_PUBLIC_KEY='PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw='
UNRELATED_SIGNATURE="$(
  printf '%s' 'Dev Island deterministic unrelated Ed25519 signature fixture' \
    | shasum -a 512 | awk '{print $1}' | xxd -r -p | base64 | tr -d '\n'
)"

test -x "$VERIFIER" || fail "Release asset verifier is missing or not executable"
test -x "$METADATA_VALIDATOR" || fail "Published Release metadata validator is missing or not executable"
test -x "$INTEGRITY_GENERATOR" || fail "Release integrity generator is missing or not executable"
test -x "$SPARKLE_SIGN_TOOL" && test ! -L "$SPARKLE_SIGN_TOOL" \
  || fail "Pinned Sparkle sign_update fixture dependency is missing or unsafe"
test -f "$SPARKLE_SIGNATURE_VERIFIER" && test ! -L "$SPARKLE_SIGNATURE_VERIFIER" \
  || fail "CryptoKit Sparkle verifier is missing or unsafe"

TEMP_DIR="$(mktemp -d -t dev-island-release-verifier)"
cleanup() {
  [[ "$TEMP_DIR" == /private/var/folders/*/T/dev-island-release-verifier.* \
     || "$TEMP_DIR" == /var/folders/*/T/dev-island-release-verifier.* \
     || "$TEMP_DIR" == /tmp/dev-island-release-verifier.* ]] \
    && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

write_fixture_archive() {
  local output="$1"
  local public_key="$2"
  local fixture_root
  fixture_root="$(mktemp -d "$TEMP_DIR/archive-app.XXXXXX")"
  mkdir -p "$fixture_root/Dev Island.app/Contents/MacOS"
  /usr/bin/plutil -create xml1 "$fixture_root/Dev Island.app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string app.devisland.Island \
    "$fixture_root/Dev Island.app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" \
    "$fixture_root/Dev Island.app/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleVersion -string "$VERSION" \
    "$fixture_root/Dev Island.app/Contents/Info.plist"
  /usr/bin/plutil -insert SUPublicEDKey -string "$public_key" \
    "$fixture_root/Dev Island.app/Contents/Info.plist"
  printf 'fixture-executable' >"$fixture_root/Dev Island.app/Contents/MacOS/IslandApp"
  chmod 0755 "$fixture_root/Dev Island.app/Contents/MacOS/IslandApp"
  ditto -c -k --keepParent "$fixture_root/Dev Island.app" "$output"
}

sign_fixture_file() {
  local input="$1"
  printf '%s' "$FIXTURE_PRIVATE_KEY" \
    | env -i \
        PATH='/usr/bin:/bin' \
        LANG='C' \
        LC_ALL='C' \
        "$SPARKLE_SIGN_TOOL" \
          --ed-key-file - \
          -p \
          "$input"
}

write_signed_appcast() {
  local directory="$1"
  local archive="$directory/Dev-Island-${VERSION}.zip"
  local zip_size
  local archive_signature
  zip_size="$(stat -f '%z' "$archive")"
  archive_signature="$(sign_fixture_file "$archive")"
  ruby - "$directory/appcast.xml" "$VERSION" "$zip_size" "$archive_signature" <<'RUBY'
path, version, zip_size, signature = ARGV
payload = <<~XML
  <?xml version="1.0" standalone="yes"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
      <channel>
          <title>Dev Island</title>
          <item>
              <title>#{version}</title>
              <link>https://devisland.app</link>
              <sparkle:version>#{version}</sparkle:version>
              <sparkle:shortVersionString>#{version}</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
              <enclosure url="https://github.com/sheepxux/Dev-Island/releases/download/v#{version}/Dev-Island-#{version}.zip" length="#{zip_size}" type="application/octet-stream" sparkle:edSignature="#{signature}"></enclosure>
          </item>
      </channel>
  </rss>
XML
File.binwrite(path, payload)
RUBY
  printf '%s' "$FIXTURE_PRIVATE_KEY" \
    | env -i \
        PATH='/usr/bin:/bin' \
        LANG='C' \
        LC_ALL='C' \
        "$SPARKLE_SIGN_TOOL" \
          --ed-key-file - \
          "$directory/appcast.xml" \
          >/dev/null
}

VALID="$TEMP_DIR/valid"
mkdir -p "$VALID"
printf 'notarized-dmg-fixture' >"$VALID/Dev-Island.dmg"
cp "$VALID/Dev-Island.dmg" "$VALID/Dev-Island-${VERSION}.dmg"
write_fixture_archive "$VALID/Dev-Island.zip" "$FIXTURE_PUBLIC_KEY"
cp "$VALID/Dev-Island.zip" "$VALID/Dev-Island-${VERSION}.zip"
write_signed_appcast "$VALID"

ruby -r json -r uri - "$VALID/Dev-Island.spdx.json" "$VERSION" "$SOURCE_REVISION" \
  "$ROOT/scripts/assets/agent-logos/manifest.json" <<'RUBY'
path, version, revision, brand_manifest_path = ARGV
root_id = "SPDXRef-Package-Dev-Island"
swift_toml_id = "SPDXRef-Package-swift-toml-bbbbbbbbbbbb"
toml_id = "SPDXRef-Package-tomlplusplus"
brand_assets = JSON.parse(File.binread(brand_manifest_path)).fetch("assets")
brand_packages = brand_assets.map do |asset|
  upstream = asset.fetch("upstream")
  asserted = upstream.fetch("repository") != "NOASSERTION"
  id = asset.fetch("id")
  package_id = id == "opencode" ? "SPDXRef-Package-opencode-brand-square" : "SPDXRef-Package-agent-brand-#{id}"
  bundle_hashes = asset.fetch("bundleFiles").map do |bundle|
    "#{bundle.fetch("name")}=#{bundle.fetch("sha256")}"
  end.join(", ")
  source_info = if asserted
    "Official #{asset.fetch("displayName")} brand asset at Git revision #{upstream.fetch("revision")}; path #{upstream.fetch("path")}; upstream SVG SHA-256 #{upstream.fetch("sha256")}; transform #{upstream.fetch("transform")}; source SVG SHA-256 #{asset.fetch("sourceSHA256")}; shipped PNG SHA-256 #{bundle_hashes}"
  else
    "Local #{asset.fetch("displayName")} brand source awaiting upstream provenance review; source SVG SHA-256 #{asset.fetch("sourceSHA256")}; shipped PNG SHA-256 #{bundle_hashes}"
  end
  package = {
    "SPDXID" => package_id,
    "name" => id == "opencode" ? "opencode-logo-dark-square" : "#{id}-agent-brand-assets",
    "downloadLocation" => asserted ? upstream.fetch("repository") : "NOASSERTION",
    "filesAnalyzed" => false,
    "licenseConcluded" => asset.fetch("assetLicense"),
    "licenseDeclared" => asset.fetch("assetLicense"),
    "copyrightText" => id == "opencode" ? "Copyright (c) 2025 opencode" : "NOASSERTION",
    "primaryPackagePurpose" => "FILE",
    "sourceInfo" => source_info,
    "comment" => "Bundled notice: #{asset.fetch("bundledNotice")} SHA-256 #{asset.fetch("bundledNoticeSHA256")}; provenanceReview=#{asset.fetch("provenanceReview")}; trademarkReview=#{asset.fetch("trademarkReview")}; nominative use does not imply affiliation or endorsement",
  }
  package["versionInfo"] = upstream.fetch("version") if upstream.fetch("version") != "NOASSERTION"
  if asserted
    owner, repository = URI.parse(upstream.fetch("repository")).path.split("/").reject(&:empty?)
    package["externalRefs"] = [{
      "referenceCategory" => "PACKAGE-MANAGER",
      "referenceType" => "purl",
      "referenceLocator" => "pkg:github/#{owner}/#{repository}@#{upstream.fetch("revision")}",
    }]
  end
  package
end
brand_relationships = brand_packages.map do |package|
  {
    "spdxElementId" => root_id,
    "relationshipType" => "CONTAINS",
    "relatedSpdxElement" => package.fetch("SPDXID"),
  }
end
document = {
  "spdxVersion" => "SPDX-2.3",
  "dataLicense" => "CC0-1.0",
  "SPDXID" => "SPDXRef-DOCUMENT",
  "name" => "Dev-Island-#{version}-SBOM",
  "documentNamespace" => "https://devisland.app/spdx/dev-island/#{version}/#{revision}/#{"c" * 64}",
  "creationInfo" => {
    "created" => "2026-08-27T00:00:00Z",
    "creators" => ["Tool: Dev-Island-release-sbom/1"],
  },
  "packages" => [
    {
      "SPDXID" => root_id,
      "name" => "Dev Island",
      "versionInfo" => version,
      "downloadLocation" => "https://github.com/sheepxux/Dev-Island",
      "filesAnalyzed" => false,
      "licenseConcluded" => "MIT",
      "licenseDeclared" => "MIT",
      "copyrightText" => "NOASSERTION",
      "primaryPackagePurpose" => "APPLICATION",
      "sourceInfo" => "Git revision #{revision}",
      "externalRefs" => [{
        "referenceCategory" => "PACKAGE-MANAGER",
        "referenceType" => "purl",
        "referenceLocator" => "pkg:github/sheepxux/Dev-Island@#{version}",
      }],
    },
    {
      "SPDXID" => swift_toml_id,
      "name" => "swift-toml",
      "versionInfo" => "2.0.0",
      "downloadLocation" => "https://github.com/mattt/swift-toml.git",
      "filesAnalyzed" => false,
      "primaryPackagePurpose" => "LIBRARY",
    },
    {
      "SPDXID" => toml_id,
      "name" => "tomlplusplus",
      "versionInfo" => "3.4.0",
      "downloadLocation" => "https://github.com/marzer/tomlplusplus",
      "filesAnalyzed" => false,
      "primaryPackagePurpose" => "LIBRARY",
    },
  ] + brand_packages,
  "relationships" => [
    {
      "spdxElementId" => "SPDXRef-DOCUMENT",
      "relationshipType" => "DESCRIBES",
      "relatedSpdxElement" => root_id,
    },
    {
      "spdxElementId" => root_id,
      "relationshipType" => "DEPENDS_ON",
      "relatedSpdxElement" => swift_toml_id,
    },
    {
      "spdxElementId" => swift_toml_id,
      "relationshipType" => "DEPENDS_ON",
      "relatedSpdxElement" => toml_id,
    },
  ] + brand_relationships,
}
File.binwrite(path, JSON.pretty_generate(document) + "\n")
RUBY

ZIP_SHA="$(shasum -a 256 "$VALID/Dev-Island.zip" | awk '{print $1}')"
VERSION="$VERSION" SHA256="$ZIP_SHA" OUTPUT="$VALID/dev-island.rb" \
  ./scripts/render-homebrew-cask.sh >/dev/null
VERSION="$VERSION" BUILD_DIR="$VALID" "$INTEGRITY_GENERATOR" >/dev/null

"$VERIFIER" \
  --tag "$TAG" \
  --asset-dir "$VALID" \
  --source-revision "$SOURCE_REVISION" >/dev/null \
  || fail "Valid complete Release fixture did not pass"

RELEASE_JSON="$TEMP_DIR/release.json"
ruby -r json - "$RELEASE_JSON" "$TAG" "$VERSION" "$VALID" <<'RUBY'
path, tag, version, asset_directory = ARGV
names = [
  "Dev-Island.dmg",
  "Dev-Island-#{version}.dmg",
  "Dev-Island.zip",
  "Dev-Island-#{version}.zip",
  "Dev-Island.spdx.json",
  "SHA256SUMS",
  "appcast.xml",
  "dev-island.rb",
]
release = {
  "tag_name" => tag,
  "draft" => false,
  "prerelease" => false,
  "assets" => names.map do |name|
    {
      "name" => name,
      "state" => "uploaded",
      "size" => File.size(File.join(asset_directory, name)),
      "browser_download_url" => "https://github.com/sheepxux/Dev-Island/releases/download/#{tag}/#{name}",
    }
  end,
}
File.binwrite(path, JSON.generate(release) + "\n")
RUBY
"$METADATA_VALIDATOR" --json "$RELEASE_JSON" --tag "$TAG" >/dev/null \
  || fail "Valid published Release API fixture did not pass"

DUPLICATE_RELEASE_JSON="$TEMP_DIR/duplicate-release.json"
ruby -r json - "$RELEASE_JSON" "$DUPLICATE_RELEASE_JSON" <<'RUBY'
source, destination = ARGV
release = JSON.parse(File.binread(source))
release.fetch("assets") << release.fetch("assets").first.dup
File.binwrite(destination, JSON.generate(release) + "\n")
RUBY
if "$METADATA_VALIDATOR" --json "$DUPLICATE_RELEASE_JSON" --tag "$TAG" \
  >"$TEMP_DIR/duplicate-release.output" 2>&1; then
  fail "Duplicate published Release asset names unexpectedly passed"
fi
rg -Fq "GitHub Release contains duplicate asset names" \
  "$TEMP_DIR/duplicate-release.output" \
  || fail "Duplicate published Release asset fixture failed for the wrong reason"

make_case() {
  local name="$1"
  local case_dir="$TEMP_DIR/$name"
  cp -R "$VALID" "$case_dir"
  printf '%s\n' "$case_dir"
}

refresh_manifest() {
  local case_dir="$1"
  rm -f "$case_dir/SHA256SUMS"
  VERSION="$VERSION" BUILD_DIR="$case_dir" "$INTEGRITY_GENERATOR" >/dev/null
}

repair_feed_length() {
  local appcast="$1"
  ruby - "$appcast" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path)
marker = contents.index("<!-- sparkle-signatures:")
abort "missing feed marker" unless marker
contents.sub!(/length: [0-9]+\n-->\n?\z/, "length: #{marker}\n-->\n")
File.binwrite(path, contents)
RUBY
}

expect_failure() {
  local name="$1"
  local expected_message="$2"
  local case_dir="$3"
  local output="$TEMP_DIR/${name}.output"
  if "$VERIFIER" \
    --tag "$TAG" \
    --asset-dir "$case_dir" \
    --source-revision "$SOURCE_REVISION" >"$output" 2>&1; then
    fail "Negative Release fixture unexpectedly passed: $name"
  fi
  if ! rg -Fq "$expected_message" "$output"; then
    sed -n '1,8p' "$output" >&2
    fail "Negative fixture '$name' failed for the wrong reason; expected: $expected_message"
  fi
}

CASE_DIR="$(make_case missing-asset)"
rm -f "$CASE_DIR/appcast.xml"
expect_failure missing-asset "missing required assets: appcast.xml" "$CASE_DIR"

CASE_DIR="$(make_case manifest-tamper)"
ruby - "$CASE_DIR/SHA256SUMS" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path)
contents.setbyte(0, contents.getbyte(0) == 48 ? 49 : 48)
File.binwrite(path, contents)
RUBY
expect_failure manifest-tamper "SHA256SUMS digest mismatch" "$CASE_DIR"

CASE_DIR="$(make_case mismatched-alias)"
printf 'different-versioned-zip' >"$CASE_DIR/Dev-Island-${VERSION}.zip"
expect_failure mismatched-alias "stable and versioned ZIP bytes differ" "$CASE_DIR"

CASE_DIR="$(make_case symbolic-link)"
rm -f "$CASE_DIR/appcast.xml"
ln -s /dev/null "$CASE_DIR/appcast.xml"
expect_failure symbolic-link "regular non-symlink file: appcast.xml" "$CASE_DIR"

CASE_DIR="$(make_case cask-sha)"
ruby - "$CASE_DIR/dev-island.rb" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub(/^  sha256 "[0-9a-f]+"$/, "  sha256 \"#{"0" * 64}\"")
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure cask-sha "Homebrew Cask ZIP SHA-256 does not match" "$CASE_DIR"

CASE_DIR="$(make_case cask-version)"
ruby - "$CASE_DIR/dev-island.rb" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub(/^  version "[^"]+"$/, "  version \"9.9.9\"")
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure cask-version "Homebrew Cask must contain exactly one pinned version" "$CASE_DIR"

CASE_DIR="$(make_case cask-url)"
ruby - "$CASE_DIR/dev-island.rb" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub("sheepxux/Dev-Island/releases/download", "sheepxuy/Dev-Island/releases/download")
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure cask-url "Homebrew Cask URL is not pinned" "$CASE_DIR"

CASE_DIR="$(make_case appcast-url)"
ruby - "$CASE_DIR/appcast.xml" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub("sheepxux/Dev-Island/releases/download", "sheepxuy/Dev-Island/releases/download")
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure appcast-url "appcast enclosure URL is not immutable" "$CASE_DIR"

CASE_DIR="$(make_case appcast-length)"
ruby - "$CASE_DIR/appcast.xml" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub(/length="[0-9]+" type=/, "length=\"999\" type=")
File.binwrite(path, contents)
RUBY
repair_feed_length "$CASE_DIR/appcast.xml"
refresh_manifest "$CASE_DIR"
expect_failure appcast-length "appcast enclosure length does not match" "$CASE_DIR"

CASE_DIR="$(make_case appcast-archive-signature)"
ruby - "$CASE_DIR/appcast.xml" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub(/sparkle:edSignature="[^"]+"/, "sparkle:edSignature=\"bad\"")
File.binwrite(path, contents)
RUBY
repair_feed_length "$CASE_DIR/appcast.xml"
refresh_manifest "$CASE_DIR"
expect_failure appcast-archive-signature "archive Ed25519 signature is malformed" "$CASE_DIR"

CASE_DIR="$(make_case unrelated-archive-signature)"
ruby - "$CASE_DIR/appcast.xml" "$UNRELATED_SIGNATURE" <<'RUBY'
path, signature = ARGV
contents = File.binread(path).sub(
  /sparkle:edSignature="[^"]+"/,
  "sparkle:edSignature=\"#{signature}\""
)
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure unrelated-archive-signature \
  "Sparkle archive Ed25519 signature verification failed" \
  "$CASE_DIR"

CASE_DIR="$(make_case appcast-feed-signature)"
ruby - "$CASE_DIR/appcast.xml" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub(/<!-- sparkle-signatures:[\s\S]*\z/, "")
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure appcast-feed-signature "signed-feed block is missing" "$CASE_DIR"

CASE_DIR="$(make_case unrelated-feed-signature)"
ruby - "$CASE_DIR/appcast.xml" "$UNRELATED_SIGNATURE" <<'RUBY'
path, signature = ARGV
contents = File.binread(path).sub(
  /(<!-- sparkle-signatures:\nedSignature: )[A-Za-z0-9+\/=]+(\nlength:)/,
  "\\1#{signature}\\2"
)
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure unrelated-feed-signature \
  "Sparkle feed Ed25519 signature verification failed" \
  "$CASE_DIR"

CASE_DIR="$(make_case tampered-signed-feed-prefix)"
ruby - "$CASE_DIR/appcast.xml" <<'RUBY'
path = ARGV.fetch(0)
contents = File.binread(path).sub(
  "<link>https://devisland.app</link>",
  "<link>https://devisland.apq</link>"
)
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure tampered-signed-feed-prefix \
  "Sparkle feed Ed25519 signature verification failed" \
  "$CASE_DIR"

CASE_DIR="$(make_case mismatched-embedded-public-key)"
rm -f "$CASE_DIR/Dev-Island.zip" "$CASE_DIR/Dev-Island-${VERSION}.zip"
write_fixture_archive "$CASE_DIR/Dev-Island.zip" "$MISMATCHED_PUBLIC_KEY"
cp "$CASE_DIR/Dev-Island.zip" "$CASE_DIR/Dev-Island-${VERSION}.zip"
write_signed_appcast "$CASE_DIR"
MISMATCHED_ZIP_SHA="$(shasum -a 256 "$CASE_DIR/Dev-Island.zip" | awk '{print $1}')"
VERSION="$VERSION" SHA256="$MISMATCHED_ZIP_SHA" OUTPUT="$CASE_DIR/dev-island.rb" \
  ./scripts/render-homebrew-cask.sh >/dev/null
refresh_manifest "$CASE_DIR"
expect_failure mismatched-embedded-public-key \
  "Sparkle archive Ed25519 signature verification failed" \
  "$CASE_DIR"

CASE_DIR="$(make_case malformed-sbom)"
printf '{not-json}\n' >"$CASE_DIR/Dev-Island.spdx.json"
refresh_manifest "$CASE_DIR"
expect_failure malformed-sbom "SPDX SBOM is not valid JSON" "$CASE_DIR"

CASE_DIR="$(make_case wrong-sbom-version)"
ruby - "$CASE_DIR/Dev-Island.spdx.json" "$VERSION" <<'RUBY'
path, version = ARGV
contents = File.binread(path).sub("Dev-Island-#{version}-SBOM", "Dev-Island-9.9.9-SBOM")
File.binwrite(path, contents)
RUBY
refresh_manifest "$CASE_DIR"
expect_failure wrong-sbom-version "SPDX SBOM name does not match" "$CASE_DIR"

CASE_DIR="$(make_case missing-opencode-brand-component)"
ruby -r json - "$CASE_DIR/Dev-Island.spdx.json" <<'RUBY'
path = ARGV.fetch(0)
document = JSON.parse(File.binread(path))
document.fetch("packages").reject! { |package| package["name"] == "opencode-logo-dark-square" }
document.fetch("relationships").reject! do |relationship|
  relationship["relatedSpdxElement"] == "SPDXRef-Package-opencode-brand-square"
end
File.binwrite(path, JSON.pretty_generate(document) + "\n")
RUBY
refresh_manifest "$CASE_DIR"
expect_failure missing-opencode-brand-component \
  "SPDX SBOM must inventory all nine reviewed Agent brand assets exactly once" \
  "$CASE_DIR"

CASE_DIR="$(make_case tampered-opencode-brand-hash)"
ruby -r json - "$CASE_DIR/Dev-Island.spdx.json" <<'RUBY'
path = ARGV.fetch(0)
document = JSON.parse(File.binread(path))
component = document.fetch("packages").find do |package|
  package["name"] == "opencode-logo-dark-square"
end
abort "missing fixture component" unless component
component["sourceInfo"] = component.fetch("sourceInfo").sub(
  /source SVG SHA-256 [0-9a-f]{64}/,
  "source SVG SHA-256 #{"0" * 64}"
)
File.binwrite(path, JSON.pretty_generate(document) + "\n")
RUBY
refresh_manifest "$CASE_DIR"
expect_failure tampered-opencode-brand-hash \
  "SPDX SBOM brand source hash is missing: opencode" \
  "$CASE_DIR"

CASE_DIR="$(make_case tampered-packaged-brand-hash)"
ruby -r json - "$CASE_DIR/Dev-Island.spdx.json" <<'RUBY'
path = ARGV.fetch(0)
document = JSON.parse(File.binread(path))
component = document.fetch("packages").find do |package|
  package["SPDXID"] == "SPDXRef-Package-agent-brand-codex"
end
abort "missing fixture component" unless component
component["sourceInfo"] = component.fetch("sourceInfo").sub(
  /AgentLogo-codex\.png=[0-9a-f]{64}/,
  "AgentLogo-codex.png=#{"0" * 64}"
)
File.binwrite(path, JSON.pretty_generate(document) + "\n")
RUBY
refresh_manifest "$CASE_DIR"
expect_failure tampered-packaged-brand-hash \
  "SPDX SBOM packaged brand hash is missing: AgentLogo-codex.png" \
  "$CASE_DIR"

CASE_DIR="$(make_case wrong-source-revision)"
# Directly exercise the optional tagged-commit binding with another valid
# 40-character SHA; all other metadata remains internally consistent.
if "$VERIFIER" --tag "$TAG" --asset-dir "$CASE_DIR" \
  --source-revision "$(printf 'd%.0s' {1..40})" >"$TEMP_DIR/wrong-source.output" 2>&1; then
  fail "Wrong tagged source revision unexpectedly passed"
fi
rg -Fq "SPDX SBOM source revision does not match" "$TEMP_DIR/wrong-source.output" \
  || fail "Wrong tagged source revision failed for the wrong reason"

CASE_DIR="$(make_case unexpected-asset)"
printf 'unexpected' >"$CASE_DIR/notes.txt"
expect_failure unexpected-asset "unexpected release asset or directory: notes.txt" "$CASE_DIR"

echo "Release asset verifier fixtures: PASS"
