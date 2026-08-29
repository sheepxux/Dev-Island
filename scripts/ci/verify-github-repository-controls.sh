#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

VALIDATOR="scripts/qa/validate-github-repository-controls.rb"
AUDITOR="scripts/qa/audit-github-repository-controls.sh"
DEPENDABOT=".github/dependabot.yml"

test -x "$VALIDATOR" || fail "GitHub repository-controls validator is missing"
test -x "$AUDITOR" || fail "Read-only GitHub repository-controls auditor is missing"
test -f "$DEPENDABOT" || fail "Dependabot configuration is missing"
ruby -c "$VALIDATOR" >/dev/null || fail "GitHub repository-controls validator is not valid Ruby"
bash -n "$AUDITOR" || fail "GitHub repository-controls auditor is not valid Bash"

for endpoint in \
  'branches/${BRANCH}/protection' \
  'actions/permissions"' \
  'actions/permissions/workflow' \
  'actions/permissions/selected-actions'; do
  rg -Fq "$endpoint" "$AUDITOR" \
    || fail "Read-only repository-controls auditor endpoint is missing: $endpoint"
done
if rg -q -- '--method|--input|--raw-field|(^|[[:space:]])-X([[:space:]]|$)|(^|[[:space:]])-f([[:space:]]|$)' "$AUDITOR"; then
  fail "Repository-controls auditor must remain GET-only"
fi
for classification in \
  'GitHub API network unavailable' \
  'GitHub authentication required' \
  'repository administration read access required' \
  'GitHub API rate limited' \
  'unexpected GitHub API failure'; do
  rg -Fq "$classification" "$AUDITOR" \
    || fail "Repository-controls auditor failure classification is missing: $classification"
done
rg -Fq '2>"$failure_output"' "$AUDITOR" \
  || fail "Repository-controls auditor must isolate raw GitHub API diagnostics"

ruby -r yaml - "$DEPENDABOT" <<'RUBY'
path = ARGV.fetch(0)
configuration = YAML.safe_load(File.binread(path))
abort "Dependabot root schema is invalid" unless configuration.is_a?(Hash) && configuration["version"] == 2
updates = configuration["updates"]
abort "Dependabot updates are invalid" unless updates.is_a?(Array) && updates.length == 2
expected = ["github-actions", "swift"]
abort "Dependabot ecosystems are incomplete" unless updates.map { |entry| entry["package-ecosystem"] }.sort == expected
updates.each do |entry|
  abort "Dependabot directory must be the repository root" unless entry["directory"] == "/"
  abort "Dependabot must run weekly" unless entry.dig("schedule", "interval") == "weekly"
  abort "Dependabot pull-request bound is invalid" unless entry["open-pull-requests-limit"].is_a?(Integer) && entry["open-pull-requests-limit"].between?(1, 10)
  groups = entry["groups"]
  abort "Dependabot updates must be grouped" unless groups.is_a?(Hash) && groups.length == 1 && groups.values.first["patterns"] == ["*"]
end
RUBY

