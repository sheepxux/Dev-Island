#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

GENERATOR="scripts/release/generate-trademark-review-packet.rb"
FIXTURE_PNG="IslandApp/Resources/AgentLogo-codex.png"
SCREENSHOT_NAMES=(
  "02-welcome-step.png"
  "20-priority-panel.png"
  "31-session-history.png"
  "61-agent-brand-badges.png"
)

test -x "$GENERATOR" || fail "Trademark review packet generator is missing or not executable"
test -f "$FIXTURE_PNG" && test ! -L "$FIXTURE_PNG" \
  || fail "Trademark packet PNG fixture is missing or symbolic"

TEMP_DIR="$(mktemp -d -t dev-island-trademark-packet)"
cleanup() {
  [[ "$TEMP_DIR" == /private/var/folders/*/T/dev-island-trademark-packet.* \
     || "$TEMP_DIR" == /var/folders/*/T/dev-island-trademark-packet.* \
     || "$TEMP_DIR" == /tmp/dev-island-trademark-packet.* ]] \
    && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

make_screenshots() {
  local directory="$1"
  mkdir -p "$directory"
  local screenshot
  for screenshot in "${SCREENSHOT_NAMES[@]}"; do
    cp "$FIXTURE_PNG" "$directory/$screenshot"
  done
}

expect_failure() {
  local label="$1"
  local expected="$2"
  shift 2
  local output="$TEMP_DIR/$label.log"
  if "$@" >"$output" 2>&1; then
    fail "Trademark packet attack fixture unexpectedly passed: $label"
  fi
  rg -Fq "$expected" "$output" \
    || fail "Trademark packet attack fixture failed for the wrong reason: $label"
}

SCREENSHOTS="$TEMP_DIR/screenshots"
make_screenshots "$SCREENSHOTS"

VALID_A="$TEMP_DIR/valid-a"
VALID_B="$TEMP_DIR/valid-b"
"$GENERATOR" --screenshots-dir "$SCREENSHOTS" --output-dir "$VALID_A" >/dev/null
"$GENERATOR" --screenshots-dir "$SCREENSHOTS" --output-dir "$VALID_B" >/dev/null

diff -qr "$VALID_A" "$VALID_B" >/dev/null \
  || fail "Trademark review packet generation is not deterministic"
if find "$VALID_A" -type l | rg -q .; then
  fail "Trademark review packet contains a symbolic link"
fi
test "$(find "$VALID_A/assets/source" -type f | wc -l | tr -d ' ')" = 9 \
  || fail "Trademark review packet source inventory is incomplete"
test "$(find "$VALID_A/assets/rendered" -type f | wc -l | tr -d ' ')" = 18 \
  || fail "Trademark review packet rendered inventory is incomplete"
test "$(find "$VALID_A/notices" -type f | wc -l | tr -d ' ')" = 5 \
  || fail "Trademark review packet notice inventory is incomplete"
test "$(find "$VALID_A/screenshots" -type f | wc -l | tr -d ' ')" = 4 \
  || fail "Trademark review packet screenshot inventory is incomplete"
test "$(find "$VALID_A" -type f | wc -l | tr -d ' ')" = 42 \
  || fail "Trademark review packet contains missing or extra files"
cmp scripts/assets/agent-logos/manifest.json "$VALID_A/records/manifest.json" \
  || fail "Trademark review packet manifest copy drifted"
cmp scripts/assets/agent-logos/trademark-reviews.json "$VALID_A/records/trademark-reviews.json" \
  || fail "Trademark review packet decision record copy drifted"
(
  cd "$VALID_A"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "Trademark review packet SHA256SUMS did not verify"

jq -e '
  .schemaVersion == 1 and
  .status == "review-input-not-approval" and
  (.assets | length) == 9 and
  ([.assets[].decision] | all(. == "required")) and
  (.screenshots | length) == 4
' "$VALID_A/PACKET-MANIFEST.json" >/dev/null \
  || fail "Trademark review packet manifest is incomplete or overstates approval"

while IFS= read -r fingerprint; do
  rg -Fq "$fingerprint" "$VALID_A/TRADEMARK_REVIEW_FORM.md" \
    || fail "Trademark review form is missing a bound asset fingerprint"
done < <(jq -r '.reviews[].assetFingerprintSHA256' scripts/assets/agent-logos/trademark-reviews.json)

expect_failure existing-output \
  "output directory already exists; refusing to overwrite" \
  "$GENERATOR" --screenshots-dir "$SCREENSHOTS" --output-dir "$VALID_A"

MISSING_SCREENSHOTS="$TEMP_DIR/missing-screenshots"
make_screenshots "$MISSING_SCREENSHOTS"
rm "$MISSING_SCREENSHOTS/31-session-history.png"
expect_failure missing-screenshot \
  "review screenshot is missing" \
  "$GENERATOR" --screenshots-dir "$MISSING_SCREENSHOTS" --output-dir "$TEMP_DIR/missing-output"

SYMLINK_SCREENSHOTS="$TEMP_DIR/symlink-screenshots"
make_screenshots "$SYMLINK_SCREENSHOTS"
rm "$SYMLINK_SCREENSHOTS/61-agent-brand-badges.png"
ln -s "$FIXTURE_PNG" "$SYMLINK_SCREENSHOTS/61-agent-brand-badges.png"
expect_failure symlink-screenshot \
  "review screenshot must be a regular non-symlink file" \
  "$GENERATOR" --screenshots-dir "$SYMLINK_SCREENSHOTS" --output-dir "$TEMP_DIR/symlink-output"

INVALID_SCREENSHOTS="$TEMP_DIR/invalid-screenshots"
make_screenshots "$INVALID_SCREENSHOTS"
printf 'not-a-png' >"$INVALID_SCREENSHOTS/20-priority-panel.png"
expect_failure invalid-screenshot \
  "review screenshot is not a PNG" \
  "$GENERATOR" --screenshots-dir "$INVALID_SCREENSHOTS" --output-dir "$TEMP_DIR/invalid-output"

REAL_PARENT="$TEMP_DIR/real-parent"
SYMLINK_PARENT="$TEMP_DIR/symlink-parent"
mkdir -p "$REAL_PARENT"
ln -s "$REAL_PARENT" "$SYMLINK_PARENT"
expect_failure symlink-output-parent \
  "output parent must be a regular non-symlink directory" \
  "$GENERATOR" --screenshots-dir "$SCREENSHOTS" --output-dir "$SYMLINK_PARENT/packet"

TAMPERED="$TEMP_DIR/tampered"
cp -R "$VALID_A" "$TAMPERED"
printf 'tampered' >>"$TAMPERED/screenshots/02-welcome-step.png"
if (
  cd "$TAMPERED"
  shasum -a 256 -c SHA256SUMS >/dev/null 2>&1
); then
  fail "Trademark review packet checksum accepted tampered evidence"
fi

echo "Trademark review packet fixtures: PASS"
