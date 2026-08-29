#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

ITERATIONS=20
CHILD_PROCESSES_PER_ITERATION=12
FILTER='LocalLiveReadinessTests.testRepeatedFastVersionProcessesDoNotLoseTerminationOrOutput'
TEST_SCRATCH="$ROOT/.build/tests-authoritative"

[[ -d "$TEST_SCRATCH" && ! -L "$TEST_SCRATCH" ]] \
  || fail "Authoritative test scratch is unavailable; run run-authoritative-tests.sh first"

TEMP_ROOT="$(mktemp -d -t dev-island-version-probe-stability)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-version-probe-stability.*|/var/folders/*/T/dev-island-version-probe-stability.*|/tmp/dev-island-version-probe-stability.*) ;;
  *) fail "Refusing to use an unexpected temporary path" ;;
esac

cleanup() {
  case "$TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-version-probe-stability.*|/var/folders/*/T/dev-island-version-probe-stability.*|/tmp/dev-island-version-probe-stability.*)
      rm -rf "$TEMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  LOG="$TEMP_ROOT/run-$iteration.log"
  if ! swift test --scratch-path "$TEST_SCRATCH" \
    --skip-build --filter "$FILTER" >"$LOG" 2>&1; then
    # Keep CI diagnostics useful without appending another XCTest aggregate
    # count after the authoritative full-suite total.
    rg -n 'Test Case .* failed|error:' "$LOG" >&2 || true
    fail "Local version probe stability failed at round $iteration"
  fi
done

TOTAL_CHILDREN=$((ITERATIONS * CHILD_PROCESSES_PER_ITERATION))
echo "Local version probe stability: PASS ($ITERATIONS rounds, $TOTAL_CHILDREN child processes)"
