#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

ANALYZER="scripts/qa/summarize-performance-samples.sh"
ANIMATION_HITCH_ANALYZER="scripts/qa/summarize-animation-hitches.rb"
SAMPLER="scripts/qa/measure-app-performance.sh"
SCREEN_PROBE="scripts/qa/display-session-state.swift"
DOT_MATRIX="IslandAppLib/Views/Components/AnimatedDotMatrixMark.swift"
DOT_MATRIX_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/DotMatrixRenderingTests.swift"
ISLAND_WINDOW="IslandAppLib/Windows/IslandWindow.swift"
ISLAND_WINDOW_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/IslandWindowMouseTrackingPolicyTests.swift"
ISLAND_PRESENTATION="IslandAppLib/Presentation/IslandPresentationSnapshot.swift"
ISLAND_PRESENTATION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/IslandPresentationSnapshotTests.swift"
ISLAND_ROOT="IslandAppLib/Views/Island/IslandRootView.swift"
MOTION="IslandAppLib/Theme/Animations.swift"
PANEL_ACTIVITY_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/IslandPanelActivityTimingTests.swift"
ACTION_REQUEST_PRESENTATION="IslandAppLib/Presentation/ActionRequestPresentationPolicy.swift"
ACTION_REQUEST_PRESENTATION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/ActionRequestPresentationPolicyTests.swift"
NOTCH_PANEL="IslandAppLib/Views/NotchPanel/NotchPanelView.swift"
TASK_CARD="IslandAppLib/Views/NotchPanel/TaskCard.swift"
ACTION_REQUEST_SURFACE="IslandAppLib/Views/NotchPanel/ActionRequestSurface.swift"
PANEL_CLOCK_PRESENTATION="IslandAppLib/Presentation/PanelClockPresentation.swift"
PANEL_CLOCK_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/PanelClockPresentationTests.swift"
PLAN_RENDERING="IslandAppLib/Presentation/PlanMarkdownRendering.swift"
PLAN_RENDERING_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/PlanMarkdownPresentationTests.swift"
VISUAL_SNAPSHOT_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/VisualSnapshotTests.swift"
ACTION_REQUEST_MODEL="IslandCore/Sources/IslandCore/Models/AgentActionRequest.swift"
PLAN_REVIEW_TESTS="IslandCoreTests/Sources/IslandCoreTests/ClaudePlanReviewHookTests.swift"
AGENT_INSTALLATION="IslandAppLib/Presentation/LocalAgentInstallationPresentation.swift"
AGENT_INSTALLATION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/LocalAgentInstallationPresentationTests.swift"
AGENT_CONNECTIONS="IslandAppLib/Presentation/LocalAgentConnectionsPresentation.swift"
AGENT_CONNECTIONS_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/LocalAgentConnectionsPresentationTests.swift"
SETTINGS_VIEW="IslandAppLib/Views/Settings/SettingsView.swift"
SUPPORT_DIAGNOSTICS_PRESENTATION="IslandAppLib/Presentation/SupportDiagnosticsPresentation.swift"
SUPPORT_DIAGNOSTICS_EXPORTER="IslandAppLib/Support/SupportDiagnosticsExporter.swift"
SUPPORT_DIAGNOSTICS_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/SupportDiagnosticsTests.swift"
ONBOARDING_CONNECTION="IslandAppLib/Presentation/OnboardingConnectionPresentation.swift"
ONBOARDING_CONNECTION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/OnboardingAgentSelectionTests.swift"
ONBOARDING_VIEW="IslandAppLib/Views/Onboarding/OnboardingView.swift"
PERFORMANCE_FIXTURE="IslandCore/Sources/IslandCore/Internal/PerformanceFixture.swift"
HERMETIC_LAUNCH_MODE="IslandCore/Sources/IslandCore/Internal/HermeticAppLaunchMode.swift"
HERMETIC_LAUNCH_MODE_TESTS="IslandCoreTests/Sources/IslandCoreTests/HermeticAppLaunchModeTests.swift"
TASK_STORE="IslandCore/Sources/IslandCore/TaskStore.swift"
APP_ENTRY="IslandApp/IslandApp.swift"
SINGLE_INSTANCE_GATE="IslandAppLib/Support/AppSingleInstanceGate.swift"
SINGLE_INSTANCE_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/AppSingleInstanceGateTests.swift"
CI_WORKFLOW=".github/workflows/ci.yml"
RELEASE_WORKFLOW=".github/workflows/release.yml"
test -x "$ANALYZER" || fail "Executable performance analyzer is missing"
test -x "$ANIMATION_HITCH_ANALYZER" || fail "Executable Animation Hitches analyzer is missing"
test -x "$SAMPLER" || fail "Executable performance sampler is missing"
test -s "$SCREEN_PROBE" || fail "Display-session state probe is missing"
test -s "$SINGLE_INSTANCE_GATE" || fail "Single-instance launch gate is missing"
test -s "$SINGLE_INSTANCE_TESTS" || fail "Single-instance launch regressions are missing"
test -s "$DOT_MATRIX" || fail "Compositor dot-matrix implementation is missing"
test -s "$DOT_MATRIX_TESTS" || fail "Dot-matrix rendering regression tests are missing"
test -s "$ISLAND_WINDOW" || fail "Island window implementation is missing"
test -s "$ISLAND_WINDOW_TESTS" || fail "Island window cadence regressions are missing"
test -s "$ISLAND_PRESENTATION" || fail "Root-island presentation snapshot is missing"
test -s "$ISLAND_PRESENTATION_TESTS" || fail "Root-island presentation snapshot regressions are missing"
test -s "$ISLAND_ROOT" || fail "Root-island implementation is missing"
test -s "$MOTION" || fail "Product motion tokens are missing"
test -s "$PANEL_ACTIVITY_TESTS" || fail "Panel-activity timing regressions are missing"
test -s "$ACTION_REQUEST_PRESENTATION" || fail "Action-request presentation projection is missing"
test -s "$ACTION_REQUEST_PRESENTATION_TESTS" || fail "Action-request projection regressions are missing"
test -s "$NOTCH_PANEL" || fail "Expanded panel implementation is missing"
test -s "$TASK_CARD" || fail "Task-card implementation is missing"
test -s "$ACTION_REQUEST_SURFACE" || fail "Action-request surface is missing"
test -s "$PANEL_CLOCK_PRESENTATION" || fail "Panel clock presentation policy is missing"
test -s "$PANEL_CLOCK_TESTS" || fail "Panel clock presentation regressions are missing"
test -s "$PLAN_RENDERING" || fail "Plan Markdown rendering boundary is missing"
test -s "$PLAN_RENDERING_TESTS" || fail "Plan Markdown rendering regressions are missing"
test -s "$VISUAL_SNAPSHOT_TESTS" || fail "Visual snapshot regressions are missing"
test -s "$ACTION_REQUEST_MODEL" || fail "Action-request model is missing"
test -s "$PLAN_REVIEW_TESTS" || fail "Plan-review input regressions are missing"
test -s "$AGENT_INSTALLATION" || fail "Agent configuration I/O coordinator is missing"
test -s "$AGENT_INSTALLATION_TESTS" || fail "Agent configuration I/O regressions are missing"
test -s "$AGENT_CONNECTIONS" || fail "Settings Agent-surface operation coordinator is missing"
test -s "$AGENT_CONNECTIONS_TESTS" || fail "Settings Agent-surface operation regressions are missing"
test -s "$SETTINGS_VIEW" || fail "Settings implementation is missing"
test -s "$SUPPORT_DIAGNOSTICS_PRESENTATION" || fail "Support diagnostics operation coordinator is missing"
test -s "$SUPPORT_DIAGNOSTICS_EXPORTER" || fail "Support diagnostics I/O boundary is missing"
test -s "$SUPPORT_DIAGNOSTICS_TESTS" || fail "Support diagnostics responsiveness regressions are missing"
test -s "$ONBOARDING_CONNECTION" || fail "Welcome connection I/O coordinator is missing"
test -s "$ONBOARDING_CONNECTION_TESTS" || fail "Welcome connection I/O regressions are missing"
test -s "$ONBOARDING_VIEW" || fail "Welcome implementation is missing"
test -s "$PERFORMANCE_FIXTURE" || fail "Performance fixture implementation is missing"
test -s "$HERMETIC_LAUNCH_MODE" || fail "Hermetic Production launch mode is missing"
test -s "$HERMETIC_LAUNCH_MODE_TESTS" || fail "Hermetic Production launch-mode regressions are missing"
test -s "$TASK_STORE" || fail "TaskStore implementation is missing"
test -s "$APP_ENTRY" || fail "App entry point is missing"
test -s "$CI_WORKFLOW" || fail "PR CI workflow is missing"
test -s "$RELEASE_WORKFLOW" || fail "Tag Release workflow is missing"

