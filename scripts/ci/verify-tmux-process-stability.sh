#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

ITERATIONS=20
FILTER='SourceAppResolverTests.testTmuxNavigatorKillsBackgroundDescendantAfterLeaderExits'
TEST_SCRATCH="$ROOT/.build/tests-authoritative"

[[ -d "$TEST_SCRATCH" && ! -L "$TEST_SCRATCH" ]] \
  || fail "Authoritative test scratch is unavailable; run run-authoritative-tests.sh first"

TEMP_ROOT="$(mktemp -d -t dev-island-tmux-process-stability)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-tmux-process-stability.*|/var/folders/*/T/dev-island-tmux-process-stability.*|/tmp/dev-island-tmux-process-stability.*) ;;
  *) fail "Refusing to use an unexpected temporary path" ;;
esac

cleanup() {
  case "$TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-tmux-process-stability.*|/var/folders/*/T/dev-island-tmux-process-stability.*|/tmp/dev-island-tmux-process-stability.*)
      rm -rf "$TEMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT

for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  LOG="$TEMP_ROOT/run-$iteration.log"
  if ! swift test --scratch-path "$TEST_SCRATCH" \
    --skip-build --filter "$FILTER" >"$LOG" 2>&1; then
    # Keep the preceding full suite as the sole authoritative XCTest total.
    rg -n 'Test Case .* failed|error:' "$LOG" >&2 || true
    fail "tmux descendant cleanup stability failed at round $iteration"
  fi
done

echo "tmux descendant cleanup stability: PASS ($ITERATIONS rounds)"
