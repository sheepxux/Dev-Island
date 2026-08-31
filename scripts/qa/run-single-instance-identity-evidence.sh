#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 '/absolute/path/Dev Island.app' '/Volumes/T7 Shield/.../evidence-directory'" >&2
  exit 64
}

[[ "$#" -eq 2 ]] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$1"
EVIDENCE_DIR="$2"
FIXTURE_DIR="$SCRIPT_DIR/fixtures"
PROBE_SOURCE="$FIXTURE_DIR/RunningApplicationProbe.swift"
LAUNCH_PROBE_SOURCE="$FIXTURE_DIR/ApplicationLaunchProbe.swift"
IMPOSTOR_SOURCE="$FIXTURE_DIR/SingleInstanceImpostor.swift"
IMPOSTOR_PLIST="$FIXTURE_DIR/SingleInstanceImpostor-Info.plist"
SCREEN_PROBE_SOURCE="$SCRIPT_DIR/display-session-state.swift"
EXPECTED_BUNDLE_ID="app.devisland.Island"
LISTENER_PORT=7824
ROUND_COUNT=20

[[ -d "/Volumes/T7 Shield" ]] || {
  echo "error: T7 Shield is not mounted" >&2
  exit 2
}
[[ "$SOURCE_APP" == /* && -d "$SOURCE_APP" && ! -L "$SOURCE_APP" ]] || {
  echo "error: selected QA App must be an absolute, regular app-bundle directory" >&2
  exit 2
}
[[ "$EVIDENCE_DIR" == "/Volumes/T7 Shield/"* && ! -e "$EVIDENCE_DIR" && ! -L "$EVIDENCE_DIR" ]] || {
  echo "error: evidence directory must be a new path on T7 Shield" >&2
  exit 2
}
for source in \
  "$PROBE_SOURCE" \
  "$LAUNCH_PROBE_SOURCE" \
  "$IMPOSTOR_SOURCE" \
  "$IMPOSTOR_PLIST" \
  "$SCREEN_PROBE_SOURCE"; do
  [[ -f "$source" && ! -L "$source" ]] || {
    echo "error: missing single-instance QA fixture: $source" >&2
    exit 2
  }
done

SOURCE_APP="$(/bin/realpath "$SOURCE_APP")"
SOURCE_BINARY="$SOURCE_APP/Contents/MacOS/IslandApp"
SOURCE_PLIST="$SOURCE_APP/Contents/Info.plist"
[[ -x "$SOURCE_BINARY" && -f "$SOURCE_PLIST" && ! -L "$SOURCE_BINARY" && ! -L "$SOURCE_PLIST" ]] || {
  echo "error: selected QA App has no regular executable or Info.plist" >&2
  exit 2
}

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_PLIST" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || {
  echo "error: selected QA App Bundle ID is not exact" >&2
  exit 2
}

umask 077
/bin/mkdir -p "$EVIDENCE_DIR"
RUNTIME_ROOT="$(mktemp -d -t dev-island-single-instance-identity)"
PROBE="$RUNTIME_ROOT/running-application-probe"
LAUNCH_PROBE="$RUNTIME_ROOT/application-launch-probe"
SCREEN_PROBE="$RUNTIME_ROOT/display-session-state"
COPY_A="$RUNTIME_ROOT/identical-a/Dev Island.app"
COPY_B="$RUNTIME_ROOT/identical-b/Dev Island.app"
IMPOSTOR_APP="$RUNTIME_ROOT/impostor/Dev Island Identity Impostor.app"
IMPOSTOR_BINARY="$IMPOSTOR_APP/Contents/MacOS/SingleInstanceImpostor"
IMPOSTOR_EVENTS="$RUNTIME_ROOT/impostor-events.log"
ROUND_CSV="$EVIDENCE_DIR/IDENTICAL_ADHOC_20_ROUNDS.csv"
AUDIT_FILE="$EVIDENCE_DIR/SINGLE_INSTANCE_IDENTITY_AUDIT.txt"
TREE_MANIFEST_FILE="$EVIDENCE_DIR/APP_TREE_MANIFEST.txt"
SHA_FILE="$EVIDENCE_DIR/SHA256SUMS"
OWNED_PROCESS_FILE="$RUNTIME_ROOT/owned-processes.tsv"
PHASE="preflight"
: >"$OWNED_PROCESS_FILE"

append_owned_pid() {
  printf '%s\t%s\n' "$1" "$2" >>"$OWNED_PROCESS_FILE"
}

forget_owned_pid() {
  local target="$1"
  local next="$RUNTIME_ROOT/owned-processes.next.tsv"
  awk -F '\t' -v pid="$target" '$1 != pid' "$OWNED_PROCESS_FILE" >"$next"
  /bin/mv "$next" "$OWNED_PROCESS_FILE"
}

terminate_exact_pid() {
  local pid="$1"
  local executable="$2"
  local attempt
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
    forget_owned_pid "$pid"
    return 0
  fi

  "$PROBE" terminate "$pid" "$executable" >/dev/null 2>&1 || true
  for attempt in $(jot 50); do
    local state
    state="$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -z "$state" || "$state" == Z* ]] && break
    sleep 0.1
  done
  if kill -0 "$pid" 2>/dev/null; then
    local observed
    observed="$("$PROBE" list "$EXPECTED_BUNDLE_ID" 2>/dev/null | awk -F '\t' -v pid="$pid" '$1 == pid { print $2 }')"
    if [[ "$observed" == "$(/bin/realpath "$executable")" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  fi
  wait "$pid" 2>/dev/null || true
  forget_owned_pid "$pid"
  return 0
}

cleanup() {
  local pid executable cleanup_snapshot
  cleanup_snapshot="$RUNTIME_ROOT/owned-processes.cleanup.tsv"
  /bin/cp "$OWNED_PROCESS_FILE" "$cleanup_snapshot" 2>/dev/null || true
  while IFS=$'\t' read -r pid executable; do
    [[ -n "$pid" && -n "$executable" ]] || continue
    terminate_exact_pid "$pid" "$executable"
  done <"$cleanup_snapshot"
  /bin/rm -rf "$RUNTIME_ROOT"
}

handle_exit() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if [[ "$status" -ne 0 && ! -e "$AUDIT_FILE" && ! -L "$AUDIT_FILE" ]]; then
    {
      echo "result=FAIL"
      echo "failed_phase=$PHASE"
      echo "failure=unexpected-harness-exit-status-$status"
    } >"$AUDIT_FILE"
  fi
  cleanup
  exit "$status"
}
trap handle_exit EXIT
trap 'exit 130' INT TERM

fail() {
  echo "error: $*" >&2
  {
    echo "result=FAIL"
    echo "failed_phase=$PHASE"
    echo "failure=$*"
  } >>"$AUDIT_FILE"
  exit 1
}

running_snapshot() {
  "$PROBE" list "$EXPECTED_BUNDLE_ID"
}

listener_pids() {
  /usr/sbin/lsof -nP -iTCP:"$LISTENER_PORT" -sTCP:LISTEN -Fp 2>/dev/null \
    | sed -n 's/^p//p' \
    | sort -n -u
}

require_only_local_listener_socket() {
  local pid="$1"
  local socket_snapshot="$RUNTIME_ROOT/network-$pid.snapshot"
  local names states
  /usr/sbin/lsof -nP -a -p "$pid" -i -F pnPT >"$socket_snapshot" 2>/dev/null \
    || fail "expected owner has no inspectable local listener socket"
  names="$(sed -n 's/^n//p' "$socket_snapshot" | sort -u)"
  states="$(sed -n 's/^TST=//p' "$socket_snapshot" | sort -u)"
  [[ "$names" == "127.0.0.1:$LISTENER_PORT" && "$states" == "LISTEN" ]] \
    || fail "ordinary owner opened a network socket outside 127.0.0.1:7824 LISTEN"
}

require_no_network_socket() {
  local pid="$1"
  if /usr/sbin/lsof -nP -a -p "$pid" -i 2>/dev/null \
      | awk 'NR > 1 { found = 1 } END { exit(found ? 0 : 1) }'; then
    fail "AppKit impostor unexpectedly opened a network socket"
  fi
}

wait_for_exact_application() {
  local expected_pid="$1"
  local expected_executable="$2"
  local attempt snapshot observed
  for attempt in $(jot 120); do
    snapshot="$(running_snapshot 2>/dev/null || true)"
    observed="$(printf '%s\n' "$snapshot" | awk -F '\t' -v pid="$expected_pid" '$1 == pid { print $2 }')"
    [[ -n "$observed" && -f "$observed" && "$observed" -ef "$expected_executable" ]] \
      && return 0
    kill -0 "$expected_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

launch_application() {
  local app="$1"
  local private_user_root="$2"
  local event_log="${3:-}"
  local result
  if [[ -n "$event_log" ]]; then
    result="$("$LAUNCH_PROBE" "$app" "$private_user_root" "$event_log")" || return 1
  else
    result="$("$LAUNCH_PROBE" "$app" "$private_user_root")" || return 1
  fi
  [[ "$result" == *$'\t'* && "$result" != *$'\n'* ]] || return 1
  printf '%s\n' "$result"
}

wait_for_process_disappearance() {
  local pid="$1"
  local expected_executable="$2"
  local timeout_deciseconds="$3"
  local attempt observed
  for attempt in $(jot "$timeout_deciseconds"); do
    observed="$(running_snapshot 2>/dev/null | awk -F '\t' -v pid="$pid" '$1 == pid { print $2 }' || true)"
    if [[ -n "$observed" \
       && ( ! -f "$observed" || ! "$observed" -ef "$expected_executable" ) ]]; then
      return 125
    fi
    if [[ -z "$observed" ]] && ! kill -0 "$pid" 2>/dev/null; then
      forget_owned_pid "$pid"
      return 0
    fi
    sleep 0.1
  done
  return 124
}

wait_for_listener_owner() {
  local expected_pid="$1"
  local attempt observed
  for attempt in $(jot 160); do
    observed="$(listener_pids || true)"
    [[ "$observed" == "$expected_pid" ]] && return 0
    kill -0 "$expected_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

require_exact_running_set() {
  local expected_file="$1"
  local actual_file="$RUNTIME_ROOT/running.actual"
  LC_ALL=C sort -n "$expected_file" -o "$expected_file"
  local attempt
  for attempt in $(jot 30); do
    running_snapshot | LC_ALL=C sort -n >"$actual_file"
    cmp -s "$expected_file" "$actual_file" && return 0
    sleep 0.1
  done
  fail "same-Bundle running application set drifted"
}

wait_for_no_product_runtime() {
  local attempt
  for attempt in $(jot 50); do
    if [[ -z "$(running_snapshot 2>/dev/null || true)" \
       && -z "$(listener_pids || true)" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

require_empty_duplicate_user_root() {
  local private_user_root="$1"
  local forbidden
  for forbidden in \
    "$private_user_root/Library/Application Support/island-app/tasks.sqlite" \
    "$private_user_root/Library/Application Support/island-app/local-hook-authorization.header"; do
    [[ ! -e "$forbidden" && ! -L "$forbidden" ]] \
      || fail "yielding duplicate created product state in its private user root"
  done
  [[ -z "$(find "$private_user_root" -mindepth 1 -print 2>/dev/null)" ]] \
    || fail "yielding duplicate created unexpected state in its private user root"
}

millis_now() {
  /usr/bin/ruby -e 'puts((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round)'
}

app_tree_manifest() {
  local root="$1"
  local output="$2"
  /usr/bin/ruby -rdigest -rfind -e '
    root = File.realpath(ARGV.fetch(0))
    entries = []
    Find.find(root) do |path|
      next if path == root
      relative = path.delete_prefix(root + "/")
      stat = File.lstat(path)
      if stat.file?
        entries << [relative, "file", stat.mode & 0o7777, Digest::SHA256.file(path).hexdigest]
      elsif stat.symlink?
        entries << [relative, "symlink", stat.mode & 0o7777, File.readlink(path)]
      elsif stat.directory?
        entries << [relative, "directory", stat.mode & 0o7777, "-"]
      else
        abort "unsupported bundle entry: #{relative}"
      end
    end
    entries.sort.each { |entry| puts entry.join("\t") }
  ' "$root" >"$output"
}

PHASE="compile-helpers"
/usr/bin/xcrun swiftc -O "$PROBE_SOURCE" -o "$PROBE" \
  || fail "could not compile running-application probe"
/usr/bin/xcrun swiftc -O -parse-as-library "$LAUNCH_PROBE_SOURCE" -o "$LAUNCH_PROBE" \
  || fail "could not compile LaunchServices application probe"
/usr/bin/xcrun swiftc -O "$SCREEN_PROBE_SOURCE" -o "$SCREEN_PROBE" \
  || fail "could not compile display-session probe"
SCREEN_STATE_INITIAL="$("$SCREEN_PROBE" 2>/dev/null || printf 'unknown\n')"
case "$SCREEN_STATE_INITIAL" in
  locked|unlocked|unknown) ;;
  *) SCREEN_STATE_INITIAL="unknown" ;;
esac

PHASE="source-identity"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP" \
  || fail "selected QA App does not pass strict deep code-signing verification"
SOURCE_SIGNING="$RUNTIME_ROOT/source-signing.txt"
/usr/bin/codesign -dv --verbose=4 "$SOURCE_APP" >"$SOURCE_SIGNING" 2>&1 \
  || fail "selected QA App signing information is unavailable"
grep -Fxq "Identifier=$EXPECTED_BUNDLE_ID" "$SOURCE_SIGNING" \
  || fail "selected QA App code identifier is not exact"
grep -Fxq "Signature=adhoc" "$SOURCE_SIGNING" \
  || fail "selected QA App is not explicitly ad-hoc signed"
grep -Fxq "TeamIdentifier=not set" "$SOURCE_SIGNING" \
  || fail "selected QA App unexpectedly has a Team ID"
SOURCE_CDHASH="$(sed -n 's/^CDHash=//p' "$SOURCE_SIGNING" | head -n 1)"
[[ "$SOURCE_CDHASH" =~ ^[0-9a-f]{40}$ ]] || fail "selected QA App has no stable SHA-256 CDHash"
SOURCE_EXECUTABLE_SHA256="$(shasum -a 256 "$SOURCE_BINARY" | awk '{print $1}')"

PHASE="preflight"
[[ -z "$(running_snapshot 2>/dev/null || true)" ]] \
  || fail "a pre-existing app with the production Bundle ID is running; no process was changed"
[[ -z "$(listener_pids || true)" ]] \
  || fail "TCP port 7824 already has a listener; no process was changed"

PHASE="freeze-byte-identical-copies"
/bin/mkdir -p "$(dirname "$COPY_A")" "$(dirname "$COPY_B")"
/usr/bin/ditto --rsrc --extattr "$SOURCE_APP" "$COPY_A"
/usr/bin/ditto --rsrc --extattr "$SOURCE_APP" "$COPY_B"
/usr/bin/codesign --verify --deep --strict "$COPY_A" \
  || fail "first byte-identical copy failed strict signing verification"
/usr/bin/codesign --verify --deep --strict "$COPY_B" \
  || fail "second byte-identical copy failed strict signing verification"
app_tree_manifest "$SOURCE_APP" "$RUNTIME_ROOT/source.manifest"
app_tree_manifest "$COPY_A" "$RUNTIME_ROOT/copy-a.manifest"
app_tree_manifest "$COPY_B" "$RUNTIME_ROOT/copy-b.manifest"
cmp -s "$RUNTIME_ROOT/source.manifest" "$RUNTIME_ROOT/copy-a.manifest" \
  || fail "first App copy is not byte-identical to the selected QA App"
cmp -s "$RUNTIME_ROOT/source.manifest" "$RUNTIME_ROOT/copy-b.manifest" \
  || fail "second App copy is not byte-identical to the selected QA App"
COPY_A_CDHASH="$(/usr/bin/codesign -dv --verbose=4 "$COPY_A" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1)"
COPY_B_CDHASH="$(/usr/bin/codesign -dv --verbose=4 "$COPY_B" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1)"
[[ "$COPY_A_CDHASH" == "$SOURCE_CDHASH" && "$COPY_B_CDHASH" == "$SOURCE_CDHASH" ]] \
  || fail "byte-identical copies do not share the source CDHash"
/bin/cp "$RUNTIME_ROOT/source.manifest" "$TREE_MANIFEST_FILE"

{
  echo "round,duplicate_pid,duration_ms,termination_observation,sole_owner_pid,listener_owner_pid"
} >"$ROUND_CSV"

PHASE="identical-owner-launch"
/bin/mkdir -m 700 "$RUNTIME_ROOT/owner-home" "$RUNTIME_ROOT/duplicate-home"
OWNER_LAUNCH="$(launch_application "$COPY_A" "$RUNTIME_ROOT/owner-home")" \
  || fail "LaunchServices could not launch the first byte-identical App"
OWNER_PID="${OWNER_LAUNCH%%$'\t'*}"
OWNER_EXECUTABLE="${OWNER_LAUNCH#*$'\t'}"
[[ "$OWNER_PID" =~ ^[1-9][0-9]*$ \
   && -f "$OWNER_EXECUTABLE" \
   && "$OWNER_EXECUTABLE" -ef "$COPY_A/Contents/MacOS/IslandApp" ]] \
  || fail "LaunchServices returned an unexpected first-owner identity"
append_owned_pid "$OWNER_PID" "$OWNER_EXECUTABLE"
wait_for_exact_application "$OWNER_PID" "$COPY_A/Contents/MacOS/IslandApp" \
  || fail "first byte-identical App did not register as the expected application"
wait_for_listener_owner "$OWNER_PID" \
  || fail "first byte-identical App did not become sole port-7824 backend owner"
require_only_local_listener_socket "$OWNER_PID"

for round in $(jot "$ROUND_COUNT"); do
  PHASE="identical-round-$round"
  start_ms="$(millis_now)"
  duplicate_launch="$(launch_application "$COPY_B" "$RUNTIME_ROOT/duplicate-home")" \
    || fail "LaunchServices could not launch duplicate round $round"
  duplicate_pid="${duplicate_launch%%$'\t'*}"
  duplicate_executable="${duplicate_launch#*$'\t'}"
  [[ "$duplicate_pid" =~ ^[1-9][0-9]*$ \
     && -f "$duplicate_executable" \
     && "$duplicate_executable" -ef "$COPY_B/Contents/MacOS/IslandApp" ]] \
    || fail "LaunchServices returned an unexpected duplicate identity in round $round"
  append_owned_pid "$duplicate_pid" "$duplicate_executable"
  set +e
  wait_for_process_disappearance "$duplicate_pid" "$COPY_B/Contents/MacOS/IslandApp" 50
  duplicate_observation_status=$?
  set -e
  end_ms="$(millis_now)"
  [[ "$duplicate_observation_status" -eq 0 ]] \
    || fail "duplicate round $round did not disappear within 5 seconds (observation $duplicate_observation_status)"
  require_empty_duplicate_user_root "$RUNTIME_ROOT/duplicate-home"
  kill -0 "$OWNER_PID" 2>/dev/null \
    || fail "owner exited during duplicate round $round"
  expected="$RUNTIME_ROOT/expected-owner.tsv"
  printf '%s\t%s\n' "$OWNER_PID" "$OWNER_EXECUTABLE" >"$expected"
  require_exact_running_set "$expected"
  observed_listener="$(listener_pids || true)"
  [[ "$observed_listener" == "$OWNER_PID" ]] \
    || fail "listener ownership drifted during duplicate round $round"
  require_only_local_listener_socket "$OWNER_PID"
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$round" "$duplicate_pid" "$((end_ms - start_ms))" "process-disappeared" "$OWNER_PID" "$observed_listener" \
    >>"$ROUND_CSV"
done
require_empty_duplicate_user_root "$RUNTIME_ROOT/duplicate-home"
require_only_local_listener_socket "$OWNER_PID"

PHASE="identical-owner-terminate"
terminate_exact_pid "$OWNER_PID" "$COPY_A/Contents/MacOS/IslandApp"
PHASE="identical-owner-wait-empty"
wait_for_no_product_runtime \
  || fail "same-Bundle QA process or port-7824 listener remained after identical-copy phase"

PHASE="build-different-cdhash-impostor"
/bin/mkdir -p "$IMPOSTOR_APP/Contents/MacOS"
/bin/cp "$IMPOSTOR_PLIST" "$IMPOSTOR_APP/Contents/Info.plist"
/usr/bin/xcrun swiftc -O -parse-as-library "$IMPOSTOR_SOURCE" -framework AppKit -o "$IMPOSTOR_BINARY" \
  || fail "could not compile the AppKit impostor"
/usr/bin/codesign --force --sign - --timestamp=none --identifier "$EXPECTED_BUNDLE_ID" "$IMPOSTOR_APP" \
  || fail "could not ad-hoc sign the AppKit impostor"
/usr/bin/codesign --verify --deep --strict "$IMPOSTOR_APP" \
  || fail "AppKit impostor failed strict code-signing verification"
IMPOSTOR_SIGNING="$RUNTIME_ROOT/impostor-signing.txt"
/usr/bin/codesign -dv --verbose=4 "$IMPOSTOR_APP" >"$IMPOSTOR_SIGNING" 2>&1 \
  || fail "AppKit impostor signing information is unavailable"
grep -Fxq "Identifier=$EXPECTED_BUNDLE_ID" "$IMPOSTOR_SIGNING" \
  || fail "impostor code identifier is not exact"
grep -Fxq "Signature=adhoc" "$IMPOSTOR_SIGNING" \
  || fail "impostor is not explicitly ad-hoc signed"
grep -Fxq "TeamIdentifier=not set" "$IMPOSTOR_SIGNING" \
  || fail "impostor unexpectedly has a Team ID"
IMPOSTOR_CDHASH="$(sed -n 's/^CDHash=//p' "$IMPOSTOR_SIGNING" | head -n 1)"
[[ "$IMPOSTOR_CDHASH" =~ ^[0-9a-f]{40}$ && "$IMPOSTOR_CDHASH" != "$SOURCE_CDHASH" ]] \
  || fail "impostor does not have a distinct nonempty CDHash"

PHASE="impostor-launch"
: >"$IMPOSTOR_EVENTS"
/bin/mkdir -m 700 "$RUNTIME_ROOT/impostor-home"
IMPOSTOR_LAUNCH="$(launch_application "$IMPOSTOR_APP" "$RUNTIME_ROOT/impostor-home" "$IMPOSTOR_EVENTS")" \
  || fail "LaunchServices could not launch the AppKit impostor"
IMPOSTOR_PID="${IMPOSTOR_LAUNCH%%$'\t'*}"
IMPOSTOR_EXECUTABLE="${IMPOSTOR_LAUNCH#*$'\t'}"
[[ "$IMPOSTOR_PID" =~ ^[1-9][0-9]*$ \
   && -f "$IMPOSTOR_EXECUTABLE" \
   && "$IMPOSTOR_EXECUTABLE" -ef "$IMPOSTOR_BINARY" ]] \
  || fail "LaunchServices returned an unexpected impostor identity"
append_owned_pid "$IMPOSTOR_PID" "$IMPOSTOR_EXECUTABLE"
wait_for_exact_application "$IMPOSTOR_PID" "$IMPOSTOR_BINARY" \
  || fail "impostor did not register as the expected same-Bundle application"
for attempt in $(jot 50); do
  grep -Fxq "did-finish-launching" "$IMPOSTOR_EVENTS" && break
  kill -0 "$IMPOSTOR_PID" 2>/dev/null || fail "impostor exited before readiness"
  sleep 0.1
done
grep -Fxq "did-finish-launching" "$IMPOSTOR_EVENTS" \
  || fail "impostor did not publish its launch marker"
require_no_network_socket "$IMPOSTOR_PID"
IMPOSTOR_ACTIVE_BEFORE="$(grep -Fxc "did-become-active" "$IMPOSTOR_EVENTS" || true)"

PHASE="different-cdhash-real-launch"
/bin/mkdir -m 700 "$RUNTIME_ROOT/real-home"
REAL_LAUNCH="$(launch_application "$COPY_A" "$RUNTIME_ROOT/real-home")" \
  || fail "LaunchServices could not launch the real App beside the impostor"
REAL_PID="${REAL_LAUNCH%%$'\t'*}"
REAL_EXECUTABLE="${REAL_LAUNCH#*$'\t'}"
[[ "$REAL_PID" =~ ^[1-9][0-9]*$ \
   && -f "$REAL_EXECUTABLE" \
   && "$REAL_EXECUTABLE" -ef "$COPY_A/Contents/MacOS/IslandApp" ]] \
  || fail "LaunchServices returned an unexpected real-App identity"
append_owned_pid "$REAL_PID" "$REAL_EXECUTABLE"
wait_for_exact_application "$REAL_PID" "$COPY_A/Contents/MacOS/IslandApp" \
  || fail "real App yielded to or failed beside the different-CDHash impostor"
wait_for_listener_owner "$REAL_PID" \
  || fail "real App did not become the sole port-7824 backend owner beside the impostor"
require_only_local_listener_socket "$REAL_PID"
require_no_network_socket "$IMPOSTOR_PID"
sleep 1
kill -0 "$REAL_PID" 2>/dev/null || fail "real App exited beside the different-CDHash impostor"
kill -0 "$IMPOSTOR_PID" 2>/dev/null || fail "different-CDHash impostor was terminated"
IMPOSTOR_ACTIVE_AFTER="$(grep -Fxc "did-become-active" "$IMPOSTOR_EVENTS" || true)"
[[ "$IMPOSTOR_ACTIVE_AFTER" == "$IMPOSTOR_ACTIVE_BEFORE" ]] \
  || fail "different-CDHash impostor received an activation event"
[[ "$(grep -Fxc "will-terminate" "$IMPOSTOR_EVENTS" || true)" == "0" ]] \
  || fail "different-CDHash impostor received a termination event"
expected="$RUNTIME_ROOT/expected-impostor-real.tsv"
{
  printf '%s\t%s\n' "$IMPOSTOR_PID" "$IMPOSTOR_EXECUTABLE"
  printf '%s\t%s\n' "$REAL_PID" "$REAL_EXECUTABLE"
} >"$expected"
require_exact_running_set "$expected"
[[ "$(listener_pids || true)" == "$REAL_PID" ]] \
  || fail "real App was not the unique listener owner beside the impostor"
require_only_local_listener_socket "$REAL_PID"
require_no_network_socket "$IMPOSTOR_PID"

PHASE="impostor-matrix-cleanup"
terminate_exact_pid "$REAL_PID" "$COPY_A/Contents/MacOS/IslandApp"
kill -0 "$IMPOSTOR_PID" 2>/dev/null \
  || fail "impostor did not survive real App shutdown"
terminate_exact_pid "$IMPOSTOR_PID" "$IMPOSTOR_BINARY"
wait_for_no_product_runtime \
  || fail "same-Bundle QA process or port-7824 listener remained after impostor phase"

PHASE="write-evidence"
SCREEN_STATE_FINAL="$("$SCREEN_PROBE" 2>/dev/null || printf 'unknown\n')"
case "$SCREEN_STATE_FINAL" in
  locked|unlocked|unknown) ;;
  *) SCREEN_STATE_FINAL="unknown" ;;
esac
[[ "$SCREEN_STATE_FINAL" == "$SCREEN_STATE_INITIAL" ]] \
  || fail "display session state changed during process-level evidence capture"
MIN_DURATION="$(awk -F, 'NR == 2 { min = $3 } NR > 2 && $3 < min { min = $3 } END { print min }' "$ROUND_CSV")"
MAX_DURATION="$(awk -F, 'NR > 1 && $3 > max { max = $3 } END { print max }' "$ROUND_CSV")"
AVERAGE_DURATION="$(awk -F, 'NR > 1 { total += $3; count += 1 } END { printf "%.1f", total / count }' "$ROUND_CSV")"
DURATION_QUANTILES="$(/usr/bin/ruby -rcsv -e '
  values = CSV.read(ARGV.fetch(0), headers: true).map { |row| Integer(row.fetch("duration_ms")) }.sort
  abort "expected exactly 20 durations" unless values.length == 20
  middle = values.length / 2
  median = (values[middle - 1] + values[middle]) / 2.0
  p95 = values[(values.length * 0.95).ceil - 1]
  printf("%.1f\t%d\n", median, p95)
' "$ROUND_CSV")"
MEDIAN_DURATION="${DURATION_QUANTILES%%$'\t'*}"
P95_DURATION="${DURATION_QUANTILES#*$'\t'}"
{
  echo "Dev Island v6.84 live code-identity single-instance evidence"
  echo "date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "result=PASS"
  echo "screen_state_initial=$SCREEN_STATE_INITIAL"
  echo "screen_state_final=$SCREEN_STATE_FINAL"
  echo "timing_scope=process-level-only"
  echo "ordinary_owner_harness=not-hermetic-login-keychain-not-isolated"
  echo "keychain_content_read_by_harness=false"
  echo "owner_network_scope_every_check=127.0.0.1:7824-LISTEN-only"
  echo "bundle_identifier=$EXPECTED_BUNDLE_ID"
  echo "source_app=$SOURCE_APP"
  echo "source_executable_sha256=$SOURCE_EXECUTABLE_SHA256"
  echo "source_signature=adhoc"
  echo "source_team_identifier=not-set"
  echo "source_cdhash=$SOURCE_CDHASH"
  echo "byte_identical_tree_manifest=true"
  echo "identical_copy_cdhash=$COPY_A_CDHASH"
  echo "identical_rounds=$ROUND_COUNT"
  echo "identical_process_disappearance_rounds=$ROUND_COUNT"
  echo "identical_duration_ms_min=$MIN_DURATION"
  echo "identical_duration_ms_median=$MEDIAN_DURATION"
  echo "identical_duration_ms_p95=$P95_DURATION"
  echo "identical_duration_ms_average=$AVERAGE_DURATION"
  echo "identical_duration_ms_max=$MAX_DURATION"
  echo "identical_sole_application_every_round=true"
  echo "identical_sole_listener_owner_every_round=true"
  echo "identical_duplicate_private_user_root_empty_every_round=true"
  echo "identical_termination_observation=LaunchServices-returned PID disappeared after AppKit gate"
  echo "identical_exit_status=not-observable-for-LaunchServices-spawned-process"
  echo "impostor_signature=adhoc"
  echo "impostor_team_identifier=not-set"
  echo "impostor_cdhash=$IMPOSTOR_CDHASH"
  echo "impostor_cdhash_differs=true"
  echo "real_app_survived_impostor=true"
  echo "real_app_unique_listener_owner=true"
  echo "impostor_activation_count_before=$IMPOSTOR_ACTIVE_BEFORE"
  echo "impostor_activation_count_after=$IMPOSTOR_ACTIVE_AFTER"
  echo "impostor_not_activated=true"
  echo "impostor_not_terminated_by_real_launch=true"
  echo "cleanup_same_bundle_process_count=0"
  echo "cleanup_port_7824_listener_count=0"
  echo "boundary_same_team_cross_version=not-tested-requires-developer-id-artifacts"
} >"$AUDIT_FILE"

(
  cd "$EVIDENCE_DIR"
  shasum -a 256 \
    "$(basename "$AUDIT_FILE")" \
    "$(basename "$ROUND_CSV")" \
    "$(basename "$TREE_MANIFEST_FILE")" \
    >"$(basename "$SHA_FILE")"
)
/bin/chmod 400 "$AUDIT_FILE" "$ROUND_CSV" "$TREE_MANIFEST_FILE" "$SHA_FILE"

echo "Single-instance identity evidence: PASS"
echo "20/20 byte-identical ad-hoc duplicate PIDs disappeared after arbitration."
echo "Different-CDHash same-Bundle impostor was neither activated nor terminated; the real App remained the sole listener owner."
echo "Evidence: $EVIDENCE_DIR"
