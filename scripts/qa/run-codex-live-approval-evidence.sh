#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

CODEX_EVIDENCE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CODEX_EVIDENCE_PACKAGER="$CODEX_EVIDENCE_SCRIPT_DIR/package-codex-live-approval-evidence.rb"
CODEX_EVIDENCE_VALIDATOR="$CODEX_EVIDENCE_SCRIPT_DIR/validate-codex-live-approval-evidence.rb"

fail() {
  echo "error: $1" >&2
  exit 1
}

test -x "$CODEX_EVIDENCE_PACKAGER" && test -x "$CODEX_EVIDENCE_VALIDATOR" \
  || fail "Codex live-approval evidence packager or validator is unavailable"
command -v ruby >/dev/null 2>&1 || fail "Ruby is required"

for CODEX_EVIDENCE_ARGUMENT in "$@"; do
  [[ "$CODEX_EVIDENCE_ARGUMENT" != "--output" ]] \
    || fail "--output is managed by the T7 evidence wrapper"
done

CODEX_EVIDENCE_MOUNT_ROOT="/Volumes/T7 Shield"
[[ -d "$CODEX_EVIDENCE_MOUNT_ROOT" && ! -L "$CODEX_EVIDENCE_MOUNT_ROOT" ]] \
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

CODEX_EVIDENCE_ROOT="$CODEX_EVIDENCE_MOUNT_ROOT"
for CODEX_EVIDENCE_COMPONENT in \
  MacMini CodexFiles DevIsland-Optimization evidence codex-live-approval; do
  CODEX_EVIDENCE_ROOT="$(
    ensure_child_directory "$CODEX_EVIDENCE_ROOT" "$CODEX_EVIDENCE_COMPONENT"
  )"
done
CODEX_EVIDENCE_ROOT="$(cd "$CODEX_EVIDENCE_ROOT" && pwd -P)"
[[ "$CODEX_EVIDENCE_ROOT" == "$CODEX_EVIDENCE_MOUNT_ROOT/"* ]] \
  || fail "resolved evidence directory escaped T7 Shield"

CODEX_EVIDENCE_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
CODEX_EVIDENCE_RUN_DIRECTORY="$(
  /usr/bin/mktemp -d "$CODEX_EVIDENCE_ROOT/run-$CODEX_EVIDENCE_TIMESTAMP-XXXXXX"
)" || fail "could not allocate an append-never Codex evidence directory"
[[ "$CODEX_EVIDENCE_RUN_DIRECTORY" == "$CODEX_EVIDENCE_ROOT/run-"* ]] \
  || fail "Codex evidence allocation escaped its reviewed root"
/bin/chmod 700 "$CODEX_EVIDENCE_RUN_DIRECTORY"

set +e
"$CODEX_EVIDENCE_PACKAGER" "$@" --output "$CODEX_EVIDENCE_RUN_DIRECTORY"
CODEX_EVIDENCE_PACKAGE_EXIT=$?
set -e
if (( CODEX_EVIDENCE_PACKAGE_EXIT != 0 )); then
  echo "Codex live-approval evidence was not accepted." >&2
  echo "Partial evidence retained at: $CODEX_EVIDENCE_RUN_DIRECTORY" >&2
  exit "$CODEX_EVIDENCE_PACKAGE_EXIT"
fi

"$CODEX_EVIDENCE_VALIDATOR" \
  --evidence "$CODEX_EVIDENCE_RUN_DIRECTORY" \
  --require-accepted

echo "Codex live-approval evidence package: ACCEPTED"
echo "Evidence: $CODEX_EVIDENCE_RUN_DIRECTORY"
