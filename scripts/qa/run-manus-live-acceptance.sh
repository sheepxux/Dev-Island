#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

LIVE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
LIVE_REPOSITORY_ROOT="$(cd "$LIVE_SCRIPT_DIR/../.." && pwd -P)"
LIVE_VALIDATOR="$LIVE_SCRIPT_DIR/validate-manus-live-acceptance-transcript.rb"
LIVE_BUILD_INPUT_GENERATOR="$LIVE_SCRIPT_DIR/generate-manus-live-build-inputs.rb"
LIVE_VERSION_VALIDATOR="$LIVE_REPOSITORY_ROOT/scripts/release/validate-product-version.rb"
LIVE_TIMEOUT=600

usage() {
  echo "Usage: run-manus-live-acceptance.sh [--timeout 60...1800]" >&2
  exit 64
}

fail() {
  echo "error: $1" >&2
  exit 1
}

if [[ $# -eq 2 && "$1" == "--timeout" && "$2" =~ ^[0-9]+$ ]]; then
  LIVE_TIMEOUT="$2"
elif [[ $# -ne 0 ]]; then
  usage
fi
(( LIVE_TIMEOUT >= 60 && LIVE_TIMEOUT <= 1800 )) || usage

test -x "$LIVE_VALIDATOR" && test -x "$LIVE_BUILD_INPUT_GENERATOR" \
  && test -x "$LIVE_VERSION_VALIDATOR" \
  || fail "live-acceptance validator or build-input boundary is unavailable"
command -v xcrun >/dev/null 2>&1 || fail "Xcode command-line tools are required"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"
command -v git >/dev/null 2>&1 || fail "git is required"

LIVE_MOUNT_ROOT="/Volumes/T7 Shield"
[[ -d "$LIVE_MOUNT_ROOT" && ! -L "$LIVE_MOUNT_ROOT" ]] \
  || fail "T7 Shield is not mounted at the required path"
/sbin/mount | /usr/bin/grep -Fq " on /Volumes/T7 Shield (" \
  || fail "T7 Shield is not mounted; connect the external drive before running acceptance"

ensure_child_directory() {
  local parent="$1"
  local component="$2"
  local candidate="$parent/$component"
  [[ ! -L "$candidate" ]] || fail "refusing a symbolic-link T7 evidence directory"
  if [[ -e "$candidate" ]]; then
    [[ -d "$candidate" ]] || fail "a required T7 evidence path is not a directory"
  else
    /bin/mkdir "$candidate" || fail "could not create a required T7 evidence directory"
  fi
  [[ -d "$candidate" && ! -L "$candidate" ]] \
    || fail "T7 evidence directory changed during creation"
  printf '%s\n' "$candidate"
}

LIVE_EVIDENCE_ROOT="$LIVE_MOUNT_ROOT"
for LIVE_COMPONENT in MacMini CodexFiles DevIsland-Optimization evidence manus-live-acceptance; do
  LIVE_EVIDENCE_ROOT="$(ensure_child_directory "$LIVE_EVIDENCE_ROOT" "$LIVE_COMPONENT")"
done
LIVE_EVIDENCE_ROOT="$(cd "$LIVE_EVIDENCE_ROOT" && pwd -P)"
[[ "$LIVE_EVIDENCE_ROOT" == "$LIVE_MOUNT_ROOT/"* ]] \
  || fail "resolved evidence directory escaped T7 Shield"

LIVE_CACHE_ROOT="$LIVE_MOUNT_ROOT"
for LIVE_COMPONENT in MacMini CodexFiles DevIsland-Optimization build-cache manus-live-acceptance; do
  LIVE_CACHE_ROOT="$(ensure_child_directory "$LIVE_CACHE_ROOT" "$LIVE_COMPONENT")"
done
LIVE_CACHE_ROOT="$(cd "$LIVE_CACHE_ROOT" && pwd -P)"
[[ "$LIVE_CACHE_ROOT" == "$LIVE_MOUNT_ROOT/"* ]] \
  || fail "resolved build cache escaped T7 Shield"

for LIVE_COMPONENT in scratch cache configuration security; do
  ensure_child_directory "$LIVE_CACHE_ROOT" "$LIVE_COMPONENT" >/dev/null
done
LIVE_BUILD_SCRATCH="$LIVE_CACHE_ROOT/scratch"
LIVE_SWIFTPM_CACHE="$LIVE_CACHE_ROOT/cache"
LIVE_SWIFTPM_CONFIG="$LIVE_CACHE_ROOT/configuration"
LIVE_SWIFTPM_SECURITY="$LIVE_CACHE_ROOT/security"

LIVE_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
LIVE_RUN_DIRECTORY="$(/usr/bin/mktemp -d "$LIVE_EVIDENCE_ROOT/run-$LIVE_TIMESTAMP-XXXXXX")" \
  || fail "could not allocate an append-never evidence directory"
[[ "$LIVE_RUN_DIRECTORY" == "$LIVE_EVIDENCE_ROOT/run-"* ]] \
  || fail "evidence directory allocation escaped its reviewed root"
/bin/chmod 700 "$LIVE_RUN_DIRECTORY"

LIVE_STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
LIVE_FINISHED_AT=""
LIVE_BOOTSTRAP_RESULT="not_started"
LIVE_BUILD_RESULT="not_started"
LIVE_SOURCE_STABILITY="not_checked"
LIVE_TOOLCHAIN_STABILITY="not_checked"
LIVE_LOCAL_INPUT_COUNT="unavailable"
LIVE_DEPENDENCY_COUNT="unavailable"
LIVE_CLI_EXIT="not_run"
LIVE_TEE_EXIT="not_run"
LIVE_TRANSCRIPT_RESULT="not_created"
LIVE_ACCEPTED_RESULT="not_checked"
LIVE_WRAPPER_RESULT="preparing"
LIVE_WRAPPER_SIGNAL="none"
LIVE_BINARY_SHA256="unavailable"
LIVE_BASELINE_COMMIT="$(git -C "$LIVE_REPOSITORY_ROOT" rev-parse HEAD)" \
  || fail "repository commit could not be resolved"
if [[ -n "$(git -C "$LIVE_REPOSITORY_ROOT" status --porcelain --untracked-files=normal)" ]]; then
  LIVE_WORKTREE_STATE="dirty"
else
  LIVE_WORKTREE_STATE="clean"
fi
LIVE_PRODUCT_VERSION="$("$LIVE_VERSION_VALIDATOR" \
  --version-file "$LIVE_REPOSITORY_ROOT/VERSION")"

write_build_inputs() {
  local destination="$1"
  "$LIVE_BUILD_INPUT_GENERATOR" \
    --repository "$LIVE_REPOSITORY_ROOT" \
    --scratch "$LIVE_BUILD_SCRATCH" >"$destination"
}

write_toolchain_manifest() {
  local destination="$1"
  local swiftc_path
  local swiftc_resolved
  local sdk_path
  swiftc_path="$(xcrun -f swiftc)"
  swiftc_resolved="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$swiftc_path")"
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  [[ -f "$swiftc_resolved" && ! -L "$swiftc_resolved" ]] \
    || fail "resolved Swift compiler is unavailable"
  [[ -f "$sdk_path/SDKSettings.json" && ! -L "$sdk_path/SDKSettings.json" ]] \
    || fail "macOS SDK settings are unavailable"
  {
    printf 'schema=dev-island-manus-live-toolchain-v1\n'
    printf 'machine_arch=%s\n' "$(uname -m)"
    printf 'swiftc_path=%s\n' "$swiftc_path"
    printf 'swiftc_resolved_path=%s\n' "$swiftc_resolved"
    printf 'swiftc_sha256=%s\n' "$(shasum -a 256 "$swiftc_resolved" | awk '{print $1}')"
    printf 'sdk_path=%s\n' "$sdk_path"
    printf 'sdk_settings_sha256=%s\n' "$(shasum -a 256 "$sdk_path/SDKSettings.json" | awk '{print $1}')"
    xcrun swift --version | sed 's/^/swift_version=/'
    xcodebuild -version | sed 's/^/xcode_version=/'
    sw_vers | sed 's/^/macos_version=/'
  } >"$destination"
}

write_metadata() {
  LIVE_FINISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    printf 'schema=dev-island-manus-live-acceptance-evidence-v2\n'
    printf 'started_at_utc=%s\n' "$LIVE_STARTED_AT"
    printf 'finished_at_utc=%s\n' "$LIVE_FINISHED_AT"
    printf 'product_version=%s\n' "$LIVE_PRODUCT_VERSION"
    printf 'baseline_commit=%s\n' "$LIVE_BASELINE_COMMIT"
    printf 'worktree_state=%s\n' "$LIVE_WORKTREE_STATE"
    printf 'timeout_seconds=%s\n' "$LIVE_TIMEOUT"
    printf 'bootstrap_result=%s\n' "$LIVE_BOOTSTRAP_RESULT"
    printf 'build_result=%s\n' "$LIVE_BUILD_RESULT"
    printf 'source_stability=%s\n' "$LIVE_SOURCE_STABILITY"
    printf 'toolchain_stability=%s\n' "$LIVE_TOOLCHAIN_STABILITY"
    printf 'local_input_files=%s\n' "$LIVE_LOCAL_INPUT_COUNT"
    printf 'dependency_checkouts=%s\n' "$LIVE_DEPENDENCY_COUNT"
    printf 'binary_sha256=%s\n' "$LIVE_BINARY_SHA256"
    printf 'cli_exit=%s\n' "$LIVE_CLI_EXIT"
    printf 'tee_exit=%s\n' "$LIVE_TEE_EXIT"
    printf 'transcript_result=%s\n' "$LIVE_TRANSCRIPT_RESULT"
    printf 'accepted_result=%s\n' "$LIVE_ACCEPTED_RESULT"
    printf 'wrapper_result=%s\n' "$LIVE_WRAPPER_RESULT"
    printf 'wrapper_signal=%s\n' "$LIVE_WRAPPER_SIGNAL"
  } >"$LIVE_RUN_DIRECTORY/EVIDENCE_METADATA.txt"
}

finalize_evidence() {
  write_metadata
  for LIVE_EVIDENCE_FILE in "$LIVE_RUN_DIRECTORY"/*; do
    [[ -f "$LIVE_EVIDENCE_FILE" && ! -L "$LIVE_EVIDENCE_FILE" ]] \
      || fail "evidence package contains an unexpected non-regular entry"
    if [[ -x "$LIVE_EVIDENCE_FILE" ]]; then
      /bin/chmod 500 "$LIVE_EVIDENCE_FILE"
    else
      /bin/chmod 400 "$LIVE_EVIDENCE_FILE"
    fi
  done
  (
    cd "$LIVE_RUN_DIRECTORY"
    for LIVE_EVIDENCE_NAME in *; do
      [[ "$LIVE_EVIDENCE_NAME" == "SHA256SUMS" || "$LIVE_EVIDENCE_NAME" == "SHA256SUMS.partial" ]] \
        && continue
      [[ -f "$LIVE_EVIDENCE_NAME" && ! -L "$LIVE_EVIDENCE_NAME" ]] \
        || exit 1
      shasum -a 256 "$LIVE_EVIDENCE_NAME"
    done
  ) >"$LIVE_RUN_DIRECTORY/SHA256SUMS.partial"
  /bin/chmod 400 "$LIVE_RUN_DIRECTORY/SHA256SUMS.partial"
  /bin/mv "$LIVE_RUN_DIRECTORY/SHA256SUMS.partial" "$LIVE_RUN_DIRECTORY/SHA256SUMS"
  echo "Evidence: $LIVE_RUN_DIRECTORY"
}

handle_build_signal() {
  local signal_name="$1"
  local exit_status="$2"
  trap - INT TERM
  LIVE_WRAPPER_SIGNAL="$signal_name"
  if [[ "$LIVE_BOOTSTRAP_RESULT" == "not_started" ]]; then
    LIVE_BOOTSTRAP_RESULT="interrupted"
  else
    LIVE_BUILD_RESULT="interrupted"
  fi
  LIVE_WRAPPER_RESULT="wrapper_interrupted_during_build"
  LIVE_SOURCE_STABILITY="unavailable_after_interruption"
  LIVE_TOOLCHAIN_STABILITY="unavailable_after_interruption"
  finalize_evidence || true
  echo "Manus live acceptance build interrupted; no accepted evidence was produced." >&2
  exit "$exit_status"
}

record_live_signal() {
  LIVE_WRAPPER_SIGNAL="$1"
}

echo "Preparing the Package.resolved dependency closure on T7 Shield..."
trap 'handle_build_signal interrupt 130' INT
trap 'handle_build_signal terminate 143' TERM
set +e
xcrun swift build \
  --package-path "$LIVE_REPOSITORY_ROOT" \
  --scratch-path "$LIVE_BUILD_SCRATCH" \
  --cache-path "$LIVE_SWIFTPM_CACHE" \
  --config-path "$LIVE_SWIFTPM_CONFIG" \
  --security-path "$LIVE_SWIFTPM_SECURITY" \
  --only-use-versions-from-resolved-file \
  --product IslandCoreCLI >"$LIVE_RUN_DIRECTORY/BUILD.log" 2>&1
LIVE_BOOTSTRAP_EXIT=$?
set -e
trap - INT TERM
if (( LIVE_BOOTSTRAP_EXIT != 0 )); then
  LIVE_BOOTSTRAP_RESULT="failed"
  LIVE_WRAPPER_RESULT="dependency_bootstrap_failed"
  finalize_evidence
  fail "resolved dependency preparation failed; the private build log is in the evidence directory"
fi
LIVE_BOOTSTRAP_RESULT="passed"

write_build_inputs "$LIVE_RUN_DIRECTORY/BUILD_INPUTS_BEFORE_BUILD.json"
write_toolchain_manifest "$LIVE_RUN_DIRECTORY/TOOLCHAIN_BEFORE_BUILD.txt"
read -r LIVE_LOCAL_INPUT_COUNT LIVE_DEPENDENCY_COUNT < <(ruby -r json -e '
  manifest = JSON.parse(File.binread(ARGV.fetch(0)))
  totals = manifest.fetch("totals")
  puts [totals.fetch("localInputFiles"), totals.fetch("dependencyCheckouts")].join(" ")
' "$LIVE_RUN_DIRECTORY/BUILD_INPUTS_BEFORE_BUILD.json")

echo "Building the reviewed IslandCoreCLI from the validated input closure..."
trap 'handle_build_signal interrupt 130' INT
trap 'handle_build_signal terminate 143' TERM
set +e
xcrun swift build \
  --package-path "$LIVE_REPOSITORY_ROOT" \
  --scratch-path "$LIVE_BUILD_SCRATCH" \
  --cache-path "$LIVE_SWIFTPM_CACHE" \
  --config-path "$LIVE_SWIFTPM_CONFIG" \
  --security-path "$LIVE_SWIFTPM_SECURITY" \
  --only-use-versions-from-resolved-file \
  --product IslandCoreCLI >>"$LIVE_RUN_DIRECTORY/BUILD.log" 2>&1
LIVE_BUILD_EXIT=$?
set -e
trap - INT TERM
LIVE_BUILD_RESULT="$([[ "$LIVE_BUILD_EXIT" == "0" ]] && printf passed || printf failed)"

write_build_inputs "$LIVE_RUN_DIRECTORY/BUILD_INPUTS_AFTER_BUILD.json"
write_toolchain_manifest "$LIVE_RUN_DIRECTORY/TOOLCHAIN_AFTER_BUILD.txt"
if /usr/bin/cmp -s \
  "$LIVE_RUN_DIRECTORY/BUILD_INPUTS_BEFORE_BUILD.json" \
  "$LIVE_RUN_DIRECTORY/BUILD_INPUTS_AFTER_BUILD.json"; then
  LIVE_SOURCE_STABILITY="stable"
else
  LIVE_SOURCE_STABILITY="changed"
fi
if /usr/bin/cmp -s \
  "$LIVE_RUN_DIRECTORY/TOOLCHAIN_BEFORE_BUILD.txt" \
  "$LIVE_RUN_DIRECTORY/TOOLCHAIN_AFTER_BUILD.txt"; then
  LIVE_TOOLCHAIN_STABILITY="stable"
else
  LIVE_TOOLCHAIN_STABILITY="changed"
fi
if (( LIVE_BUILD_EXIT != 0 )); then
  LIVE_WRAPPER_RESULT="build_failed"
  finalize_evidence
  fail "IslandCoreCLI build failed; the private build log is in the evidence directory"
fi
if [[ "$LIVE_SOURCE_STABILITY" != "stable" || "$LIVE_TOOLCHAIN_STABILITY" != "stable" ]]; then
  LIVE_WRAPPER_RESULT="build_input_changed_during_build"
  finalize_evidence
  fail "live-acceptance build inputs changed during the build"
fi

LIVE_BIN_DIRECTORY="$(xcrun swift build \
  --package-path "$LIVE_REPOSITORY_ROOT" \
  --scratch-path "$LIVE_BUILD_SCRATCH" \
  --cache-path "$LIVE_SWIFTPM_CACHE" \
  --config-path "$LIVE_SWIFTPM_CONFIG" \
  --security-path "$LIVE_SWIFTPM_SECURITY" \
  --only-use-versions-from-resolved-file \
  --show-bin-path 2>>"$LIVE_RUN_DIRECTORY/BUILD.log")"
[[ "$LIVE_BIN_DIRECTORY" == "$LIVE_BUILD_SCRATCH/"* ]] \
  || fail "SwiftPM binary directory escaped the reviewed T7 scratch path"
LIVE_BUILT_BINARY="$LIVE_BIN_DIRECTORY/IslandCoreCLI"
[[ -f "$LIVE_BUILT_BINARY" && ! -L "$LIVE_BUILT_BINARY" && -x "$LIVE_BUILT_BINARY" ]] \
  || fail "built IslandCoreCLI is unavailable or unsafe"
LIVE_EVIDENCE_BINARY="$LIVE_RUN_DIRECTORY/IslandCoreCLI"
/bin/cp "$LIVE_BUILT_BINARY" "$LIVE_EVIDENCE_BINARY"
/bin/chmod 500 "$LIVE_EVIDENCE_BINARY"
LIVE_BINARY_SHA256="$(shasum -a 256 "$LIVE_EVIDENCE_BINARY" | awk '{print $1}')"

echo "Starting the explicit Manus live-account acceptance run."
echo "The CLI will ask for the API key through the terminal and never from arguments or environment."
echo "Create one task that finishes and one task that pauses for input; fixed checkpoints appear below."

LIVE_TRANSCRIPT_PART="$LIVE_RUN_DIRECTORY/transcript.txt.partial"
LIVE_TRANSCRIPT="$LIVE_RUN_DIRECTORY/transcript.txt"
trap 'record_live_signal interrupt' INT
trap 'record_live_signal terminate' TERM
set +e
/usr/bin/env -i \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin" \
  TMPDIR="/tmp" \
  LC_ALL="C" \
  "$LIVE_EVIDENCE_BINARY" manus-live-acceptance --timeout "$LIVE_TIMEOUT" \
  | /usr/bin/tee "$LIVE_TRANSCRIPT_PART"
LIVE_PIPE_STATUSES=("${PIPESTATUS[@]}")
set -e
trap - INT TERM
LIVE_CLI_EXIT="${LIVE_PIPE_STATUSES[0]:-1}"
LIVE_TEE_EXIT="${LIVE_PIPE_STATUSES[1]:-1}"
/bin/mv "$LIVE_TRANSCRIPT_PART" "$LIVE_TRANSCRIPT"
/bin/chmod 600 "$LIVE_TRANSCRIPT"

LIVE_VALIDATION_LOG="$LIVE_RUN_DIRECTORY/TRANSCRIPT_VALIDATION.txt"
set +e
"$LIVE_VALIDATOR" --transcript "$LIVE_TRANSCRIPT" >"$LIVE_VALIDATION_LOG" 2>&1
LIVE_SAFE_TRANSCRIPT_EXIT=$?
set -e
if (( LIVE_SAFE_TRANSCRIPT_EXIT == 0 )); then
  LIVE_TRANSCRIPT_RESULT="allowlisted"
  set +e
  "$LIVE_VALIDATOR" --transcript "$LIVE_TRANSCRIPT" --require-accepted \
    >>"$LIVE_VALIDATION_LOG" 2>&1
  LIVE_ACCEPTED_TRANSCRIPT_EXIT=$?
  set -e
  if (( LIVE_ACCEPTED_TRANSCRIPT_EXIT == 0 )); then
    LIVE_ACCEPTED_RESULT="validated"
  else
    LIVE_ACCEPTED_RESULT="not_accepted"
  fi
else
  LIVE_TRANSCRIPT_RESULT="rejected_and_removed"
  LIVE_ACCEPTED_RESULT="not_checked"
  /bin/rm -f "$LIVE_TRANSCRIPT"
  printf '%s\n' \
    'Transcript removed because it contained data outside the low-cardinality evidence contract.' \
    >"$LIVE_RUN_DIRECTORY/TRANSCRIPT_REMOVED.txt"
fi

if [[ "$LIVE_CLI_EXIT" == "0" \
      && "$LIVE_TEE_EXIT" == "0" \
      && "$LIVE_ACCEPTED_RESULT" == "validated" ]]; then
  LIVE_WRAPPER_RESULT="accepted"
  printf '%s\n' 'accepted=true' >"$LIVE_RUN_DIRECTORY/ACCEPTED"
  finalize_evidence
  echo "Manus live acceptance: ACCEPTED"
  exit 0
fi

if [[ "$LIVE_TEE_EXIT" != "0" ]]; then
  LIVE_WRAPPER_RESULT="transcript_capture_failed"
elif [[ "$LIVE_TRANSCRIPT_RESULT" == "rejected_and_removed" ]]; then
  LIVE_WRAPPER_RESULT="transcript_rejected"
elif [[ "$LIVE_CLI_EXIT" == "0" ]]; then
  LIVE_WRAPPER_RESULT="accepted_claim_not_proven"
else
  LIVE_WRAPPER_RESULT="live_run_not_accepted"
fi
finalize_evidence
echo "Manus live acceptance: NOT ACCEPTED" >&2
if [[ "$LIVE_CLI_EXIT" =~ ^[0-9]+$ ]] && (( LIVE_CLI_EXIT > 0 && LIVE_CLI_EXIT <= 255 )); then
  exit "$LIVE_CLI_EXIT"
fi
exit 1
