#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

BUILD_ROOT="$ROOT/.build"
TEST_SCRATCH="$ROOT/.build/tests-authoritative"
TEST_LOCK="$ROOT/.build/tests-authoritative.lock"

validate_directory() {
  local path="$1"
  local label="$2"
  local owner permissions

  [[ -d "$path" && ! -L "$path" ]] \
    || fail "$label must be a regular directory"
  owner="$(stat -f '%u' "$path")"
  permissions="$(stat -f '%Lp' "$path")"
  [[ "$owner" == "$(id -u)" ]] \
    || fail "$label must be owned by the current user"
  [[ "$permissions" =~ ^[0-7]{3,4}$ ]] \
    || fail "$label permissions could not be validated"
  (( (8#$permissions & 8#022) == 0 )) \
    || fail "$label must not be group/other writable"
}

if [[ -L "$BUILD_ROOT" ]]; then
  fail "SwiftPM build root must not be a symbolic link"
elif [[ -e "$BUILD_ROOT" ]]; then
  validate_directory "$BUILD_ROOT" "SwiftPM build root"
else
  mkdir -m 700 "$BUILD_ROOT"
fi

if [[ -L "$TEST_SCRATCH" ]]; then
  fail "authoritative test scratch must not be a symbolic link"
elif [[ -e "$TEST_SCRATCH" ]]; then
  validate_directory "$TEST_SCRATCH" "authoritative test scratch"
else
  mkdir -m 700 "$TEST_SCRATCH"
fi

# The scratch graph is deliberately stable so every repetition can reuse one
# test binary. Prevent a second wrapper invocation from rebuilding or reading
# that graph at the same time. Keep the zero-byte file so BSD lock ordering is
# stable across runs; the advisory lock itself lives only on descriptor 9.
if [[ -L "$TEST_LOCK" ]]; then
  fail "authoritative test lock must not be a symbolic link"
elif [[ ! -e "$TEST_LOCK" ]]; then
  if ! (umask 077; set -o noclobber; : >"$TEST_LOCK") 2>/dev/null; then
    [[ -e "$TEST_LOCK" || -L "$TEST_LOCK" ]] \
      || fail "authoritative test lock could not be created"
  fi
fi

[[ -f "$TEST_LOCK" && ! -L "$TEST_LOCK" ]] \
  || fail "authoritative test lock must be a regular file"
[[ "$(stat -f '%u' "$TEST_LOCK")" == "$(id -u)" ]] \
  || fail "authoritative test lock must be owned by the current user"
[[ "$(stat -f '%Lp' "$TEST_LOCK")" == "600" ]] \
  || fail "authoritative test lock permissions must be 0600"
[[ "$(stat -f '%l' "$TEST_LOCK")" == "1" ]] \
  || fail "authoritative test lock must have exactly one hard link"
[[ "$(stat -f '%z' "$TEST_LOCK")" == "0" ]] \
  || fail "authoritative test lock must remain empty"

exec 9<>"$TEST_LOCK" \
  || fail "authoritative test lock could not be opened"
if ! /usr/bin/lockf -s -t 0 9; then
  fail "another authoritative test run is already using the shared test graph"
fi

# Dependency resolution may use SwiftPM's conventional workspace, while the
# full suite and every --skip-build repetition share this separate graph.
# This prevents a developer build, a release/debug App build, or an unrelated
# `swift package` operation from holding the authoritative test database.
swift test --disable-keychain \
  --scratch-path "$TEST_SCRATCH" \
  --only-use-versions-from-resolved-file

./scripts/ci/verify-local-version-probe-stability.sh
./scripts/ci/verify-hermetic-local-listener.sh
./scripts/ci/verify-tmux-process-stability.sh
./scripts/ci/verify-codex-hook-trust-process-stability.sh
./scripts/ci/verify-sleep-wake-lifecycle-stability.sh

echo "Authoritative test graph: PASS"
