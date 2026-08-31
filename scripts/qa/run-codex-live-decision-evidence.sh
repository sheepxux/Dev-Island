#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

CODEX_DECISION_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CODEX_DECISION_PACKAGER="$CODEX_DECISION_SCRIPT_DIR/package-codex-live-decision-evidence.rb"
CODEX_DECISION_VALIDATOR="$CODEX_DECISION_SCRIPT_DIR/validate-codex-live-decision-evidence.rb"

fail() {
  echo "error: $1" >&2
  exit 1
}

test -x "$CODEX_DECISION_PACKAGER" && test -x "$CODEX_DECISION_VALIDATOR" \
  || fail "Codex live-decision evidence packager or validator is unavailable"
command -v ruby >/dev/null 2>&1 || fail "Ruby is required"

for CODEX_DECISION_ARGUMENT in "$@"; do
  [[ "$CODEX_DECISION_ARGUMENT" != "--output" ]] \
    || fail "--output is managed by the T7 evidence wrapper"
  [[ "$CODEX_DECISION_ARGUMENT" != "--classify-session" ]] \
    || fail "classification-only mode must not allocate an accepted evidence package"
done

CODEX_DECISION_MOUNT_ROOT="/Volumes/T7 Shield"
[[ -d "$CODEX_DECISION_MOUNT_ROOT" && ! -L "$CODEX_DECISION_MOUNT_ROOT" ]] \
  || fail "T7 Shield is not mounted at the required path"
/sbin/mount | /usr/bin/grep -Fq " on /Volumes/T7 Shield (" \
  || fail "T7 Shield is not mounted; connect the external drive before packaging evidence"

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

CODEX_DECISION_ROOT="$CODEX_DECISION_MOUNT_ROOT"
for CODEX_DECISION_COMPONENT in \
  MacMini CodexFiles DevIsland-Optimization evidence codex-live-decision; do
  CODEX_DECISION_ROOT="$(
    ensure_child_directory "$CODEX_DECISION_ROOT" "$CODEX_DECISION_COMPONENT"
  )"
done
CODEX_DECISION_ROOT="$(cd "$CODEX_DECISION_ROOT" && pwd -P)"
[[ "$CODEX_DECISION_ROOT" == "$CODEX_DECISION_MOUNT_ROOT/"* ]] \
  || fail "resolved evidence directory escaped T7 Shield"

CODEX_DECISION_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
CODEX_DECISION_RUN_DIRECTORY="$(
  /usr/bin/mktemp -d "$CODEX_DECISION_ROOT/run-$CODEX_DECISION_TIMESTAMP-XXXXXX"
)" || fail "could not allocate an append-never Codex decision directory"
[[ "$CODEX_DECISION_RUN_DIRECTORY" == "$CODEX_DECISION_ROOT/run-"* ]] \
  || fail "Codex decision allocation escaped its reviewed root"
/bin/chmod 700 "$CODEX_DECISION_RUN_DIRECTORY"

set +e
"$CODEX_DECISION_PACKAGER" "$@" --output "$CODEX_DECISION_RUN_DIRECTORY"
CODEX_DECISION_PACKAGE_EXIT=$?
set -e
if (( CODEX_DECISION_PACKAGE_EXIT != 0 )); then
  echo "Codex live-decision evidence was not accepted." >&2
  echo "Partial evidence retained at: $CODEX_DECISION_RUN_DIRECTORY" >&2
  exit "$CODEX_DECISION_PACKAGE_EXIT"
fi

"$CODEX_DECISION_VALIDATOR" \
  --evidence "$CODEX_DECISION_RUN_DIRECTORY" \
  --require-accepted

echo "Codex live-decision evidence package: ACCEPTED"
echo "Evidence: $CODEX_DECISION_RUN_DIRECTORY"
