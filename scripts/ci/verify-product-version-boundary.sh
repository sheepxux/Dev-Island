#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

VALIDATOR="scripts/release/validate-product-version.rb"
BUILD_SCRIPT="scripts/build-app.sh"
CI_WORKFLOW=".github/workflows/ci.yml"
RELEASE_WORKFLOW=".github/workflows/release.yml"

test -x "$VALIDATOR" || fail "Executable product-version validator is missing"
ruby -c "$VALIDATOR" >/dev/null || fail "Product-version validator is not valid Ruby"
[[ "$("$VALIDATOR" --version-file VERSION)" == "0.4.0" ]] \
  || fail "Repository VERSION did not validate"

for valid in 0.0.0 1.2.3 9999.99.99; do
  [[ "$("$VALIDATOR" --version "$valid")" == "$valid" ]] \
    || fail "Canonical version was rejected: $valid"
done

for invalid in \
  "" \
  "v1.2.3" \
  "01.2.3" \
  "1.02.3" \
  "1.2.03" \
  "10000.1.1" \
  "1.100.1" \
  "1.1.100" \
  "1.2" \
  "1.2.3.4" \
  "1.2.3-beta" \
  "1.2.3&injected" \
  "1/2/3" \
  "1.2.3 "; do
  if "$VALIDATOR" --version "$invalid" >/dev/null 2>&1; then
    fail "Invalid product version was accepted: $invalid"
  fi
done

TEMP_ROOT="$(mktemp -d -t dev-island-product-version)"
cleanup() {
  [[ "$TEMP_ROOT" == /private/var/folders/*/T/dev-island-product-version.* \
     || "$TEMP_ROOT" == /var/folders/*/T/dev-island-product-version.* \
     || "$TEMP_ROOT" == /tmp/dev-island-product-version.* ]] \
    && rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

expect_file_rejection() {
  local label="$1"
  local version_path="$2"
  if "$VALIDATOR" --version-file "$version_path" >"$TEMP_ROOT/$label.log" 2>&1; then
    fail "Unsafe VERSION file was accepted: $label"
  fi
  rg -q 'VERSION' "$TEMP_ROOT/$label.log" \
    || fail "Unsafe VERSION file failed without a bounded diagnostic: $label"
}

expect_file_rejection missing "$TEMP_ROOT/missing"
mkdir "$TEMP_ROOT/directory"
expect_file_rejection directory "$TEMP_ROOT/directory"
: >"$TEMP_ROOT/empty"
expect_file_rejection empty "$TEMP_ROOT/empty"
printf '1.2.3' >"$TEMP_ROOT/no-newline"
expect_file_rejection no-newline "$TEMP_ROOT/no-newline"
printf '1.2.3\n\n' >"$TEMP_ROOT/extra-newline"
expect_file_rejection extra-newline "$TEMP_ROOT/extra-newline"
printf '1.2.3\n2.0.0\n' >"$TEMP_ROOT/multiple-lines"
expect_file_rejection multiple-lines "$TEMP_ROOT/multiple-lines"
printf '1.2.3-beta\n' >"$TEMP_ROOT/prerelease"
expect_file_rejection prerelease "$TEMP_ROOT/prerelease"
printf '1.2.3&{{BUILD}}\n' >"$TEMP_ROOT/sed-injection"
expect_file_rejection sed-injection "$TEMP_ROOT/sed-injection"
printf '1.2.3\n' >"$TEMP_ROOT/group-writable"
chmod 0664 "$TEMP_ROOT/group-writable"
expect_file_rejection group-writable "$TEMP_ROOT/group-writable"
printf '1.2.3\n' >"$TEMP_ROOT/hard-link-source"
ln "$TEMP_ROOT/hard-link-source" "$TEMP_ROOT/hard-link"
expect_file_rejection hard-link "$TEMP_ROOT/hard-link"
printf '1.2.3\n' >"$TEMP_ROOT/symlink-target"
ln -s symlink-target "$TEMP_ROOT/symlink"
expect_file_rejection symlink "$TEMP_ROOT/symlink"
dd if=/dev/zero of="$TEMP_ROOT/oversized" bs=65 count=1 2>/dev/null
expect_file_rejection oversized "$TEMP_ROOT/oversized"

for invariant in \
  'validate-product-version.rb' \
  '--version-file' \
  'product-version validator is missing or not executable'; do
  rg -Fq -- "$invariant" "$BUILD_SCRIPT" \
    || fail "App build version boundary is missing: $invariant"
done
if rg -Fq 'echo "0.1.0"' "$BUILD_SCRIPT"; then
  fail "App build must never silently substitute a fallback product version"
fi

for workflow in "$CI_WORKFLOW" "$RELEASE_WORKFLOW"; do
  rg -Fq 'validate-product-version.rb' "$workflow" \
    || fail "Workflow does not use the shared product-version boundary: $workflow"
done
for release_tool in \
  scripts/render-homebrew-cask.sh \
  scripts/release/generate-release-integrity-manifest.sh \
  scripts/release/verify-release-assets.sh \
  scripts/release/verify-published-release.sh; do
  rg -Fq 'validate-product-version.rb' "$release_tool" \
    || fail "Release tool bypasses the shared product-version boundary: $release_tool"
done

echo "Product version boundary: PASS"
