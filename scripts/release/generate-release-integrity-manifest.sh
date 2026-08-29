#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION_VALIDATOR="$ROOT/scripts/release/validate-product-version.rb"

fail() {
  echo "::error::$1" >&2
  exit 1
}

: "${VERSION:?VERSION is required}"
test -x "$VERSION_VALIDATOR" || fail "product-version validator is missing"
VERSION="$("$VERSION_VALIDATOR" --version "$VERSION")"

BUILD_DIR="${BUILD_DIR:-build}"
[[ -d "$BUILD_DIR" ]] || fail "Release build directory does not exist"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd -P)"
OUTPUT="$BUILD_DIR/SHA256SUMS"

ARTIFACTS=(
  "Dev-Island.dmg"
  "Dev-Island-${VERSION}.dmg"
  "Dev-Island.zip"
  "Dev-Island-${VERSION}.zip"
  "Dev-Island.spdx.json"
  "appcast.xml"
  "dev-island.rb"
)

for artifact in "${ARTIFACTS[@]}"; do
  path="$BUILD_DIR/$artifact"
  [[ -f "$path" ]] || fail "Release artifact is missing: $artifact"
  [[ ! -L "$path" ]] || fail "Release artifact must not be a symbolic link: $artifact"
done

# Stable and versioned names are two download aliases for the same bytes. A
# mismatch would make the website, Cask, release notes, and Sparkle describe
# different builds even if every individual checksum were technically valid.
cmp -s "$BUILD_DIR/Dev-Island.dmg" "$BUILD_DIR/Dev-Island-${VERSION}.dmg" \
  || fail "Stable and versioned DMG bytes differ"
cmp -s "$BUILD_DIR/Dev-Island.zip" "$BUILD_DIR/Dev-Island-${VERSION}.zip" \
  || fail "Stable and versioned ZIP bytes differ"

TEMP_OUTPUT="$(mktemp "$BUILD_DIR/.SHA256SUMS.XXXXXX")"
cleanup() {
  rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT

(
  cd "$BUILD_DIR"
  for artifact in "${ARTIFACTS[@]}"; do
    shasum -a 256 "$artifact"
  done | LC_ALL=C sort -k2
) >"$TEMP_OUTPUT"

[[ "$(wc -l <"$TEMP_OUTPUT" | tr -d ' ')" -eq "${#ARTIFACTS[@]}" ]] \
  || fail "Release integrity manifest is incomplete"
chmod 0644 "$TEMP_OUTPUT"

# Verify the temporary file before atomically replacing the public manifest.
# A failed rerun therefore leaves the last known-good SHA256SUMS untouched.
(
  cd "$BUILD_DIR"
  shasum -a 256 -c "$(basename "$TEMP_OUTPUT")" >/dev/null
) || fail "Generated release integrity manifest did not verify"

mv -f "$TEMP_OUTPUT" "$OUTPUT"
trap - EXIT

echo "Release integrity manifest: $OUTPUT"
