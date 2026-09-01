#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

GENERATOR="scripts/ci/generate-ci-diagnostics.rb"
WORKFLOW=".github/workflows/ci.yml"
AUTHORITATIVE_TESTS="scripts/ci/run-authoritative-tests.sh"
test -x "$GENERATOR" || fail "CI diagnostic generator is missing or not executable"
test -x "$AUTHORITATIVE_TESTS" || fail "Authoritative test runner is missing or not executable"
ruby -c "$GENERATOR" >/dev/null || fail "CI diagnostic generator is not valid Ruby"
test -s "$WORKFLOW" || fail "CI workflow is missing"

diagnostics_line="$(rg -n 'name: Generate CI diagnostics' "$WORKFLOW" | cut -d: -f1)"
upload_line="$(rg -n 'name: Upload failed-run diagnostics' "$WORKFLOW" | cut -d: -f1)"
[[ -n "$diagnostics_line" && -n "$upload_line" && "$diagnostics_line" -lt "$upload_line" ]] \
  || fail "CI diagnostics must be generated before failed-run upload"
diagnostics_block="$(sed -n "${diagnostics_line},$((upload_line - 1))p" "$WORKFLOW")"
upload_block="$(sed -n "${upload_line},$((upload_line + 16))p" "$WORKFLOW")"
for invariant in \
  'if: always()' \
  './scripts/ci/generate-ci-diagnostics.rb' \
  'DIAGNOSTIC_ROOT="$(mktemp -d "${RUNNER_TEMP}/dev-island-ci-diagnostics.XXXXXX")"' \
  '--security-log "${SECURITY_LOG}"' \
  '--test-log "${TEST_LOG}"' \
  '--step '\''sparkle-update=${{ steps.sparkle_update.outcome }}'\''' \
  '--step '\''brand=${{ steps.brand.outcome }}'\''' \
  '${GITHUB_OUTPUT}' \
  '${GITHUB_STEP_SUMMARY}'; do
  rg -Fq -- "$invariant" <<<"$diagnostics_block" \
    || fail "Always-run CI diagnostic invariant missing: $invariant"
done
for invariant in \
  'if: ${{ failure() }}' \
  'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' \
  'path: ${{ steps.diagnostics.outputs.artifact_path }}' \
  'if-no-files-found: error' \
  'retention-days: 14' \
  'include-hidden-files: false'; do
  rg -Fq -- "$invariant" <<<"$upload_block" \
    || fail "Failed-run artifact invariant missing: $invariant"
done
if rg -q 'dev-island-(security|tests)\.log' <<<"$upload_block"; then
  fail "Raw CI logs must never be uploaded as diagnostics"
fi
checkout_line="$(rg -n 'name: Checkout' "$WORKFLOW" | cut -d: -f1)"
checkout_block="$(sed -n "${checkout_line},$((checkout_line + 6))p" "$WORKFLOW")"
rg -Fq 'persist-credentials: false' <<<"$checkout_block" \
  || fail "PR checkout must not persist the GitHub token for repository scripts"
dependencies_line="$(rg -n '^[[:space:]]+- name: Resolve dependencies$' "$WORKFLOW" | cut -d: -f1)"
dependencies_block="$(sed -n "${dependencies_line},$((dependencies_line + 14))p" "$WORKFLOW")"
for invariant in \
  'git ls-files --error-unmatch VERSION' \
  'git ls-files --error-unmatch scripts/release/validate-product-version.rb' \
  './scripts/release/validate-product-version.rb --version-file VERSION' \
  'git ls-files --error-unmatch Package.resolved' \
  'swift package resolve' \
  'git diff --exit-code -- Package.resolved'; do
  rg -Fq -- "$invariant" <<<"$dependencies_block" \
    || fail "Dependency/version source-identity boundary is missing: $invariant"
done
for step_id in \
  toolchain \
  dependencies \
  sparkle_update \
  security \
  tests \
  performance_build \
  app_build \
  bundle \
  brand \
  sbom \
  isolation \
  hygiene; do
  rg -q "^[[:space:]]+id: ${step_id}$" "$WORKFLOW" \
    || fail "Stable CI diagnostic step ID is missing: $step_id"
done
[[ "$(rg -c 'set -(o|euo) pipefail' "$WORKFLOW")" -ge 2 ]] \
  || fail "Security and test log capture must preserve pipeline failures"
