#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

TEST_SCRATCH="$ROOT/.build/tests-authoritative"
[[ -d "$TEST_SCRATCH" && ! -L "$TEST_SCRATCH" ]] \
  || fail "Authoritative test scratch is unavailable; run run-authoritative-tests.sh first"

CLI_CANDIDATES=()
while IFS= read -r candidate; do
  CLI_CANDIDATES+=("$candidate")
done < <(find "$TEST_SCRATCH" -type f -path '*/debug/IslandCoreCLI' -print)
[[ "${#CLI_CANDIDATES[@]}" -eq 1 ]] \
  || fail "Expected exactly one authoritative IslandCoreCLI executable"
CLI="${CLI_CANDIDATES[0]}"
[[ -x "$CLI" && ! -L "$CLI" && "$(stat -f '%u' "$CLI")" == "$(id -u)" ]] \
  || fail "Authoritative IslandCoreCLI ownership boundary failed"

TEMP_ROOT="$(mktemp -d -t dev-island-hermetic-listener)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-hermetic-listener.*|/var/folders/*/T/dev-island-hermetic-listener.*|/tmp/dev-island-hermetic-listener.*) ;;
  *) fail "Refusing to use an unexpected temporary path" ;;
esac

cleanup() {
  case "$TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-hermetic-listener.*|/var/folders/*/T/dev-island-hermetic-listener.*|/tmp/dev-island-hermetic-listener.*)
      rm -rf "$TEMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT

ITERATIONS=10
for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  STDOUT_LOG="$TEMP_ROOT/stdout-$iteration.log"
  STDERR_LOG="$TEMP_ROOT/stderr-$iteration.log"
  if ! "$CLI" local-hermetic-listener-check >"$STDOUT_LOG" 2>"$STDERR_LOG"; then
    fail "Hermetic local listener check failed at round $iteration"
  fi
  [[ ! -s "$STDERR_LOG" ]] \
    || fail "Hermetic local listener leaked framework diagnostics at round $iteration"
  EXPECTED_OUTPUT=$'[CLI] Hermetic local listener check\n[CLI] listener=verified\n[CLI] authorization=memory-only\n[CLI] agent-routes=disabled\n[CLI] result=verified'
  [[ "$(<"$STDOUT_LOG")" == "$EXPECTED_OUTPUT" ]] \
    || fail "Hermetic local listener output contract drifted at round $iteration"
done

echo "Hermetic local listener: PASS ($ITERATIONS rounds, memory-only authorization, zero Agent routes)"