TEMP_DIR="$(mktemp -d -t dev-island-github-controls-fixtures)"
cleanup() {
  [[ "$TEMP_DIR" == /private/var/folders/*/T/dev-island-github-controls-fixtures.* \
     || "$TEMP_DIR" == /var/folders/*/T/dev-island-github-controls-fixtures.* \
     || "$TEMP_DIR" == /tmp/dev-island-github-controls-fixtures.* ]] \
    && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

ruby -r json - "$TEMP_DIR" <<'RUBY'
directory = ARGV.fetch(0)
write = ->(name, value) {
  File.binwrite(File.join(directory, name), JSON.generate(value) + "\n")
}

safe_branch = {
  "required_status_checks" => {
    "strict" => true,
    "checks" => [{"context" => "Tests, security, universal build", "app_id" => 15_368}],
  },
  "required_pull_request_reviews" => {
    "required_approving_review_count" => 1,
    "dismiss_stale_reviews" => true,
    "require_last_push_approval" => true,
  },
  "enforce_admins" => {"enabled" => true},
  "required_conversation_resolution" => {"enabled" => true},
  "required_linear_history" => {"enabled" => true},
  "allow_force_pushes" => {"enabled" => false},
  "allow_deletions" => {"enabled" => false},
}
safe_actions = {
  "enabled" => true,
  "allowed_actions" => "selected",
  "sha_pinning_required" => true,
}
safe_selected = {
  "github_owned_allowed" => true,
  "verified_allowed" => false,
  "patterns_allowed" => [
    "softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65",
  ],
}
safe_workflow = {
  "default_workflow_permissions" => "read",
  "can_approve_pull_request_reviews" => false,
}
safe_repository = {
  "security_and_analysis" => {
    "secret_scanning" => {"status" => "enabled"},
    "secret_scanning_push_protection" => {"status" => "enabled"},
    "dependabot_security_updates" => {"status" => "enabled"},
  },
}

write.call("safe-branch.json", safe_branch)
write.call("safe-actions.json", safe_actions)
write.call("safe-selected.json", safe_selected)
write.call("safe-workflow.json", safe_workflow)
write.call("safe-repository.json", safe_repository)

unsafe_branch = safe_branch.merge(
  "required_status_checks" => nil,
  "required_pull_request_reviews" => nil,
  "required_conversation_resolution" => {"enabled" => false}
)
unsafe_actions = safe_actions.merge(
  "allowed_actions" => "all",
  "sha_pinning_required" => false
)
unsafe_repository = {
  "security_and_analysis" => safe_repository.fetch("security_and_analysis").merge(
    "dependabot_security_updates" => {"status" => "disabled"}
  ),
}
write.call("unsafe-branch.json", unsafe_branch)
write.call("unsafe-actions.json", unsafe_actions)
write.call("unsafe-repository.json", unsafe_repository)
RUBY

run_validator() {
  local branch="$1"
  local actions="$2"
  local repository="$3"
  "$VALIDATOR" \
    --branch-protection "$branch" \
    --actions-permissions "$actions" \
    --selected-actions "$TEMP_DIR/safe-selected.json" \
    --workflow-permissions "$TEMP_DIR/safe-workflow.json" \
    --repository "$repository"
}

run_validator \
  "$TEMP_DIR/safe-branch.json" \
  "$TEMP_DIR/safe-actions.json" \
  "$TEMP_DIR/safe-repository.json" >/dev/null \
  || fail "Secure GitHub repository-controls fixture did not pass"

if run_validator \
  "$TEMP_DIR/unsafe-branch.json" \
  "$TEMP_DIR/unsafe-actions.json" \
  "$TEMP_DIR/unsafe-repository.json" >"$TEMP_DIR/unsafe.output" 2>&1; then
  fail "Unsafe GitHub repository-controls fixture unexpectedly passed"
fi
for finding in B01 B04 B09 A02 A06 S04; do
  rg -q "^${finding}:" "$TEMP_DIR/unsafe.output" \
    || fail "Unsafe repository-controls fixture omitted finding: $finding"
done
[[ "$(rg -c '^[A-Z][0-9]{2}:' "$TEMP_DIR/unsafe.output")" -eq 6 ]] \
  || fail "Unsafe repository-controls fixture produced an unexpected finding set"

printf '{malformed}\n' >"$TEMP_DIR/malformed.json"
if run_validator \
  "$TEMP_DIR/malformed.json" \
  "$TEMP_DIR/safe-actions.json" \
  "$TEMP_DIR/safe-repository.json" >/dev/null 2>&1; then
  fail "Malformed repository-controls JSON unexpectedly passed"
fi

ln -s "$TEMP_DIR/safe-branch.json" "$TEMP_DIR/symlink-branch.json"
if run_validator \
  "$TEMP_DIR/symlink-branch.json" \
  "$TEMP_DIR/safe-actions.json" \
  "$TEMP_DIR/safe-repository.json" >/dev/null 2>&1; then
  fail "Symbolic-link repository-controls snapshot unexpectedly passed"
fi

FAKE_BIN="$TEMP_DIR/fake-bin"
mkdir -m 700 "$FAKE_BIN"
cat >"$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

scenario="${FAKE_GH_SCENARIO:-success}"
command_name="${1:-}"

if [[ "$command_name" == "auth" ]]; then
  exit 0
fi

[[ "$command_name" == "api" && $# -eq 2 ]] || exit 64
endpoint="$2"

case "$scenario" in
  connection-reset)
    printf '%s\n' 'connection reset by peer: https://api.github.com/private?token=DO-NOT-PRINT-NETWORK' >&2
    exit 1
    ;;
  http-401)
    printf '%s\n' 'gh: Bad credentials (HTTP 401) DO-NOT-PRINT-AUTH' >&2
    exit 1
    ;;
  http-403)
    printf '%s\n' 'gh: Resource not accessible by integration (HTTP 403) DO-NOT-PRINT-403' >&2
    exit 1
    ;;
  http-404)
    printf '%s\n' 'gh: Not Found (HTTP 404) DO-NOT-PRINT-404' >&2
    exit 1
    ;;
  rate-limit)
    printf '%s\n' 'gh: API rate limit exceeded (HTTP 403) DO-NOT-PRINT-RATE' >&2
    exit 1
    ;;
  unexpected)
    printf '%s\n' 'gh: opaque upstream failure DO-NOT-PRINT-UNEXPECTED' >&2
    exit 1
    ;;
  success) ;;
  *) exit 64 ;;