test_line="$(rg -n '^[[:space:]]+- name: Test$' "$WORKFLOW" | cut -d: -f1)"
test_block="$(sed -n "${test_line},$((test_line + 14))p" "$WORKFLOW")"
for invariant in \
  'set -euo pipefail' \
  './scripts/ci/run-authoritative-tests.sh 2>&1 \' \
  '| tee "${RUNNER_TEMP}/dev-island-tests.log"'; do
  rg -Fq -- "$invariant" <<<"$test_block" \
    || fail "Test and stability log boundary is missing: $invariant"
done

TEMP_DIR="$(mktemp -d -t dev-island-ci-diagnostics-fixtures)"
AUTHORITATIVE_PID=""
AUTHORITATIVE_RELEASE=""
cleanup() {
  if [[ -n "$AUTHORITATIVE_PID" ]] && kill -0 "$AUTHORITATIVE_PID" 2>/dev/null; then
    [[ -n "$AUTHORITATIVE_RELEASE" ]] && : >"$AUTHORITATIVE_RELEASE"
    kill "$AUTHORITATIVE_PID" 2>/dev/null || true
    wait "$AUTHORITATIVE_PID" 2>/dev/null || true
  fi
  [[ "$TEMP_DIR" == /private/var/folders/*/T/dev-island-ci-diagnostics-fixtures.* \
     || "$TEMP_DIR" == /var/folders/*/T/dev-island-ci-diagnostics-fixtures.* \
     || "$TEMP_DIR" == /tmp/dev-island-ci-diagnostics-fixtures.* ]] \
    && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

FAKE_BIN="$TEMP_DIR/fake-bin"
FAKE_SWIFT_LOG="$TEMP_DIR/fake-swift.log"
AUTHORITATIVE_OUTPUT="$TEMP_DIR/authoritative-tests.output"
mkdir -m 700 "$FAKE_BIN"
ruby - "$FAKE_BIN/swift" <<'RUBY'
path = ARGV.fetch(0)
File.binwrite(path, <<~'BASH')
  #!/usr/bin/env bash
  set -euo pipefail
  : "${FAKE_SWIFT_LOG:?}"
  printf '%s\n' "$*" >>"$FAKE_SWIFT_LOG"
  if [[ "${FAKE_SWIFT_BLOCK_ON_FULL:-0}" == "1" && "$*" != *"--skip-build"* ]]; then
    : "${FAKE_SWIFT_READY:?}"
    : "${FAKE_SWIFT_RELEASE:?}"
    : >"$FAKE_SWIFT_READY"
    for ((attempt = 0; attempt < 250; attempt++)); do
      [[ -e "$FAKE_SWIFT_RELEASE" ]] && exit 0
      sleep 0.02
    done
    echo "fake Swift full-suite hold timed out" >&2
    exit 97
  fi
BASH
RUBY
chmod 700 "$FAKE_BIN/swift"
ruby - "$FAKE_BIN/IslandCoreCLI" <<'RUBY'
path = ARGV.fetch(0)
File.binwrite(path, <<~'BASH')
  #!/usr/bin/env bash
  set -euo pipefail
  [[ "$#" -eq 1 && "$1" == "local-hermetic-listener-check" ]] || exit 64
  printf '%s\n' \
    '[CLI] Hermetic local listener check' \
    '[CLI] listener=verified' \
    '[CLI] authorization=memory-only' \
    '[CLI] agent-routes=disabled' \
    '[CLI] result=verified'
BASH
RUBY
chmod 700 "$FAKE_BIN/IslandCoreCLI"
ruby - "$FAKE_BIN/find" <<'RUBY'
path = ARGV.fetch(0)
File.binwrite(path, <<~'BASH')
  #!/usr/bin/env bash
  set -euo pipefail
  : "${FAKE_HERMETIC_CLI:?}"
  if [[ "$*" == *"/tests-authoritative"* && "$*" == *"*/debug/IslandCoreCLI"* ]]; then
    printf '%s\n' "$FAKE_HERMETIC_CLI"
  else
    exec /usr/bin/find "$@"
  fi
BASH
RUBY
chmod 700 "$FAKE_BIN/find"

AUTHORITATIVE_READY="$TEMP_DIR/authoritative.ready"
AUTHORITATIVE_RELEASE="$TEMP_DIR/authoritative.release"
PATH="$FAKE_BIN:$PATH" \
  FAKE_SWIFT_LOG="$FAKE_SWIFT_LOG" \
  FAKE_SWIFT_BLOCK_ON_FULL=1 \
  FAKE_SWIFT_READY="$AUTHORITATIVE_READY" \
  FAKE_SWIFT_RELEASE="$AUTHORITATIVE_RELEASE" \
  FAKE_HERMETIC_CLI="$FAKE_BIN/IslandCoreCLI" \
  "$AUTHORITATIVE_TESTS" >"$AUTHORITATIVE_OUTPUT" 2>&1 &
AUTHORITATIVE_PID=$!

for ((attempt = 0; attempt < 250; attempt++)); do
  [[ -e "$AUTHORITATIVE_READY" ]] && break
  kill -0 "$AUTHORITATIVE_PID" 2>/dev/null \
    || fail "First authoritative test fixture exited before acquiring its graph"
  sleep 0.02
done
[[ -e "$AUTHORITATIVE_READY" ]] \
  || fail "First authoritative test fixture did not reach the held full suite"

CONTENDED_OUTPUT="$TEMP_DIR/authoritative-contended.output"
contended_started=$SECONDS
if PATH="$FAKE_BIN:$PATH" \
  FAKE_SWIFT_LOG="$FAKE_SWIFT_LOG" \
  FAKE_SWIFT_BLOCK_ON_FULL=1 \
  FAKE_SWIFT_READY="$AUTHORITATIVE_READY" \
  FAKE_SWIFT_RELEASE="$AUTHORITATIVE_RELEASE" \
  FAKE_HERMETIC_CLI="$FAKE_BIN/IslandCoreCLI" \
  "$AUTHORITATIVE_TESTS" >"$CONTENDED_OUTPUT" 2>&1; then
  fail "A concurrent authoritative test run entered the shared graph"
fi
(( SECONDS - contended_started <= 1 )) \
  || fail "A concurrent authoritative test run did not fail immediately"
[[ "$(wc -l <"$CONTENDED_OUTPUT" | tr -d ' ')" -eq 1 ]] \
  || fail "Contended authoritative test output must remain low-cardinality"
rg -Fxq \
  '::error::another authoritative test run is already using the shared test graph' \
  "$CONTENDED_OUTPUT" \
  || fail "Contended authoritative test run failed for the wrong reason"
[[ "$(wc -l <"$FAKE_SWIFT_LOG" | tr -d ' ')" -eq 1 ]] \
  || fail "A contended authoritative test run executed Swift"

: >"$AUTHORITATIVE_RELEASE"
wait "$AUTHORITATIVE_PID" \
  || fail "Authoritative test isolation fixture did not pass"
AUTHORITATIVE_PID=""

EXPECTED_SCRATCH="$ROOT/.build/tests-authoritative"
[[ "$(wc -l <"$FAKE_SWIFT_LOG" | tr -d ' ')" -eq 66 ]] \
  || fail "Authoritative test runner executed an unexpected Swift command count"
FIRST_INVOCATION="$(sed -n '1p' "$FAKE_SWIFT_LOG")"
[[ "$FIRST_INVOCATION" == \
  "test --disable-keychain --scratch-path $EXPECTED_SCRATCH --only-use-versions-from-resolved-file" ]] \
  || fail "Full suite did not use the isolated authoritative scratch"
if rg -v -F -- "--scratch-path $EXPECTED_SCRATCH" "$FAKE_SWIFT_LOG"; then
  fail "A Swift test invocation escaped the authoritative scratch"
fi
[[ "$(rg -Fc -- '--skip-build --filter' "$FAKE_SWIFT_LOG")" -eq 65 ]] \
  || fail "Stability repetitions did not reuse the built authoritative graph"
[[ "$(rg -Fc 'LocalLiveReadinessTests.testRepeatedFastVersionProcessesDoNotLoseTerminationOrOutput' "$FAKE_SWIFT_LOG")" -eq 20 ]] \
  || fail "Local version process repetitions drifted"
[[ "$(rg -Fc 'SourceAppResolverTests.testTmuxNavigatorKillsBackgroundDescendantAfterLeaderExits' "$FAKE_SWIFT_LOG")" -eq 20 ]] \
  || fail "tmux process repetitions drifted"
[[ "$(rg -Fc 'CodexHookTrustProbeTests' "$FAKE_SWIFT_LOG")" -eq 5 ]] \
  || fail "Codex trust process repetitions drifted"
[[ "$(rg -Fc 'TaskStoreManusLifecycleTests' "$FAKE_SWIFT_LOG")" -eq 20 ]] \
  || fail "Sleep/wake lifecycle repetitions drifted"
for accepted in \
  'Local version probe stability: PASS (20 rounds, 240 child processes)' \
  'Hermetic local listener: PASS (10 rounds, memory-only authorization, zero Agent routes)' \
  'tmux descendant cleanup stability: PASS (20 rounds)' \
  'Codex Hook trust process stability: PASS (5 rounds)' \
  'Sleep/wake lifecycle stability: PASS (20 rounds)' \
  'Authoritative test graph: PASS'; do
  rg -Fq "$accepted" "$AUTHORITATIVE_OUTPUT" \
    || fail "Authoritative test runner omitted completion state: $accepted"
done

LOCK_FIXTURE_ROOT="$TEMP_DIR/authoritative-lock-fixtures"
LOCK_FIXTURE_RUNNER="$LOCK_FIXTURE_ROOT/scripts/ci/run-authoritative-tests.sh"
LOCK_FIXTURE_FILE="$LOCK_FIXTURE_ROOT/.build/tests-authoritative.lock"
mkdir -m 700 "$LOCK_FIXTURE_ROOT"
mkdir -m 700 "$LOCK_FIXTURE_ROOT/scripts" "$LOCK_FIXTURE_ROOT/scripts/ci"
mkdir -m 700 "$LOCK_FIXTURE_ROOT/.build" \
  "$LOCK_FIXTURE_ROOT/.build/tests-authoritative"
cp "$AUTHORITATIVE_TESTS" "$LOCK_FIXTURE_RUNNER"
chmod 700 "$LOCK_FIXTURE_RUNNER"

expect_lock_failure() {
  local case_name="$1"
  local expected="$2"
  local output="$TEMP_DIR/authoritative-lock-${case_name}.output"

  if "$LOCK_FIXTURE_RUNNER" >"$output" 2>&1; then
    fail "Unsafe authoritative lock fixture passed: $case_name"
  fi
  [[ "$(wc -l <"$output" | tr -d ' ')" -eq 1 ]] \
    || fail "Unsafe authoritative lock output must remain low-cardinality: $case_name"
  rg -Fxq "::error::$expected" "$output" \
    || fail "Unsafe authoritative lock fixture failed for the wrong reason: $case_name"
}

LOCK_SYMLINK_TARGET="$LOCK_FIXTURE_ROOT/lock-symlink-target"
: >"$LOCK_SYMLINK_TARGET"
chmod 600 "$LOCK_SYMLINK_TARGET"
ln -s "$LOCK_SYMLINK_TARGET" "$LOCK_FIXTURE_FILE"
expect_lock_failure lock-symlink \
  "authoritative test lock must not be a symbolic link"
unlink "$LOCK_FIXTURE_FILE"
unlink "$LOCK_SYMLINK_TARGET"

mkdir -m 700 "$LOCK_FIXTURE_FILE"
expect_lock_failure lock-directory \
  "authoritative test lock must be a regular file"
rmdir "$LOCK_FIXTURE_FILE"

LOCK_HARDLINK_TARGET="$LOCK_FIXTURE_ROOT/lock-hardlink-target"
: >"$LOCK_HARDLINK_TARGET"
chmod 600 "$LOCK_HARDLINK_TARGET"
ln "$LOCK_HARDLINK_TARGET" "$LOCK_FIXTURE_FILE"
expect_lock_failure lock-hardlink \
  "authoritative test lock must have exactly one hard link"
unlink "$LOCK_FIXTURE_FILE"
unlink "$LOCK_HARDLINK_TARGET"

: >"$LOCK_FIXTURE_FILE"
chmod 644 "$LOCK_FIXTURE_FILE"
expect_lock_failure lock-mode \
  "authoritative test lock permissions must be 0600"
unlink "$LOCK_FIXTURE_FILE"

printf 'not-empty\n' >"$LOCK_FIXTURE_FILE"
chmod 600 "$LOCK_FIXTURE_FILE"
expect_lock_failure lock-content \
  "authoritative test lock must remain empty"
unlink "$LOCK_FIXTURE_FILE"

SECURITY_LOG="$TEMP_DIR/security.log"
TEST_LOG="$TEMP_DIR/test.log"
printf '%s\n' \
  'Localization invariants: PASS' \
  'Legal and data-flow invariants: PASS' \
  '::error::TOP_SECRET_DIAGNOSTIC_FIXTURE' \
  'TOP_SECRET_DIAGNOSTIC_FIXTURE' >"$SECURITY_LOG"
printf '%s\n' \
  "Test Case '-[IslandCoreTests.ExampleTests testFailure]' failed (0.001 seconds)." \
  'assertion contained TOP_SECRET_DIAGNOSTIC_FIXTURE' \
  'Executed 479 tests, with 1 failures (0 unexpected) in 9.000 seconds' >"$TEST_LOG"

COMMON_ARGUMENTS=(
  --repository sheepxux/Dev-Island
  --run-id 32810556735
  --run-attempt 2
  --event pull_request
  --ref refs/pull/42/merge
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480
  --runner-os macOS
  --runner-arch ARM64
  --security-log "$SECURITY_LOG"
  --test-log "$TEST_LOG"
)

FAILURE_OUTPUT="$TEMP_DIR/failure-output"
"$GENERATOR" \
  --output-dir "$FAILURE_OUTPUT" \
  "${COMMON_ARGUMENTS[@]}" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=failure \
  --step performance-build=skipped \
  --step app-build=skipped \
  --step bundle=skipped \
  --step brand=skipped \
  --step sbom=skipped \
  --step isolation=skipped \
  --step hygiene=skipped >/dev/null

[[ "$(find "$FAILURE_OUTPUT" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 2 ]] \
  || fail "CI diagnostic bundle must contain exactly two regular files"
[[ "$(stat -f '%Lp' "$FAILURE_OUTPUT")" == "700" ]] \
  || fail "CI diagnostic directory mode must be 0700"
for file in "$FAILURE_OUTPUT/summary.json" "$FAILURE_OUTPUT/README.md"; do
  [[ "$(stat -f '%Lp' "$file")" == "600" ]] \
    || fail "CI diagnostic file mode must be 0600: ${file##*/}"
done

ruby -r json - "$FAILURE_OUTPUT/summary.json" <<'RUBY'
summary = JSON.parse(File.binread(ARGV.fetch(0)))
abort "diagnostic schema mismatch" unless summary["schemaVersion"] == 2
abort "failure status mismatch" unless summary["status"] == "failure"
abort "first failure mismatch" unless summary.dig("firstFailure", "id") == "tests"
abort "test aggregate mismatch" unless summary.dig("tests", "executed") == 479 && summary.dig("tests", "failures") == 1
abort "failed case mismatch" unless summary.dig("tests", "failedCases") == ["-[IslandCoreTests.ExampleTests testFailure]"]
abort "test log source mismatch" unless summary.dig("tests", "sourceStatus") == "available"
abort "security gate mismatch" unless summary.dig("security", "passedGates") == ["Localization invariants", "Legal and data-flow invariants"]
abort "security log source mismatch" unless summary.dig("security", "sourceStatus") == "available"
abort "security error marker mismatch" unless summary.dig("security", "errorMarkerCount") == 1
abort "privacy contract mismatch" unless summary.fetch("privacy").values.none?
RUBY

if rg -n 'TOP_SECRET_DIAGNOSTIC_FIXTURE|assertion contained' "$FAILURE_OUTPUT"; then
  fail "CI diagnostic output leaked raw log content"
fi
rg -Fq './scripts/ci/run-authoritative-tests.sh' "$FAILURE_OUTPUT/README.md" \
  || fail "CI diagnostic README must include the first failure reproduction command"

SUCCESS_TEST_LOG="$TEMP_DIR/success-test.log"
printf '%s\n' 'Executed 479 tests, with 0 failures (0 unexpected) in 9.000 seconds' \
  >"$SUCCESS_TEST_LOG"
SUCCESS_OUTPUT="$TEMP_DIR/success-output"
"$GENERATOR" \
  --output-dir "$SUCCESS_OUTPUT" \
  --repository sheepxux/Dev-Island \
  --run-id 32810556736 \
  --run-attempt 1 \
  --event push \
  --ref refs/heads/main \
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480 \
  --runner-os macOS \
  --runner-arch ARM64 \
  --security-log "$SECURITY_LOG" \
  --test-log "$SUCCESS_TEST_LOG" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=success \
  --step performance-build=success \
  --step app-build=success \
  --step bundle=success \
  --step brand=success \
  --step sbom=success \
  --step isolation=success \
  --step hygiene=success >/dev/null
ruby -r json -e \
  's=JSON.parse(File.binread(ARGV.fetch(0))); abort unless s["status"] == "success" && s["firstFailure"].nil? && s.dig("tests", "failures") == 0' \
  "$SUCCESS_OUTPUT/summary.json"

APP_BUILD_FAILURE_OUTPUT="$TEMP_DIR/app-build-failure-output"
"$GENERATOR" \
  --output-dir "$APP_BUILD_FAILURE_OUTPUT" \
  --repository sheepxux/Dev-Island \
  --run-id 32810556741 \
  --run-attempt 1 \
  --event pull_request \
  --ref refs/pull/44/merge \
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480 \
  --runner-os macOS \
  --runner-arch ARM64 \
  --security-log "$SECURITY_LOG" \
  --test-log "$SUCCESS_TEST_LOG" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=success \
  --step performance-build=success \
  --step app-build=failure \
  --step bundle=skipped \
  --step brand=skipped \
  --step sbom=skipped \
  --step isolation=skipped \
  --step hygiene=skipped >/dev/null
ruby -r json - "$APP_BUILD_FAILURE_OUTPUT/summary.json" <<'RUBY'
summary = JSON.parse(File.binread(ARGV.fetch(0)))
abort "App-build first failure mismatch" unless summary.dig("firstFailure", "id") == "app-build"
abort "App-build label mismatch" unless summary.dig("firstFailure", "label") ==
  "Universal app build + Production launch smoke"
abort "App-build reproduction mismatch" unless summary.dig("firstFailure", "reproduce").include?(
  "production-launch-smoke"
)
RUBY
rg -Fq 'Universal app build + Production launch smoke' \
  "$APP_BUILD_FAILURE_OUTPUT/README.md" \
  || fail "App-build diagnostic label does not include the Production launch smoke"
rg -Fq 'production-launch-smoke' "$APP_BUILD_FAILURE_OUTPUT/README.md" \
  || fail "App-build diagnostic reproduction omits the Production launch smoke"

BRAND_FAILURE_OUTPUT="$TEMP_DIR/brand-failure-output"
"$GENERATOR" \
  --output-dir "$BRAND_FAILURE_OUTPUT" \
  --repository sheepxux/Dev-Island \
  --run-id 32810556737 \
  --run-attempt 1 \
  --event pull_request \
  --ref refs/pull/43/merge \
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480 \
  --runner-os macOS \
  --runner-arch ARM64 \
  --security-log "$SECURITY_LOG" \
  --test-log "$SUCCESS_TEST_LOG" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=success \
  --step performance-build=success \
  --step app-build=success \
  --step bundle=success \
  --step brand=failure \
  --step sbom=skipped \
  --step isolation=skipped \
  --step hygiene=skipped >/dev/null
ruby -r json - "$BRAND_FAILURE_OUTPUT/summary.json" <<'RUBY'
summary = JSON.parse(File.binread(ARGV.fetch(0)))
abort "brand failure status mismatch" unless summary["status"] == "failure"
abort "brand first failure mismatch" unless summary.dig("firstFailure", "id") == "brand"
abort "brand reproduction mismatch" unless summary.dig("firstFailure", "reproduce") ==
  "Review the Verify bundled brand asset inventory step in .github/workflows/ci.yml"
RUBY

if "$GENERATOR" \
  --output-dir "$TEMP_DIR/reordered-output" \
  "${COMMON_ARGUMENTS[@]}" \
  --step tests=failure \
  --step toolchain=success >/dev/null 2>&1; then
  fail "Incomplete/reordered CI step set unexpectedly passed"
fi

ln -s "$TEST_LOG" "$TEMP_DIR/symlink-test.log"
SYMLINK_OUTPUT="$TEMP_DIR/symlink-output"
"$GENERATOR" \
  --output-dir "$SYMLINK_OUTPUT" \
  --repository sheepxux/Dev-Island \
  --run-id 32810556738 \
  --run-attempt 1 \
  --event push \
  --ref refs/heads/main \
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480 \
  --runner-os macOS \
  --runner-arch ARM64 \
  --security-log "$SECURITY_LOG" \
  --test-log "$TEMP_DIR/symlink-test.log" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=success \
  --step performance-build=success \
  --step app-build=success \
  --step bundle=success \
  --step brand=success \
  --step sbom=success \
  --step isolation=success \
  --step hygiene=success >/dev/null
ruby -r json - "$SYMLINK_OUTPUT/summary.json" <<'RUBY'
summary = JSON.parse(File.binread(ARGV.fetch(0)))
abort "symlink fixture should preserve the CI result" unless summary["status"] == "success"
abort "symlink log unexpectedly available" unless summary.dig("tests", "available") == false
abort "symlink log source mismatch" unless summary.dig("tests", "sourceStatus") == "unsafe-file"
RUBY
if rg -n 'TOP_SECRET_DIAGNOSTIC_FIXTURE|assertion contained' "$SYMLINK_OUTPUT"; then
  fail "Symbolic-link CI diagnostic fixture leaked raw log content"
fi

OVERSIZED_TEST_LOG="$TEMP_DIR/oversized-test.log"
ruby -e 'File.open(ARGV.fetch(0), "wb", 0o600) { |file| file.truncate(17 * 1_024 * 1_024) }' \
  "$OVERSIZED_TEST_LOG"
OVERSIZED_OUTPUT="$TEMP_DIR/oversized-output"
"$GENERATOR" \
  --output-dir "$OVERSIZED_OUTPUT" \
  --repository sheepxux/Dev-Island \
  --run-id 32810556739 \
  --run-attempt 1 \
  --event push \
  --ref refs/heads/main \
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480 \
  --runner-os macOS \
  --runner-arch ARM64 \
  --security-log "$SECURITY_LOG" \
  --test-log "$OVERSIZED_TEST_LOG" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=success \
  --step performance-build=success \
  --step app-build=success \
  --step bundle=success \
  --step brand=success \
  --step sbom=success \
  --step isolation=success \
  --step hygiene=success >/dev/null
ruby -r json - "$OVERSIZED_OUTPUT/summary.json" <<'RUBY'
summary = JSON.parse(File.binread(ARGV.fetch(0)))
abort "oversized fixture should preserve the CI result" unless summary["status"] == "success"
abort "oversized log unexpectedly available" unless summary.dig("tests", "available") == false
abort "oversized log source mismatch" unless summary.dig("tests", "sourceStatus") == "oversized"
RUBY

HARDLINK_TEST_LOG="$TEMP_DIR/hardlink-test.log"
cp "$SUCCESS_TEST_LOG" "$HARDLINK_TEST_LOG"
ln "$HARDLINK_TEST_LOG" "$TEMP_DIR/hardlink-alias.log"
HARDLINK_OUTPUT="$TEMP_DIR/hardlink-output"
"$GENERATOR" \
  --output-dir "$HARDLINK_OUTPUT" \
  --repository sheepxux/Dev-Island \
  --run-id 32810556740 \
  --run-attempt 1 \
  --event push \
  --ref refs/heads/main \
  --sha 42f889507807e81eb920bcdb6f0cf532eb0ce480 \
  --runner-os macOS \
  --runner-arch ARM64 \
  --security-log "$SECURITY_LOG" \
  --test-log "$HARDLINK_TEST_LOG" \
  --step toolchain=success \
  --step dependencies=success \
  --step sparkle-update=success \
  --step security=success \
  --step tests=success \
  --step performance-build=success \
  --step app-build=success \
  --step bundle=success \
  --step brand=success \
  --step sbom=success \
  --step isolation=success \
  --step hygiene=success >/dev/null
ruby -r json - "$HARDLINK_OUTPUT/summary.json" <<'RUBY'
summary = JSON.parse(File.binread(ARGV.fetch(0)))
abort "hard-link fixture should preserve the CI result" unless summary["status"] == "success"
abort "hard-link log unexpectedly available" unless summary.dig("tests", "available") == false
abort "hard-link log source mismatch" unless summary.dig("tests", "sourceStatus") == "unsafe-file"
RUBY

rg -Fq './scripts/ci/verify-performance-fixture-isolation.sh PRODUCTION_APP PERFORMANCE_APP' \
  "$SUCCESS_OUTPUT/summary.json" \
  || fail "Performance isolation reproduction parameters are reordered"

echo "CI diagnostics fixtures: PASS"
