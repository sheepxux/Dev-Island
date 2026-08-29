#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "error: $1" >&2
  exit 1
}

[[ $# -eq 0 ]] || {
  echo "Usage: audit-github-repository-controls.sh" >&2
  exit 64
}

REPOSITORY="sheepxux/Dev-Island"
BRANCH="main"
VALIDATOR="$ROOT/scripts/qa/validate-github-repository-controls.rb"

command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required"
test -x "$VALIDATOR" || fail "repository-controls validator is unavailable"
gh auth status --hostname github.com >/dev/null 2>&1 \
  || fail "GitHub CLI is not authenticated for github.com"

TEMP_DIR="$(mktemp -d -t dev-island-github-controls)"
cleanup() {
  [[ "$TEMP_DIR" == /private/var/folders/*/T/dev-island-github-controls.* \
     || "$TEMP_DIR" == /var/folders/*/T/dev-island-github-controls.* \
     || "$TEMP_DIR" == /tmp/dev-island-github-controls.* ]] \
    && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

classify_api_failure() {
  local failure_output="$1"

  # gh's stderr can contain request URLs, account names, or upstream response
  # text. It is inspected only inside the private temporary directory and is
  # never echoed. Oversized or non-regular diagnostics stay unclassified.
  local failure_size
  failure_size="$(wc -c <"$failure_output" 2>/dev/null | tr -d ' ' || printf '0')"
  if [[ ! "$failure_size" =~ ^[0-9]+$ ]] \
     || (( failure_size < 1 || failure_size > 65536 )); then
    printf '%s\n' "unexpected GitHub API failure"
    return
  fi

  if LC_ALL=C grep -Eiq \
    'HTTP[[:space:]]+429|rate[ -]?limit|secondary rate limit|abuse detection' \
    "$failure_output"; then
    printf '%s\n' "GitHub API rate limited"
  elif LC_ALL=C grep -Eiq \
    'HTTP[[:space:]]+401|bad credentials|requires authentication|authentication required|not authenticated|gh auth login|token[^[:cntrl:]]*expired' \
    "$failure_output"; then
    printf '%s\n' "GitHub authentication required"
  elif LC_ALL=C grep -Eiq \
    'HTTP[[:space:]]+(403|404)|resource not accessible|must have admin|administration[^[:cntrl:]]*access|not found' \
    "$failure_output"; then
    printf '%s\n' "repository administration read access required"
  elif LC_ALL=C grep -Eiq \
    'HTTP[[:space:]]+5[0-9][0-9]|connection reset|could not resolve|failed to connect|connection refused|network is unreachable|no route to host|TLS handshake timeout|i/o timeout|error connecting to|temporary failure in name resolution|service unavailable' \
    "$failure_output"; then
    printf '%s\n' "GitHub API network unavailable"
  else
    printf '%s\n' "unexpected GitHub API failure"
  fi
}

FETCH_INDEX=0

fetch() {
  local endpoint="$1"
  local output="$2"
  local label="$3"
  local failure_output="$TEMP_DIR/gh-api-failure-${FETCH_INDEX}.log"
  local classification
  FETCH_INDEX=$((FETCH_INDEX + 1))

  if gh api "$endpoint" >"$output" 2>"$failure_output"; then
    rm "$failure_output"
    return
  fi

  classification="$(classify_api_failure "$failure_output")"
  fail "could not read ${label}: ${classification}"
}

BRANCH_JSON="$TEMP_DIR/branch-protection.json"
ACTIONS_JSON="$TEMP_DIR/actions-permissions.json"
SELECTED_JSON="$TEMP_DIR/selected-actions.json"
WORKFLOW_JSON="$TEMP_DIR/workflow-permissions.json"
REPOSITORY_JSON="$TEMP_DIR/repository.json"

fetch "repos/${REPOSITORY}/branches/${BRANCH}/protection" \
  "$BRANCH_JSON" "main branch protection"
fetch "repos/${REPOSITORY}/actions/permissions" \
  "$ACTIONS_JSON" "Actions permissions"
fetch "repos/${REPOSITORY}/actions/permissions/workflow" \
  "$WORKFLOW_JSON" "default workflow permissions"
fetch "repos/${REPOSITORY}" "$REPOSITORY_JSON" "repository security settings"

if ruby -r json -e \
  'exit(JSON.parse(File.binread(ARGV.fetch(0)))["allowed_actions"] == "selected" ? 0 : 1)' \
  "$ACTIONS_JSON"; then
  fetch "repos/${REPOSITORY}/actions/permissions/selected-actions" \
    "$SELECTED_JSON" "selected Actions allowlist"
else
  printf '{}\n' >"$SELECTED_JSON"
fi

"$VALIDATOR" \
  --branch-protection "$BRANCH_JSON" \
  --actions-permissions "$ACTIONS_JSON" \
  --selected-actions "$SELECTED_JSON" \
  --workflow-permissions "$WORKFLOW_JSON" \
  --repository "$REPOSITORY_JSON"
