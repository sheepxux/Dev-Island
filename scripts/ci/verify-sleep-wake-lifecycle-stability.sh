#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

ITERATIONS=20
FILTER='TaskStoreManusLifecycleTests'
TEST_SCRATCH="$ROOT/.build/tests-authoritative"

[[ -d "$TEST_SCRATCH" && ! -L "$TEST_SCRATCH" ]] \
  || fail "Authoritative test scratch is unavailable; run run-authoritative-tests.sh first"

TEMP_ROOT="$(mktemp -d -t dev-island-sleep-wake-stability)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-sleep-wake-stability.*|/var/folders/*/T/dev-island-sleep-wake-stability.*|/tmp/dev-island-sleep-wake-stability.*) ;;
  *) fail "Refusing to use an unexpected temporary path" ;;
esac

cleanup() {
  case "$TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-sleep-wake-stability.*|/var/folders/*/T/dev-island-sleep-wake-stability.*|/tmp/dev-island-sleep-wake-stability.*)
      rm -rf "$TEMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  LOG="$TEMP_ROOT/run-$iteration.log"
  if ! swift test --scratch-path "$TEST_SCRATCH" \
    --skip-build --filter "$FILTER" >"$LOG" 2>&1; then
    # Preserve one authoritative XCTest total and avoid printing fixture
    # internals unless a named test or compiler error actually failed.
    rg -n 'Test Case .* failed|error:' "$LOG" >&2 || true
    fail "Sleep/wake lifecycle stability failed at round $iteration"
  fi
done

echo "Sleep/wake lifecycle stability: PASS ($ITERATIONS rounds)"