if [[ -n "${DEV_ISLAND_QA_TMPDIR:-}" ]]; then
  [[ "$DEV_ISLAND_QA_TMPDIR" == /* && -d "$DEV_ISLAND_QA_TMPDIR" && ! -L "$DEV_ISLAND_QA_TMPDIR" ]] \
    || fail "DEV_ISLAND_QA_TMPDIR must be an absolute regular directory"
  TEMP_DIR="$(mktemp -d "${DEV_ISLAND_QA_TMPDIR%/}/dev-island-performance-analysis.XXXXXX")"
else
  TEMP_DIR="$(mktemp -d -t dev-island-performance-analysis)"
fi
trap 'rm -rf "$TEMP_DIR"' EXIT
CSV="$TEMP_DIR/linear.csv"

{
  printf 'timestamp_utc,elapsed_seconds,cpu_percent,rss_kb\n'
  for index in {0..9}; do
    printf '2026-08-26T00:00:%02dZ,%d,%d,%d\n' \
      "$index" "$index" "$index" "$((1000 + index * 100))"
  done
} >"$CSV"

SUMMARY="$($ANALYZER "$CSV" 5 6000 900)" \
  || fail "Deterministic performance fixture must pass inclusive thresholds"
for expected in \
  'sample_count=10' \
  'observation_span_seconds=9.000' \
  'average_cpu_percent=4.500' \
  'p50_cpu_percent=4.000' \
  'p95_cpu_percent=9.000' \
  'maximum_cpu_percent=9.000' \
  'average_rss_kb=1450' \
  'p50_rss_kb=1400' \
  'p95_rss_kb=1900' \
  'maximum_rss_kb=1900' \
  'starting_rss_kb=1000' \
  'ending_rss_kb=1900' \
  'rss_growth_kb=900' \
  'rss_slope_kb_per_minute=6000.000'; do
  rg -Fqx "$expected" <<<"$SUMMARY" \
    || fail "Performance statistic regression: $expected"
done

if "$ANALYZER" "$CSV" 4.499 >/dev/null 2>&1; then
  fail "Average CPU threshold must fail above the inclusive limit"
fi
if "$ANALYZER" "$CSV" '' 5999.999 >/dev/null 2>&1; then
  fail "RSS slope threshold must fail above the inclusive limit"
fi
if "$ANALYZER" "$CSV" '' '' 899 >/dev/null 2>&1; then
  fail "RSS growth threshold must fail above the inclusive limit"
fi

printf 'timestamp_utc,elapsed_seconds,cpu_percent,rss_kb\ninvalid\n' \
  >"$TEMP_DIR/malformed.csv"
if "$ANALYZER" "$TEMP_DIR/malformed.csv" >/dev/null 2>&1; then
  fail "Malformed performance samples must fail closed"
fi
ln -s linear.csv "$TEMP_DIR/symlink.csv"
if "$ANALYZER" "$TEMP_DIR/symlink.csv" >/dev/null 2>&1; then
  fail "Symbolic-link sample inputs must fail closed"
fi

[[ "$(swift "$SCREEN_PROBE" --self-test)" == "Display session state fixtures: PASS" ]] \
  || fail "Display-session state fixtures must pass"
[[ "$("$SAMPLER" --self-test-evidence-boundary)" == \
   "Performance evidence and App-input fixtures: PASS (7 cases)" ]] \
  || fail "Performance evidence file boundary fixtures must pass"
[[ "$("$ANIMATION_HITCH_ANALYZER" --self-test)" == \
   "Animation hitch summarizer fixtures: PASS (9 cases)" ]] \
  || fail "Animation Hitches parser and evidence-boundary fixtures must pass"
ruby -c "$ANIMATION_HITCH_ANALYZER" >/dev/null \
  || fail "Animation Hitches analyzer is not valid Ruby"

for invariant in \
  'forbidden DTD or entity declaration' \
  'File::RDONLY \| File::NOFOLLOW \| File::NONBLOCK' \
  'File::WRONLY \| File::CREAT \| File::EXCL' \
  'containment-level' \
  'render_gpu_only_frame_lifetimes' \
  'out_of_recording_rows' \
  'recording_tail' \
  'wall_unix' \
  'subsequent_log_timestamp_plus_uptime_delta'; do
  rg -q "$invariant" "$ANIMATION_HITCH_ANALYZER" \
    || fail "Animation Hitches evidence invariant missing: $invariant"
done

mkdir -p "$TEMP_DIR/fake/Dev Island.app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' \
  >"$TEMP_DIR/fake/Dev Island.app/Contents/MacOS/IslandApp"
chmod 700 "$TEMP_DIR/fake/Dev Island.app/Contents/MacOS/IslandApp"
if "$SAMPLER" \
    "$TEMP_DIR/fake/Dev Island.app/Contents/MacOS/IslandApp" \
    production-launch-smoke \
    "$TEMP_DIR/invalid-production-smoke.csv" \
    0 7 >/dev/null 2>&1; then
  fail "Production launch smoke must reject a non-eight-sample run"
fi
if "$SAMPLER" \
    "$TEMP_DIR/fake/Dev Island.app/Contents/MacOS/IslandApp" \
    production-launch-smoke \
    "$TEMP_DIR/threshold-production-smoke.csv" \
    0 8 1 >/dev/null 2>&1; then
  fail "Production launch smoke must reject performance thresholds"
fi

for invariant in \
  'require_unlocked_screen' \
  'umask 077' \
  'set -o noclobber' \
  'verify_evidence_descriptor' \
  'evidence_file_token' \
  'File::RDONLY \| File::NOFOLLOW \| File::NONBLOCK' \
  'input\.pread\(opened\.size, 0\)' \
  'QA_ANALYSIS_INPUT=' \
  'QA_READINESS_LOG_SNAPSHOT=' \
  'read_readiness_uptime_from_snapshot' \
  'launch_ready_milliseconds' \
  'stable_regular_file_sha256' \
  'snapshot_performance_app' \
  'verify_private_app_snapshot_identity' \
  'verify_selected_app_identity' \
  'QA_PRIVATE_APP=' \
  'QA_MAX_DURATION_SECONDS=86400' \
  'CFFIXED_USER_HOME=' \
  'NSRunningApplication\(processIdentifier: rawPID\)' \
  'app did not complete a normal zero-status termination' \
  'isolated_user_home=true' \
  'isolated_app_snapshot=true' \
  'normal_termination=true' \
  'app_exit_status=' \
  'screen_state_initial=' \
  'screen_state_final=' \
  'performance evidence is append-never' \
  'executable_sha256=' \
  'selected_executable_sha256=' \
  'machine_model=' \
  'p95_cpu_percent=' \
  'rss_slope_kb_per_minute='; do
  rg -q "$invariant" "$SAMPLER" "$ANALYZER" \
    || fail "Performance evidence invariant missing: $invariant"
done
rg -Fq '/usr/bin/ditto "$selected_app" "$destination_app"' "$SAMPLER" \
  || fail "Selected Performance QA App must be copied into the private sampler root"
if rg -n 'DEV_ISLAND_PERFORMANCE_SCENARIO=.*QA_SELECTED_BINARY|"\$QA_SELECTED_BINARY" 1>&8' "$SAMPLER"; then
  fail "The public selected App path must never be launched"
fi
rg -Fq 'QA_ANALYSIS="$("$QA_ANALYZER"' "$SAMPLER" \
  || fail "Performance analyzer invocation must preserve paths containing spaces"
rg -Fq 'snapshot_evidence_file "$QA_APP_LOG"' "$SAMPLER" \
  || fail "Readiness parsing must use a bounded App-log snapshot"
rg -Fq '"$QA_READINESS_MARKER")"' "$SAMPLER" \
  || fail "Readiness parsing must read only the private App-log snapshot"
if rg -n '\b(awk|cat|sed|head|tail)\b[^\n]*"\$QA_APP_LOG"' "$SAMPLER"; then
  fail "Readiness parsing must never reopen the public App-log path"
fi
for invariant in \
  'exec 7>"$csv_path" 8>"$app_log_path" 9>"$summary_path"' \
  '"$QA_BINARY" 1>&8 2>&8 7>&- 9>&-' \
  "printf 'timestamp_utc,elapsed_seconds,cpu_percent,rss_kb\n' >&7" \
  'QA_SUMMARY_CONTENT' \
  '>&9'; do
  rg -Fq "$invariant" "$SAMPLER" \
    || fail "Descriptor-backed performance evidence invariant missing: $invariant"
done

for invariant in \
  'await Task\.detached\(priority: priority, operation: operation\)\.value' \
  'guard activeMutation == nil else \{ return nil \}' \
  'guard activeOperationID == nil else \{ return nil \}' \
  'writeCompleted && state == operation\.expectedState'; do
  rg -q "$invariant" "$AGENT_INSTALLATION" \
    || fail "Agent configuration off-main invariant missing: $invariant"
done
[[ "$(rg -c 'LocalAgentConfigurationExecutor\.run\(' "$SETTINGS_VIEW")" -eq 4 ]] \
  || fail "Settings must route all four Agent configuration scan/mutation/maintenance paths off-main"
if rg -n 'installer\.(install|uninstall|isInstalled|requiresUpdate|hasManagedEntries)\(' \
    "$SETTINGS_VIEW"; then
  fail "Settings must not perform Agent configuration I/O directly on the main actor"
fi
for regression in \
  'testConfigurationExecutorLeavesTheMainThread' \
  'testNewRefreshRejectsLateOlderResult' \
  'testMutationIsExclusiveAndOwnsCompletion' \
  'testInvalidationRejectsLateMutationResult'; do
  rg -q "$regression" "$AGENT_INSTALLATION_TESTS" \
    || fail "Agent configuration I/O regression missing: $regression"
done

for invariant in \
  'struct LocalAgentConnectionsOperationState' \
  'guard activeOperationID == nil else \{ return nil \}' \
  'mutating func beginAgentMutation\(' \
  'mutating func beginDisconnectAll\(' \
  'mutating func completeAgentMutation\(' \
  'mutating func completeDisconnectAll\(' \
  'completionGeneration &\+= 1'; do
  rg -q "$invariant" "$AGENT_CONNECTIONS" \
    || fail "Settings Agent-surface operation-ownership invariant missing: $invariant"
done
for invariant in \
  '@State private var localAgentConnectionsOperation =' \
  'connectionsOperation: \$localAgentConnectionsOperation' \
  'connectionsOperation\.beginAgentMutation\(' \
  'connectionsOperation\.beginDisconnectAll\(' \
  'onChange\(of: connectionsOperation\.completionGeneration\)'; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Settings must preserve one Agent mutation owner across pane changes: $invariant"
done
DISCONNECT_ALL_BODY="$({
  sed -n \
    '/private func disconnectAllLocalAgents()/,/private var maintenanceFailed:/p' \
    "$SETTINGS_VIEW"
} || true)"
for invariant in \
  'LocalAgentConfigurationExecutor\.run\(' \
  'LocalAgentMaintenanceWorker\.disconnectAll\(\)' \
  'connectionsOperation\.completeDisconnectAll\('; do
  printf '%s\n' "$DISCONNECT_ALL_BODY" | rg -q "$invariant" \
    || fail "Disconnect All must use the shared off-main surface transaction: $invariant"
done
if printf '%s\n' "$DISCONNECT_ALL_BODY" | rg -n 'Task\.detached'; then
  fail "Disconnect All must not regress to an unowned View-local detached task"
fi
for regression in \
  'testAgentMutationOwnsTheSurfaceUntilItsExactCompletion' \
  'testDisconnectAllExcludesEveryAgentMutationAcrossPaneChanges' \
  'testLateOrWrongKindCompletionCannotReleaseAnotherMutation' \
  'testBeginningANewMutationClearsStaleMaintenanceFeedback'; do
  rg -q "$regression" "$AGENT_CONNECTIONS_TESTS" \
    || fail "Settings Agent-surface operation regression missing: $regression"
done

for invariant in \
  'guard activeOperationID == nil else \{ return nil \}' \
  'guard activeFeedbackID == id else \{ return false \}' \
  'mutating func invalidate\(\)'; do
  rg -q "$invariant" "$SUPPORT_DIAGNOSTICS_PRESENTATION" \
    || fail "Support diagnostics operation-ownership invariant missing: $invariant"
done
for invariant in \
  'SupportDiagnosticsIOExecutor\.run\(' \
  'SupportDiagnosticsExportWorker\.write\(report, to: destination\)' \
  'diagnosticsOperation\.invalidate\(\)' \
  'diagnosticsFeedback\.invalidate\(\)'; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Support diagnostics off-main delivery invariant missing: $invariant"
done
rg -q 'await Task\.detached\(priority: priority, operation: operation\)\.value' \
  "$SUPPORT_DIAGNOSTICS_EXPORTER" \
  || fail "Support diagnostics descriptor I/O must use the tested detached executor"
if rg -n 'SupportDiagnosticsExporter\.write\(' "$SETTINGS_VIEW"; then
  fail "Settings must never write or fsync a diagnostic file on the main actor"
fi
for regression in \
  'testDiagnosticOperationInvalidationRejectsLateCompletion' \
  'testDiagnosticFeedbackUsesIdentityInsteadOfMessageEquality' \
  'testDiagnosticIOExecutorLeavesTheMainThread' \
  'testDiagnosticExportWorkerReturnsBoundedOutcome'; do
  rg -q "$regression" "$SUPPORT_DIAGNOSTICS_TESTS" \
    || fail "Support diagnostics responsiveness regression missing: $regression"
done

for invariant in \
  'guard activeMutationID == nil else \{ return nil \}' \
  'activeRefreshID = nil' \
  'guard activeRefreshID == id else \{ return false \}' \
  'guard activeMutationID == id else \{ return false \}' \
  'snapshot: inspect\(\)' \
  'case \.connected\?, \.configured\?: return false'; do
  rg -q "$invariant" "$ONBOARDING_CONNECTION" \
    || fail "Welcome connection operation invariant missing: $invariant"
done
[[ "$(rg -c 'LocalAgentConfigurationExecutor\.run\(' "$ONBOARDING_VIEW")" -eq 2 ]] \
  || fail "Welcome must route its scan and mutation paths through the shared off-main executor"
if rg -n 'Task\.detached|LocalHooksInstaller\(' "$ONBOARDING_VIEW"; then
  fail "Welcome must not own detached tasks or perform Agent configuration I/O directly"
fi
for regression in \
  'testConnectionRefreshIsLatestWins' \
  'testMutationSupersedesRefreshAndOwnsAllWorkingSources' \
  'testDepartedWelcomeRejectsLateMutationResult' \
  'testMutationClassificationRequiresFinalReadBack'; do
  rg -q "$regression" "$ONBOARDING_CONNECTION_TESTS" \
    || fail "Welcome connection operation regression missing: $regression"
done

for invariant in \
  'await Task\.detached\(priority: priority, operation: operation\)\.value' \
  'maximumRenderedBlocks = 512' \
  'parsedBlocks\.count <= maximumRenderedBlocks' \
  'activeOperationID == operationID' \
  'PlanMarkdownDocument\.render\(markdown\)'; do
  rg -q "$invariant" "$PLAN_RENDERING" \
    || fail "Plan Review off-main rendering invariant missing: $invariant"
done
for invariant in \
  '\.task\(id: request\.id\)' \
  'PlanMarkdownRenderingExecutor\.render\(markdown\)' \
  '\.disabled\(!isPlanDecisionReady\)' \
  'initialPlanDocument: initialPlanDocuments\[request\.id\]'; do
  rg -q "$invariant" "$ACTION_REQUEST_SURFACE" "$NOTCH_PANEL" \
    || fail "Plan Review surface rendering invariant missing: $invariant"
done
if rg -n -U 'PlanMarkdownPresentation\.blocks\(|AttributedString\(\s*markdown:' \
    "$ACTION_REQUEST_SURFACE"; then
  fail "The one-second panel redraw path must not parse Plan Review Markdown"
fi
if rg -n 'initialPlanDocuments:' "$ISLAND_ROOT" "$APP_ENTRY"; then
  fail "Production roots must not inject pre-rendered Plan Review documents"
fi
rg -Fq '[request.id: PlanMarkdownDocument.render($0.markdown)]' \
  "$VISUAL_SNAPSHOT_TESTS" \
  || fail "Static Plan Review QA must use the production document renderer"
for regression in \
  'testPlanRenderingExecutorLeavesTheMainThread' \
  'testNewPlanRenderRejectsLateOlderDocument' \
  'testPlanRenderInvalidationRejectsLateDelivery' \
  'testRenderedDocumentRejectsAPathologicalSwiftUITree'; do
  rg -q "$regression" "$PLAN_RENDERING_TESTS" \
    || fail "Plan Review rendering regression missing: $regression"
done
rg -q 'maximumMarkdownBytes = 262_144' "$ACTION_REQUEST_MODEL" \
  || fail "Plan Review Markdown must have a real UTF-8 byte bound"
rg -q 'testPlanReviewEnforcesUTF8BytesEvenForOneCombiningGrapheme' "$PLAN_REVIEW_TESTS" \
  || fail "Plan Review combining-grapheme byte regression is missing"

for invariant in \
  'production-launch-smoke' \
  'production launch smoke requires exactly 0 warmup, 8 survival samples and no performance thresholds' \
  'QA_EXPECTED_BUILD_FLAVOR="production"' \
  'DEV_ISLAND_PRODUCTION_READY uptime=' \
  'DEV_ISLAND_HERMETIC_LAUNCH_SMOKE=v1' \
  '--dev-island-hermetic-launch-smoke-v1' \
  'production_services_isolated=' \
  'local-hook-authorization.header' \
  'tasks.sqlite' \
  '/usr/sbin/lsof -nP -a -p "$QA_PID" -i'; do
  rg -Fq -- "$invariant" "$SAMPLER" \
    || fail "Hermetic Production launch sampler invariant missing: $invariant"
done
for invariant in \
  'public static let argument = "--dev-island-hermetic-launch-smoke-v1"' \
  'public static let environmentKey = "DEV_ISLAND_HERMETIC_LAUNCH_SMOKE"' \
  'public static let environmentValue = "v1"' \
  'arguments.filter { $0 == argument }.count == 1' \
  'environment[environmentKey] == environmentValue'; do
  rg -Fq -- "$invariant" "$HERMETIC_LAUNCH_MODE" \
    || fail "Hermetic Production launch opt-in invariant missing: $invariant"
done
rg -Fq 'if HermeticAppLaunchMode.isEnabledForCurrentProcess {' "$TASK_STORE" \
  || fail "Hermetic Production launch must select an inert TaskStore"
rg -Fq 'return TaskStore(bootstrap: false)' "$TASK_STORE" \
  || fail "Hermetic Production launch must bypass TaskStore bootstrap"
for invariant in \
  'if !isHermeticLaunchSmoke {' \
  'signalHermeticLaunchReadiness' \
  'DEV_ISLAND_PRODUCTION_READY uptime=' \
  'hermeticLaunchMarkerQueue.async'; do
  rg -Fq -- "$invariant" "$APP_ENTRY" \
    || fail "Hermetic Production App lifecycle invariant missing: $invariant"
done

for invariant in \
  'NSWorkspace.shared.runningApplications' \
  '$0.bundleIdentifier == bundleIdentifier' \
  'maximumCandidateCount = 32' \
  'SecCodeCopyGuestWithAttributes' \
  'SecCodeCheckValidity' \
  'SecCodeCopyStaticCode' \
  'SecCodeCopySigningInformation' \
  'identifier == expectedIdentifier' \
  'kSecCodeInfoFlags' \
  'SecCodeSignatureFlags' \
  'signatureFlags.contains(.adhoc)' \
  'anchor apple generic and identifier' \
  'SecRequirementCreateWithString' \
  'kSecCodeInfoTeamIdentifier' \
  'kSecCodeInfoUnique' \
  'identity.isTrustedPeer(of: currentCodeIdentity)' \
  'revalidatedIdentity == winner.codeIdentity' \
  '.map(\.processIdentifier)' \
  '.sorted()' \
  'return existingApplication.activate(options:'; do
  rg -Fq -- "$invariant" "$SINGLE_INSTANCE_GATE" \
    || fail "Single-instance gate invariant missing: $invariant"
done
for invariant in \
  'if !isHermeticLaunchSmoke,' \
  'AppSingleInstanceGate.activateExistingInstanceIfNeeded()' \
  'yieldedToExistingInstance = true' \
  'NSApp.terminate(nil)' \
  'guard !yieldedToExistingInstance else { return }'; do
  rg -Fq -- "$invariant" "$APP_ENTRY" \
    || fail "Single-instance App wiring invariant missing: $invariant"
done
/usr/bin/ruby -e '
  source = File.binread(ARGV.fetch(0))
  arbitration = source.index("AppSingleInstanceGate.activateExistingInstanceIfNeeded()") or abort
  launch_health = source.index("LaunchHealthTracker.shared.beginLaunch()") or abort
  island_window = source.index("let window = IslandWindow()") or abort
  abort unless arbitration < launch_health && arbitration < island_window
' "$APP_ENTRY" || fail "Single-instance arbitration must precede LaunchHealth and Island construction"

for invariant in \
  'Build and launch isolated performance fixture' \
  'DEV_ISLAND_PERF_ALLOW_LOCKED=1' \
  './scripts/qa/measure-app-performance.sh' \
  'dev-island-launch-smoke.csv' \
  'performance_summary="$(' \
  '<<<"$performance_summary"' \
  'isolated_app_snapshot=true' \
  'selected_executable_sha256=' \
  'private_executable_sha256' \
  'selected_executable_sha256' \
  'normal_termination=true' \
  'app_exit_status=0' \
  'sample_count=8'; do
  rg -Fq "$invariant" "$CI_WORKFLOW" \
    || fail "Hermetic PR launch-smoke invariant missing: $invariant"
done
if rg -n '\b(grep|sed|awk|cat|head|tail)\b[^\n]*dev-island-launch-smoke\.summary\.txt' "$CI_WORKFLOW"; then
  fail "PR launch smoke must not reopen the public summary path after sampler exit"
fi

for workflow in "$CI_WORKFLOW" "$RELEASE_WORKFLOW"; do
  for invariant in \
    'production_summary="$(' \
    'production-launch-smoke' \
    'launch_profile=production-hermetic' \
    'production_services_isolated=true' \
    'normal_termination=true' \
    'app_exit_status=0' \
    'sample_count=8' \
    '<<<"$production_summary"'; do
    rg -Fq -- "$invariant" "$workflow" \
      || fail "Hermetic Production workflow invariant missing in $workflow: $invariant"
  done
done

/usr/bin/ruby -e '
  source = File.binread(ARGV.fetch(0))
  notarize = source.index("      - name: Notarize\n") or abort
  launch = source.index("      - name: Hermetically launch notarized production app\n") or abort
  app_keychain_teardown = source.index("      - name: Tear down App signing keychain\n") or abort
  package = source.index("      - name: Package DMG\n") or abort
  abort unless notarize < launch && launch < app_keychain_teardown && app_keychain_teardown < package
' "$RELEASE_WORKFLOW" \
  || fail "Tagged Production launch smoke and App keychain teardown must precede DMG packaging"

# The workflow consumes the sampler's bounded stdout in one shell variable.
# A public summary replacement after the producer exits must therefore be
# irrelevant to every acceptance assertion and hash comparison.
PUBLIC_SUMMARY="$TEMP_DIR/replaceable.summary.txt"
printf '%s\n' \
  'isolated_user_home=false' \
  'isolated_app_snapshot=false' \
  'normal_termination=false' \
  'app_exit_status=99' \
  'sample_count=0' \
  'executable_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'selected_executable_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  >"$PUBLIC_SUMMARY"
PERFORMANCE_SUMMARY="$({
  printf '%s\n' \
    'isolated_user_home=true' \
    'isolated_app_snapshot=true' \
    'normal_termination=true' \
    'app_exit_status=0' \
    'sample_count=8' \
    'executable_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    'selected_executable_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
})"
for expected in \
  'isolated_user_home=true' \
  'isolated_app_snapshot=true' \
  'normal_termination=true' \
  'app_exit_status=0' \
  'sample_count=8'; do
  grep -Fqx "$expected" <<<"$PERFORMANCE_SUMMARY" \
    || fail "In-memory performance summary fixture is missing: $expected"
done
PRIVATE_HASH="$(sed -n 's/^executable_sha256=//p' <<<"$PERFORMANCE_SUMMARY")"
SELECTED_HASH="$(sed -n 's/^selected_executable_sha256=//p' <<<"$PERFORMANCE_SUMMARY")"
[[ "$PRIVATE_HASH" =~ ^[0-9a-f]{64}$ && "$SELECTED_HASH" == "$PRIVATE_HASH" ]] \
  || fail "In-memory performance summary hashes must remain equal and canonical"
printf 'replacement\n' >"$PUBLIC_SUMMARY"
grep -Fqx 'sample_count=8' <<<"$PERFORMANCE_SUMMARY" \
  || fail "Public summary replacement must not affect the captured producer output"

for invariant in \
  'case transitionRunning20 = "transition-running-20"' \
  'case decisionApproval = "decision-approval"' \
  'case decisionQuestion = "decision-question"' \
  'case decisionPlanReview = "decision-plan-review"' \
  'scenario == \.transitionRunning20 \? 0\.8 : nil' \
  'transitionInitialDelay: TimeInterval = 1\.0'; do
  rg -q "$invariant" "$PERFORMANCE_FIXTURE" \
    || fail "Transition performance fixture invariant missing: $invariant"
done
rg -q 'PerformanceFixture\.makeActionRequest\(\)' "$TASK_STORE" \
  || fail "Performance decision request must enter the production TaskStore queue"
for invariant in \
  'PerformanceFixture\.signalActionQueued\(request\)' \
  'PerformanceFixture\.signalActionFinished\(request, response: response\)'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "Performance action marker boundary missing: $invariant"
done
for invariant in \
  'DEV_ISLAND_PERFORMANCE_ACTION phase=' \
  'actionMarkerQueue\.async' \
  'ProcessInfo\.processInfo\.systemUptime' \
  'Date\(\)\.timeIntervalSince1970' \
  'wallUnix='; do
  rg -q "$invariant" "$PERFORMANCE_FIXTURE" \
    || fail "Performance action marker invariant missing: $invariant"
done
[[ "$(rg -c 'let receipt = stageResponseReceipt' "$NOTCH_PANEL")" -eq 2 ]] \
  || fail "Decision and question responses must both reserve their receipt before store mutation"
decision_stage_line="$(rg -n 'let receipt = stageResponseReceipt' "$NOTCH_PANEL" | sed -n '1s/:.*//p')"
answer_stage_line="$(rg -n 'let receipt = stageResponseReceipt' "$NOTCH_PANEL" | sed -n '2s/:.*//p')"
decision_store_line="$(rg -n 'guard onActionDecision' "$NOTCH_PANEL" | sed -n '1s/:.*//p')"
answer_store_line="$(rg -n 'guard onQuestionAnswer' "$NOTCH_PANEL" | sed -n '1s/:.*//p')"
[[ -n "$decision_stage_line" && -n "$answer_stage_line" && \
   -n "$decision_store_line" && -n "$answer_store_line" && \
   "$decision_stage_line" -lt "$decision_store_line" && \
   "$answer_stage_line" -lt "$answer_store_line" ]] \
  || fail "Response receipts must be staged before TaskStore publishes request removal"
for invariant in \
  'questionPageOpacity' \
  'withTransaction\(replacement\)' \
  'Motion\.questionPageReveal'; do
  rg -q "$invariant" "$ACTION_REQUEST_SURFACE" \
    || fail "Question page replacement invariant missing: $invariant"
done
if rg -U -n 'withAnimation\([^)]*\)[^{]*\{[^}]*questionDraft\.(goBack|advanceOrSubmit)' \
    "$ACTION_REQUEST_SURFACE"; then
  fail "Question page identity must not animate old and new layouts together"
fi
for invariant in \
  'scheduleNextPerformanceTransition' \
  'performanceTransitionWorkItem\?\.cancel\(\)' \
  'performanceMarkerQueue\.async' \
  'DEV_ISLAND_PERFORMANCE_TRANSITION iteration='; do
  rg -q "$invariant" "$APP_ENTRY" \
    || fail "Transition driver invariant missing: $invariant"
done
for scenario in \
  transition-running-20 \
  decision-approval \
  decision-question \
  decision-plan-review; do
  rg -q "$scenario" "$SAMPLER" \
    || fail "Performance sampler must allow scenario: $scenario"
done
for invariant in \
  'CGSSessionScreenIsLocked' \
  'kCGSSessionOnConsoleKey' \
  'kCGSessionLoginDoneKey' \
  'normal active session omits lock key'; do
  rg -q "$invariant" "$SCREEN_PROBE" \
    || fail "Display-session classification invariant missing: $invariant"
done

for invariant in \
  'DotMatrixKeyframeCache\.shared\.keyframes' \
  'maximumEntryCount = 16' \
  'guard geometry != lastGeometry' \
  'guard bounds\.width > 0, bounds\.height > 0' \
  'animation\.beginTime = localNow - synchronizedPhase \* duration'; do
  rg -q "$invariant" "$DOT_MATRIX" \
    || fail "Compositor dot-matrix performance invariant missing: $invariant"
done
if rg -n 'TimelineView\(' "$DOT_MATRIX"; then
  fail "Continuous dot-matrix motion must stay compositor-owned"
fi
for regression in \
  'testKeyframesAreSharedPerSignatureAndCacheRemainsBounded' \
  'testRepeatedLayoutReusesDotGeometryUntilSizeActuallyChanges'; do
  rg -q "$regression" "$DOT_MATRIX_TESTS" \
    || fail "Dot-matrix rendering regression missing: $regression"
done

for invariant in \
  'idleWatchdogInterval: TimeInterval = 1\.0' \
  'activeInterval: TimeInterval = 0\.04' \
  'NSEvent\.addGlobalMonitorForEvents' \
  'NSEvent\.addLocalMonitorForEvents' \
  'tickMouseTracking\(forceCollapseReconciliation: true\)' \
  'pointerInside && mode == \.collapsed' \
  'IslandWindowMouseTrackingPolicy\.interval'; do
  rg -q "$invariant" "$ISLAND_WINDOW" \
    || fail "Island-window tracking performance invariant missing: $invariant"
done
for regression in \
  'testIdleWatchdogIsAtMostOneWakeupPerSecond' \
  'testCompactPointerInsideKeepsResponsiveCursorCadence' \
  'testExpandedPointerInsideReturnsToIdleWatchdogCadence'; do
  rg -q "$regression" "$ISLAND_WINDOW_TESTS" \
    || fail "Island-window tracking regression missing: $regression"
done

[[ "$(rg -c 'TaskPresentationPolicy\.ordered' "$ISLAND_PRESENTATION")" -eq 1 ]] \
  || fail "Root-island snapshot must order sessions exactly once"
for invariant in \
  'IslandPresentationSnapshot' \
  'TaskStatusSummary\(tasks: orderedTasks\)' \
  'fromPrimaryStatus: orderedTasks\.first\?\.status'; do
  rg -q "$invariant" "$ISLAND_PRESENTATION" \
    || fail "Root-island single-snapshot invariant missing: $invariant"
done
for regression in \
  'testSnapshotOrdersOnceAndSharesPrimaryStateAndCounts' \
  'testSnapshotLetsExpiredCompletionYieldToRunning' \
  'testEmptySnapshotIsIdle'; do
  rg -q "$regression" "$ISLAND_PRESENTATION_TESTS" \
    || fail "Root-island presentation regression missing: $regression"
done

for invariant in \
  'isLive: panelEffectsLive' \
  'panelEffectsLive = false' \
  'IslandPanelActivityTiming\.contentRevealDelay' \
  'IslandPanelActivityTiming\.liveEffectsDelay'; do
  rg -q "$invariant" "$ISLAND_ROOT" \
    || fail "Panel-activity staging invariant missing: $invariant"
done
[[ "$(rg -c 'guard panelRevealID == revealID, mode == \.expanded' "$ISLAND_ROOT")" -eq 2 ]] \
  || fail "Both delayed panel-activity callbacks must reject stale or collapsed generations"
for invariant in \
  'liveEffectsDelay: TimeInterval = Motion\.islandMorphDuration' \
  'reduceMotion \? 0 : liveEffectsDelay'; do
  rg -q "$invariant" "$MOTION" \
    || fail "Panel-activity motion invariant missing: $invariant"
done
for regression in \
  'testLiveEffectsWaitUntilGeometryMorphHasSettled' \
  'testReducedMotionDoesNotAddASpatialSettleDelay'; do
  rg -q "$regression" "$PANEL_ACTIVITY_TESTS" \
    || fail "Panel-activity timing regression missing: $regression"
done

for invariant in \
  'ActionRequestPresentationSnapshot' \
  'presentationSummary: presentation\.summary' \
  'requestPresentation: requestPresentation'; do
  rg -q "$invariant" "$ISLAND_ROOT" "$NOTCH_PANEL" \
    || fail "Expanded-panel linear projection invariant missing: $invariant"
done
if rg -q 'ActionRequestPresentationPolicy\.(primary|additionalCount|orphaned|isKeyboardPrimary)' "$NOTCH_PANEL"; then
  fail "Expanded panel must not rescan the full request queue per task row"
fi
for regression in \
  'testSnapshotIndexesVisibleQueuesAndOrphansWithoutChangingArrivalOrder' \
  'testSnapshotKeepsOldestOrphanAsTheOnlyKeyboardPrimaryRequest'; do
  rg -q "$regression" "$ACTION_REQUEST_PRESENTATION_TESTS" \
    || fail "Action-request projection regression missing: $regression"
done

if rg -n 'TimelineView\(' "$NOTCH_PANEL"; then
  fail "The expanded panel container must remain clock-free"
fi
if rg -n 'now: (context\.date|now)' "$NOTCH_PANEL"; then
  fail "The expanded panel must not inject one shared clock through every row"
fi
for invariant in \
  'TimelineView\(' \
  'PanelClockPresentation\.taskNeedsLiveTick' \
  'PanelClockPresentation\.taskDuration'; do
  rg -q "$invariant" "$TASK_CARD" \
    || fail "Task-row-local clock invariant missing: $invariant"
done
for invariant in \
  'TimelineView\(' \
  'PanelClockPresentation\.requestCountdown' \
  '\.animation\(minimumInterval: 1\.0, paused: !isLive\)'; do
  rg -q "$invariant" "$ACTION_REQUEST_SURFACE" \
    || fail "Request-header-local clock invariant missing: $invariant"
done
for regression in \
  'testRunningAndWaitingTasksNeedTicksWhileTerminalRowsStayStatic' \
  'testLiveDurationUsesNowAndFormatsHourBoundary' \
  'testTerminalDurationFreezesAtTaskUpdateTime' \
  'testDurationNeverBecomesNegativeForClockSkew' \
  'testCountdownRoundsUpAndClampsAtZero'; do
  rg -q "$regression" "$PANEL_CLOCK_TESTS" \
    || fail "Panel clock regression missing: $regression"
done

echo "Performance analysis invariants: PASS"
