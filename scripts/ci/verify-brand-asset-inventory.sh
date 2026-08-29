#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERIFIER="scripts/release/verify-brand-assets.rb"
MANIFEST="scripts/assets/agent-logos/manifest.json"
TRADEMARK_REVIEWS="scripts/assets/agent-logos/trademark-reviews.json"
SOURCE_DIR="scripts/assets/agent-logos"
BUNDLE_DIR="IslandApp/Resources"
LICENSES_DIR="scripts/licenses"

fail() {
  echo "::error::$1" >&2
  exit 1
}

test -x "$VERIFIER" || fail "Brand asset verifier is missing or not executable"

run_verifier() {
  "$VERIFIER" \
    --manifest "$1/manifest.json" \
    --trademark-reviews "$1/trademark-reviews.json" \
    --source-dir "$1/sources" \
    --bundle-dir "$1/bundle" \
    --licenses-dir "$1/licenses" \
    "${@:2}"
}

TEMP_DIR="$(mktemp -d -t dev-island-brand-assets)"
case "$TEMP_DIR" in
  /private/var/folders/*/T/dev-island-brand-assets.*|/var/folders/*/T/dev-island-brand-assets.*|/tmp/dev-island-brand-assets.*) ;;
  *) fail "Refusing to use unexpected temporary path" ;;
esac
trap 'rm -rf "$TEMP_DIR"' EXIT

