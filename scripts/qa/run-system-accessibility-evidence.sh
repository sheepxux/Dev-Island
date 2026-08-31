#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

fail() {
  echo "error: $1" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
T7_ROOT="/Volumes/T7 Shield"
EVIDENCE_ROOT="$T7_ROOT/MacMini/CodexFiles/DevIsland-Optimization/evidence/system-accessibility"
PACKAGER="$ROOT/scripts/qa/package-system-accessibility-evidence.rb"
VALIDATOR="$ROOT/scripts/qa/validate-system-accessibility-evidence.rb"
CAPTURE_DIR=""
DEBUG_APP=""
PRODUCTION_APP=""
OUTPUT_ROOT="$EVIDENCE_ROOT"
VOICEOVER_CONFIRMATION=""
KEYBOARD_CONFIRMATION=""

usage() {
  cat >&2 <<'USAGE'
Usage: run-system-accessibility-evidence.sh \
  --capture-dir DIR \
  --debug-app APP \
  --production-app APP \
  --confirm-voiceover-observation real_process_operator_observed \
  --confirm-keyboard-sequence command_d_then_command_return_operator_observed \
  [--output-root DIR]

This wrapper is read-only with respect to macOS preferences. It accepts evidence
only after Reduce Motion, Increase Contrast and Reduce Transparency are off,
VoiceOver and the Debug App are stopped, and exactly one reviewed Production App
process is running. Run future capture sessions in an isolated macOS test account.
USAGE
  exit 64
}

while (($#)); do
  case "$1" in
    --capture-dir)
      (($# >= 2)) || usage
      CAPTURE_DIR="$2"
      shift 2
      ;;
    --debug-app)
      (($# >= 2)) || usage
      DEBUG_APP="$2"
      shift 2
      ;;
    --production-app)
      (($# >= 2)) || usage
      PRODUCTION_APP="$2"
      shift 2
      ;;
    --output-root)
      (($# >= 2)) || usage
      OUTPUT_ROOT="$2"
      shift 2
      ;;
    --confirm-voiceover-observation)
      (($# >= 2)) || usage
      VOICEOVER_CONFIRMATION="$2"
      shift 2
      ;;
    --confirm-keyboard-sequence)
      (($# >= 2)) || usage
      KEYBOARD_CONFIRMATION="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

test -d "$T7_ROOT" || fail "T7 Shield is not mounted"
test -n "$CAPTURE_DIR" && test -d "$CAPTURE_DIR" \
  || fail "capture directory is unavailable"
test -n "$DEBUG_APP" && test -d "$DEBUG_APP" \
  || fail "Debug App is unavailable"
test -n "$PRODUCTION_APP" && test -d "$PRODUCTION_APP" \
  || fail "Production App is unavailable"
test -x "$PACKAGER" && test -x "$VALIDATOR" \
  || fail "system accessibility evidence tools are not executable"
test "$VOICEOVER_CONFIRMATION" = "real_process_operator_observed" \
  || fail "VoiceOver process observation must be explicitly confirmed"
test "$KEYBOARD_CONFIRMATION" = "command_d_then_command_return_operator_observed" \
  || fail "keyboard transition sequence must be explicitly confirmed"

case "$OUTPUT_ROOT" in
  "$EVIDENCE_ROOT"|"$EVIDENCE_ROOT"/*) ;;
  *) fail "output root must stay inside the reviewed T7 evidence directory" ;;
esac
install -d -m 700 "$EVIDENCE_ROOT" "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd -P)"

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1/Contents/Info.plist"
}

app_executable() {
  local app="$1"
  local name
  name="$(plist_value "$app" CFBundleExecutable)"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "App executable name is invalid"
  printf '%s\n' "$app/Contents/MacOS/$name"
}

preference_off() {
  local key="$1"
  local value
  value="$(defaults read com.apple.universalaccess "$key" 2>/dev/null || true)"
  case "$value" in
    0|false|FALSE) ;;
    *) fail "$key must be off before evidence can be accepted" ;;
  esac
}

process_count_exact() {
  local target="$1"
  ps ax -o command= | awk -v target="$target" '$0 == target { count++ } END { print count + 0 }'
}

preference_off reduceMotion
preference_off increaseContrast
preference_off reduceTransparency

VOICEOVER_PROCESSES="$({
  ps ax -o command= | awk \
    '/\/System\/Library\/CoreServices\/VoiceOver\.app|\/scrod/ && !/awk/ { count++ } END { print count + 0 }'
} || true)"
test "$VOICEOVER_PROCESSES" = "0" \
  || fail "VoiceOver must be stopped before evidence can be accepted"

DEBUG_EXECUTABLE="$(app_executable "$DEBUG_APP")"
PRODUCTION_EXECUTABLE="$(app_executable "$PRODUCTION_APP")"
test -f "$DEBUG_EXECUTABLE" && test -f "$PRODUCTION_EXECUTABLE" \
  || fail "reviewed App executable is unavailable"
DEBUG_PROCESSES="$(process_count_exact "$DEBUG_EXECUTABLE")"
PRODUCTION_PROCESSES="$(process_count_exact "$PRODUCTION_EXECUTABLE")"
test "$DEBUG_PROCESSES" = "0" \
  || fail "Debug App must be stopped before evidence can be accepted"
test "$PRODUCTION_PROCESSES" = "1" \
  || fail "exactly one reviewed Production App process must be running"

PRODUCTION_SHA256="$(shasum -a 256 "$PRODUCTION_EXECUTABLE" | awk '{print $1}')"
[[ "$PRODUCTION_SHA256" =~ ^[0-9a-f]{64}$ ]] \
  || fail "Production App SHA-256 is invalid"
PRODUCTION_BYTES="$(stat -f '%z' "$PRODUCTION_EXECUTABLE")"
[[ "$PRODUCTION_BYTES" =~ ^[1-9][0-9]*$ ]] \
  || fail "Production App byte size is invalid"

CAPTURE_EPOCHS="$({
  find "$CAPTURE_DIR" -maxdepth 1 -type f -print0 \
    | xargs -0 stat -f '%m' \
    | sort -n
} || true)"
test -n "$CAPTURE_EPOCHS" || fail "capture directory contains no regular files"
START_EPOCH="$(printf '%s\n' "$CAPTURE_EPOCHS" | head -n 1)"
FINISH_EPOCH="$(printf '%s\n' "$CAPTURE_EPOCHS" | tail -n 1)"
test "$START_EPOCH" -lt "$FINISH_EPOCH" \
  || fail "capture timestamps do not define a real interval"
STARTED_AT="$(date -u -r "$START_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')"
FINISHED_AT="$(date -u -r "$FINISH_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')"
RECORDED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

STAGING="$(mktemp -d "$OUTPUT_ROOT/.restoration-XXXXXX")"
case "$STAGING" in "$OUTPUT_ROOT"/.restoration-*) ;; *) fail "unsafe staging path" ;; esac
RUN_DIRECTORY=""
cleanup() {
  rm -rf "$STAGING"
  if test -n "$RUN_DIRECTORY" && test -d "$RUN_DIRECTORY" && test ! -f "$RUN_DIRECTORY/ACCEPTED"; then
    echo "warning: rejected evidence retained at $RUN_DIRECTORY" >&2
  fi
}
trap cleanup EXIT INT TERM
chmod 700 "$STAGING"
RESTORATION_STATE="$STAGING/RESTORATION_STATE.txt"
{
  printf '%s\n' \
    'schema=dev-island-system-restoration-v1' \
    "recorded_at_utc=$RECORDED_AT" \
    'reduce_motion=off' \
    'increase_contrast=off' \
    'reduce_transparency=off' \
    "voiceover_processes=$VOICEOVER_PROCESSES" \
    "debug_app_processes=$DEBUG_PROCESSES" \
    "production_app_processes=$PRODUCTION_PROCESSES" \
    "production_app_executable_sha256=$PRODUCTION_SHA256" \
    "production_app_executable_bytes=$PRODUCTION_BYTES" \
    'method=macos_system_settings_and_process_inspection'
} >"$RESTORATION_STATE"
chmod 600 "$RESTORATION_STATE"

RUN_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_DIRECTORY="$(mktemp -d "$OUTPUT_ROOT/run-$RUN_STAMP-XXXXXX")"
case "$RUN_DIRECTORY" in "$OUTPUT_ROOT"/run-*) ;; *) fail "unsafe evidence path" ;; esac
chmod 700 "$RUN_DIRECTORY"

PUBLIC_RECEIPT="$({
  "$PACKAGER" \
    --repository "$ROOT" \
    --capture-dir "$CAPTURE_DIR" \
    --debug-app "$DEBUG_APP" \
    --restoration-state "$RESTORATION_STATE" \
    --output "$RUN_DIRECTORY" \
    --started-at "$STARTED_AT" \
    --finished-at "$FINISHED_AT" \
    --confirm-voiceover-observation "$VOICEOVER_CONFIRMATION" \
    --confirm-keyboard-sequence "$KEYBOARD_CONFIRMATION"
})"

PRODUCT_VERSION="$(tr -d '\n' <"$ROOT/VERSION")"
"$VALIDATOR" --evidence "$RUN_DIRECTORY" --require-accepted \
  --product-version "$PRODUCT_VERSION" >/dev/null

printf 'System accessibility evidence: ACCEPTED\n'
printf 'package=%s\n' "$RUN_DIRECTORY"
printf 'public_receipt=%s\n' "$PUBLIC_RECEIPT"
