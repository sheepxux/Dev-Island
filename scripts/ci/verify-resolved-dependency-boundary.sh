#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

BUILD_SCRIPT="scripts/build-app.sh"
CI_WORKFLOW=".github/workflows/ci.yml"
RELEASE_WORKFLOW=".github/workflows/release.yml"
RESOLVED_FILE="Package.resolved"
AUTHORITATIVE_TESTS="scripts/ci/run-authoritative-tests.sh"

test -f "$RESOLVED_FILE" && test ! -L "$RESOLVED_FILE" \
  || fail "Package.resolved must be a regular non-symlink file"
resolved_bytes="$(stat -f '%z' "$RESOLVED_FILE")"
[[ "$resolved_bytes" -ge 1 && "$resolved_bytes" -le 1048576 ]] \
  || fail "Package.resolved must be between 1 byte and 1 MiB"

ruby -r json - "$RESOLVED_FILE" <<'RUBY'
document = JSON.parse(File.binread(ARGV.fetch(0)))
abort "Package.resolved schema mismatch" unless document["version"] == 3
pins = document["pins"]
abort "Package.resolved pin set is invalid" unless pins.is_a?(Array) && pins.length.between?(1, 256)
identities = pins.map { |pin| pin["identity"] }
abort "Package.resolved identities are invalid" unless identities.all? { |value| value.is_a?(String) && value.match?(/\A[a-z0-9._-]{1,128}\z/) }
abort "Package.resolved contains duplicate identities" unless identities.uniq.length == identities.length
pins.each do |pin|
  state = pin["state"]
  abort "Package.resolved pin state is invalid" unless state.is_a?(Hash)
  revision = state["revision"]
  abort "Package.resolved revision is invalid" unless revision.is_a?(String) && revision.match?(/\A[0-9a-f]{40}\z/)
  version = state["version"]
  abort "Package.resolved version is invalid" unless version.is_a?(String) && version.match?(/\A[0-9A-Za-z.+-]{1,64}\z/)
end
RUBY

[[ "$(rg -F --count-matches -- '--only-use-versions-from-resolved-file' "$BUILD_SCRIPT")" -eq 2 ]] \
  || fail "Both architecture builds must force Package.resolved"
test -x "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative test runner is missing or not executable"
rg -Fq -- '--only-use-versions-from-resolved-file' "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative tests must force Package.resolved"
for invariant in \
  'PACKAGE_RESOLVED_BYTES' \
  'Package.resolved must be a regular non-symlink file' \
  'Package.resolved changed type during the Universal build' \
  'Package.resolved changed during the Universal build'; do
  rg -Fq "$invariant" "$BUILD_SCRIPT" \
    || fail "App build lock-file boundary is missing: $invariant"
done

for workflow in "$CI_WORKFLOW" "$RELEASE_WORKFLOW"; do
  rg -Fq 'git ls-files --error-unmatch Package.resolved' "$workflow" \
    || fail "Workflow must reject an untracked lock file: $workflow"
  rg -Fq 'test -f Package.resolved && test ! -L Package.resolved' "$workflow" \
    || fail "Workflow must reject a missing or linked lock file: $workflow"
  rg -Fq './scripts/ci/run-authoritative-tests.sh' "$workflow" \
    || fail "Workflow must use the Package.resolved-bound authoritative test runner: $workflow"
done

TEMP_ROOT="$(mktemp -d -t dev-island-resolved-boundary)"
cleanup() {
  [[ "$TEMP_ROOT" == /private/var/folders/*/T/dev-island-resolved-boundary.* \
     || "$TEMP_ROOT" == /var/folders/*/T/dev-island-resolved-boundary.* \
     || "$TEMP_ROOT" == /tmp/dev-island-resolved-boundary.* ]] \
    && rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

# Exercise the build script's file boundary before SwiftPM can run.
for case_name in missing linked empty oversized; do
  fixture="$TEMP_ROOT/build-$case_name"
  mkdir -p "$fixture/scripts/release"
  cp "$BUILD_SCRIPT" "$fixture/scripts/build-app.sh"
  cp scripts/release/validate-product-version.rb \
    "$fixture/scripts/release/validate-product-version.rb"
  cp scripts/release/app-build-output-boundary.rb \
    "$fixture/scripts/release/app-build-output-boundary.rb"
  cp scripts/release/verify-legal-documents.rb \
    "$fixture/scripts/release/verify-legal-documents.rb"
  cp PRIVACY.md TERMS.md "$fixture/"
  chmod +x "$fixture/scripts/build-app.sh"
  chmod +x "$fixture/scripts/release/validate-product-version.rb"
  chmod +x "$fixture/scripts/release/app-build-output-boundary.rb"
  chmod +x "$fixture/scripts/release/verify-legal-documents.rb"
  printf '0.3.0\n' >"$fixture/VERSION"
  case "$case_name" in
    missing)
      ;;
    linked)
      printf '{}\n' >"$fixture/real-resolved.json"
      ln -s real-resolved.json "$fixture/Package.resolved"
      ;;
    empty)
      : >"$fixture/Package.resolved"
      ;;
    oversized)
      dd if=/dev/zero of="$fixture/Package.resolved" bs=1048577 count=1 2>/dev/null
      ;;
  esac
  if "$fixture/scripts/build-app.sh" >"$fixture/output.log" 2>&1; then
    fail "Unsafe Package.resolved fixture unexpectedly reached the build: $case_name"
  fi
  rg -q 'Package\.resolved must be' "$fixture/output.log" \
    || fail "Unsafe lock-file fixture failed for the wrong reason: $case_name"
