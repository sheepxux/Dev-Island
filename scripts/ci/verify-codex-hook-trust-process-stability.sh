#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

ITERATIONS=5
FILTER='CodexHookTrustProbeTests'
TEST_SCRATCH="$ROOT/.build/tests-authoritative"

[[ -d "$TEST_SCRATCH" && ! -L "$TEST_SCRATCH" ]] \
  || fail "Authoritative test scratch is unavailable; run run-authoritative-tests.sh first"

TEMP_ROOT="$(mktemp -d -t dev-island-codex-hook-trust-stability)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-codex-hook-trust-stability.*|/var/folders/*/T/dev-island-codex-hook-trust-stability.*|/tmp/dev-island-codex-hook-trust-stability.*) ;;
  *) fail "Refusing to use an unexpected temporary path" ;;
esac

cleanup() {
  case "$TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-codex-hook-trust-stability.*|/var/folders/*/T/dev-island-codex-hook-trust-stability.*|/tmp/dev-island-codex-hook-trust-stability.*)
      rm -rf "$TEMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  LOG="$TEMP_ROOT/run-$iteration.log"
  if ! swift test --scratch-path "$TEST_SCRATCH" \
    --skip-build --filter "$FILTER" >"$LOG" 2>&1; then
    # Keep the preceding full suite as the sole authoritative XCTest total,
    # and never print raw App Server fixture output on the success path.
    rg -n 'Test Case .* failed|error:' "$LOG" >&2 || true
    fail "Codex Hook trust process stability failed at round $iteration"
  fi
done

echo "Codex Hook trust process stability: PASS ($ITERATIONS rounds)"