esac

case "$endpoint" in
  */branches/main/protection)
    printf '%s\n' '{"required_status_checks":{"strict":true,"checks":[{"context":"Tests, security, universal build","app_id":15368}]},"required_pull_request_reviews":{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_last_push_approval":true},"enforce_admins":{"enabled":true},"required_conversation_resolution":{"enabled":true},"required_linear_history":{"enabled":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'
    ;;
  */actions/permissions/selected-actions)
    printf '%s\n' '{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65"]}'
    ;;
  */actions/permissions/workflow)
    printf '%s\n' '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
    ;;
  */actions/permissions)
    printf '%s\n' '{"enabled":true,"allowed_actions":"selected","sha_pinning_required":true}'
    ;;
  repos/*)
    printf '%s\n' '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"dependabot_security_updates":{"status":"enabled"}}}'
    ;;
  *) exit 64 ;;
esac
FAKE_GH
chmod 700 "$FAKE_BIN/gh"

AUDITOR_PATH="$(cd "$(dirname "$AUDITOR")" && pwd)/$(basename "$AUDITOR")"
if ! PATH="$FAKE_BIN:$PATH" FAKE_GH_SCENARIO=success \
  "$AUDITOR_PATH" >"$TEMP_DIR/auditor-success.output" 2>&1; then
  fail "Successful fake-gh repository audit did not pass"
fi
rg -Fxq 'GitHub repository controls: PASS' "$TEMP_DIR/auditor-success.output" \
  || fail "Successful fake-gh repository audit produced an unexpected result"

verify_auditor_failure() {
  local scenario="$1"
  local classification="$2"
  local output="$TEMP_DIR/auditor-${scenario}.output"

  if PATH="$FAKE_BIN:$PATH" FAKE_GH_SCENARIO="$scenario" \
    "$AUDITOR_PATH" >"$output" 2>&1; then
    fail "Fake-gh repository audit unexpectedly passed: $scenario"
  fi
  rg -Fxq "error: could not read main branch protection: ${classification}" "$output" \
    || fail "Fake-gh repository audit was misclassified: $scenario"
  [[ "$(wc -l <"$output" | tr -d ' ')" -eq 1 ]] \
    || fail "Fake-gh repository audit emitted unbounded diagnostics: $scenario"
  if rg -q 'DO-NOT-PRINT|api\.github\.com|token=' "$output"; then
    fail "Fake-gh repository audit exposed raw diagnostics: $scenario"
  fi
}

verify_auditor_failure connection-reset 'GitHub API network unavailable'
verify_auditor_failure http-401 'GitHub authentication required'
verify_auditor_failure http-403 'repository administration read access required'
verify_auditor_failure http-404 'repository administration read access required'
verify_auditor_failure rate-limit 'GitHub API rate limited'
verify_auditor_failure unexpected 'unexpected GitHub API failure'

echo "GitHub repository controls fixtures: PASS"