done

# Prove the SwiftPM semantic difference without network access. The consumer
# first resolves a local tagged dependency at 1.0.0. Changing its manifest to
# exact 1.1.0 must fail under force-resolved mode while ordinary resolution
# would silently rewrite Package.resolved to the newer tag.
DEPENDENCY="$TEMP_ROOT/dependency"
CONSUMER="$TEMP_ROOT/consumer"
SCRATCH="$TEMP_ROOT/scratch"
mkdir -p "$DEPENDENCY/Sources/LockedDependency" "$CONSUMER/Sources/Fixture"
cat >"$DEPENDENCY/Package.swift" <<'SWIFT'
// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "LockedDependency",
    products: [.library(name: "LockedDependency", targets: ["LockedDependency"])],
    targets: [.target(name: "LockedDependency")]
)
SWIFT
printf 'public let lockedVersion = "1.0.0"\n' \
  >"$DEPENDENCY/Sources/LockedDependency/LockedDependency.swift"
git -C "$DEPENDENCY" init -q
git -C "$DEPENDENCY" config user.name "Dev Island Fixture"
git -C "$DEPENDENCY" config user.email "fixture@devisland.invalid"
git -C "$DEPENDENCY" add Package.swift Sources
git -C "$DEPENDENCY" commit -q -m "v1.0.0"
git -C "$DEPENDENCY" tag 1.0.0
printf 'public let lockedVersion = "1.1.0"\n' \
  >"$DEPENDENCY/Sources/LockedDependency/LockedDependency.swift"
git -C "$DEPENDENCY" add Sources
git -C "$DEPENDENCY" commit -q -m "v1.1.0"
git -C "$DEPENDENCY" tag 1.1.0

cat >"$CONSUMER/Package.swift" <<'SWIFT'
// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "ResolvedBoundaryFixture",
    dependencies: [
        .package(url: "file://DEPENDENCY_PATH", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Fixture",
            dependencies: [.product(name: "LockedDependency", package: "dependency")]
        ),
    ]
)
SWIFT
ruby -e \
  'path, dependency = ARGV; data = File.binread(path); File.binwrite(path, data.sub("DEPENDENCY_PATH", dependency))' \
  "$CONSUMER/Package.swift" "$DEPENDENCY"
cat >"$CONSUMER/Sources/Fixture/main.swift" <<'SWIFT'
import LockedDependency
print(lockedVersion)
SWIFT

swift package --package-path "$CONSUMER" --disable-keychain \
  --scratch-path "$SCRATCH" resolve >/dev/null
swift build --package-path "$CONSUMER" --disable-keychain \
  --scratch-path "$SCRATCH" \
  --only-use-versions-from-resolved-file >/dev/null
locked_hash="$(shasum -a 256 "$CONSUMER/Package.resolved" | awk '{print $1}')"
ruby -e \
  'path = ARGV.fetch(0); data = File.binread(path); File.binwrite(path, data.sub(%q{exact: "1.0.0"}, %q{exact: "1.1.0"}))' \
  "$CONSUMER/Package.swift"

if swift build --package-path "$CONSUMER" --disable-keychain \
  --scratch-path "$SCRATCH" \
  --only-use-versions-from-resolved-file \
  >"$TEMP_ROOT/forced-resolution.log" 2>&1; then
  fail "Force-resolved SwiftPM build accepted an out-of-date lock file"
fi
[[ "$(shasum -a 256 "$CONSUMER/Package.resolved" | awk '{print $1}')" == "$locked_hash" ]] \
  || fail "Force-resolved failure modified Package.resolved"
rg -qi 'resolved|1\.1\.0' "$TEMP_ROOT/forced-resolution.log" \
  || fail "Force-resolved fixture failed without identifying dependency resolution"

swift package --package-path "$CONSUMER" --disable-keychain \
  --scratch-path "$SCRATCH" resolve >/dev/null
[[ "$(shasum -a 256 "$CONSUMER/Package.resolved" | awk '{print $1}')" != "$locked_hash" ]] \
  || fail "Ordinary dependency resolution did not demonstrate lock-file drift"

echo "Resolved dependency boundary: PASS"