make_case() {
  local name="$1"
  local directory="$TEMP_DIR/$name"
  mkdir -p "$directory/sources" "$directory/bundle" "$directory/licenses"
  cp "$MANIFEST" "$directory/manifest.json"
  cp "$TRADEMARK_REVIEWS" "$directory/trademark-reviews.json"
  cp "$SOURCE_DIR"/*.svg "$directory/sources/"
  cp "$BUNDLE_DIR"/AgentLogo-*.png "$directory/bundle/"
  cp "$LICENSES_DIR"/* "$directory/licenses/"
  printf '%s\n' "$directory"
}

approve_all_reviews() {
  local directory="$1"
  local region="$2"
  ruby -r json - "$directory/manifest.json" "$directory/trademark-reviews.json" "$region" <<'RUBY'
manifest_path, reviews_path, region = ARGV
manifest = JSON.parse(File.binread(manifest_path))
manifest.fetch("assets").each { |asset| asset["trademarkReview"] = "approved" }
File.binwrite(manifest_path, JSON.pretty_generate(manifest) + "\n")

document = JSON.parse(File.binread(reviews_path))
document.fetch("reviews").each do |review|
  review["decision"] = "approved"
  review["reviewedAt"] = "2026-08-27T00:00:00Z"
  review["reviewedBy"] = "Fixture reviewer"
  review["reviewerRole"] = "Fixture legal reviewer"
  review["authorityReference"] = "FIXTURE-TRADEMARK-REVIEW"
  review["evidenceReference"] = "sha256:#{"0" * 64}"
  review["salesRegions"] = [region]
  review["distributionChannels"] = %w[direct-download github-release homebrew]
end
File.binwrite(reviews_path, JSON.pretty_generate(document) + "\n")
RUBY
}

expect_failure() {
  local name="$1"
  local expected="$2"
  local directory="$3"
  shift 3
  if run_verifier "$directory" "$@" >"$TEMP_DIR/$name.output" 2>&1; then
    fail "$name unexpectedly passed"
  fi
  rg -Fq "$expected" "$TEMP_DIR/$name.output" \
    || fail "$name failed for the wrong reason"
}

VALID="$(make_case valid)"
run_verifier "$VALID" >/dev/null

TAMPERED_SOURCE="$(make_case tampered-source)"
printf 'tampered' >>"$TAMPERED_SOURCE/sources/codex.svg"
expect_failure tampered-source "brand source SHA-256 mismatch: codex" "$TAMPERED_SOURCE"

TAMPERED_BUNDLE="$(make_case tampered-bundle)"
printf 'tampered' >>"$TAMPERED_BUNDLE/bundle/AgentLogo-qwen-code@2x.png"
expect_failure tampered-bundle \
  "brand bundle SHA-256 mismatch: AgentLogo-qwen-code@2x.png" \
  "$TAMPERED_BUNDLE"

TAMPERED_NOTICE="$(make_case tampered-notice)"
printf 'tampered' >>"$TAMPERED_NOTICE/licenses/kimi-code-vscode-Apache-2.0-LICENSE"
expect_failure tampered-notice \
  "brand notice SHA-256 mismatch: kimi-code" \
  "$TAMPERED_NOTICE"

TAMPERED_UPSTREAM_HASH="$(make_case tampered-upstream-hash)"
ruby -r json - "$TAMPERED_UPSTREAM_HASH/manifest.json" <<'RUBY'
path = ARGV.fetch(0)
manifest = JSON.parse(File.binread(path))
manifest.fetch("assets").find { |asset| asset.fetch("id") == "claude-code" }
  .fetch("upstream")["sha256"] = "0" * 64
File.binwrite(path, JSON.pretty_generate(manifest) + "\n")
RUBY
expect_failure tampered-upstream-hash \
  "brand upstream SHA-256 mismatch after transform: claude-code" \
  "$TAMPERED_UPSTREAM_HASH"

TAMPERED_TRANSFORM="$(make_case tampered-transform)"
ruby -r json - "$TAMPERED_TRANSFORM/manifest.json" <<'RUBY'
path = ARGV.fetch(0)
manifest = JSON.parse(File.binread(path))
manifest.fetch("assets").find { |asset| asset.fetch("id") == "codex" }
  .fetch("upstream")["transform"] = "unreviewed-transform"
File.binwrite(path, JSON.pretty_generate(manifest) + "\n")
RUBY
expect_failure tampered-transform \
  "brand upstream transform is invalid: codex" \
  "$TAMPERED_TRANSFORM"

UNREPRESENTED="$(make_case unrepresented-source)"
cp "$UNREPRESENTED/sources/codex.svg" "$UNREPRESENTED/sources/unreviewed.svg"
expect_failure unrepresented-source \
  "brand source directory is not exactly represented by the manifest" \
  "$UNREPRESENTED"

SYMLINK_SOURCE="$(make_case symlink-source)"
rm "$SYMLINK_SOURCE/sources/manus.svg"
ln -s codex.svg "$SYMLINK_SOURCE/sources/manus.svg"
expect_failure symlink-source \
  "input must be a regular non-symlink file" \
  "$SYMLINK_SOURCE"

TAMPERED_REVIEW="$(make_case tampered-review)"
ruby -r json - "$TAMPERED_REVIEW/trademark-reviews.json" <<'RUBY'
path = ARGV.fetch(0)
document = JSON.parse(File.binread(path))
review = document.fetch("reviews").find { |item| item.fetch("id") == "codex" }
review["assetFingerprintSHA256"] = "0" * 64
File.binwrite(path, JSON.pretty_generate(document) + "\n")
RUBY
expect_failure tampered-review \
  "trademark review asset fingerprint mismatch: codex" \
  "$TAMPERED_REVIEW"

MANIFEST_ONLY_APPROVAL="$(make_case manifest-only-approval)"
ruby -r json - "$MANIFEST_ONLY_APPROVAL/manifest.json" <<'RUBY'
path = ARGV.fetch(0)
manifest = JSON.parse(File.binread(path))
asset = manifest.fetch("assets").find { |item| item.fetch("id") == "codex" }
asset["trademarkReview"] = "approved"
File.binwrite(path, JSON.pretty_generate(manifest) + "\n")
RUBY
expect_failure manifest-only-approval \
  "brand manifest and trademark review decision disagree: codex" \
  "$MANIFEST_ONLY_APPROVAL"

PARTIAL_APPROVAL="$(make_case partial-approval)"
ruby -r json - "$PARTIAL_APPROVAL/manifest.json" "$PARTIAL_APPROVAL/trademark-reviews.json" <<'RUBY'
manifest_path, reviews_path = ARGV
manifest = JSON.parse(File.binread(manifest_path))
asset = manifest.fetch("assets").find { |item| item.fetch("id") == "codex" }
asset["trademarkReview"] = "approved"
File.binwrite(manifest_path, JSON.pretty_generate(manifest) + "\n")
document = JSON.parse(File.binread(reviews_path))
review = document.fetch("reviews").find { |item| item.fetch("id") == "codex" }
review["decision"] = "approved"
File.binwrite(reviews_path, JSON.pretty_generate(document) + "\n")
RUBY
expect_failure partial-approval \
  "trademark review evidence is incomplete: codex" \
  "$PARTIAL_APPROVAL"

SCOPED_APPROVAL="$(make_case scoped-approval)"
approve_all_reviews "$SCOPED_APPROVAL" US
run_verifier "$SCOPED_APPROVAL" >/dev/null
expect_failure scoped-release-review \
  "commercial Release blocked by unreviewed brand assets" \
  "$SCOPED_APPROVAL" \
  --require-release-reviewed

WORLDWIDE_APPROVAL="$(make_case worldwide-approval)"
approve_all_reviews "$WORLDWIDE_APPROVAL" WORLDWIDE
run_verifier "$WORLDWIDE_APPROVAL" --require-release-reviewed >/dev/null

SYMLINK_REVIEW="$(make_case symlink-review)"
rm "$SYMLINK_REVIEW/trademark-reviews.json"
ln -s manifest.json "$SYMLINK_REVIEW/trademark-reviews.json"
expect_failure symlink-review \
  "input must be a regular non-symlink file" \
  "$SYMLINK_REVIEW"

expect_failure release-review \
  "commercial Release blocked by unreviewed brand assets" \
  "$VALID" \
  --require-release-reviewed

echo "Brand asset inventory fixtures: PASS"
