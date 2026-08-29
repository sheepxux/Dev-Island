#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

TRUST_FILE="IslandCore/Sources/IslandCore/Manus/ManusRealtimeTrust.swift"
MANUS_ENDPOINTS="IslandCore/Sources/IslandCore/Manus/ManusEndpoints.swift"
MANUS_CLIENT="IslandCore/Sources/IslandCore/Manus/ManusAPIClient.swift"
MANUS_CLIENT_TESTS="IslandCoreTests/Sources/IslandCoreTests/ManusAPIClientTests.swift"
MANUS_CREDENTIAL="IslandCore/Sources/IslandCore/Manus/ManusCredentialPolicy.swift"
MANUS_ACCEPTANCE="IslandCore/Sources/IslandCore/Manus/ManusLiveAcceptance.swift"
MANUS_ACCEPTANCE_TESTS="IslandCoreTests/Sources/IslandCoreTests/ManusLiveAcceptanceTests.swift"
MANUS_CLI="IslandCoreCLI/Sources/IslandCoreCLI/main.swift"
CLOUDFLARED_PROCESS="IslandCore/Sources/IslandCore/Tunnel/CloudflaredProcess.swift"
CLOUDFLARED_TESTS="IslandCoreTests/Sources/IslandCoreTests/CloudflaredProcessTests.swift"
WEBHOOK_SIGNATURE="IslandCore/Sources/IslandCore/Manus/WebhookSignature.swift"
WEBHOOK_PAYLOAD="IslandCore/Sources/IslandCore/Models/WebhookPayload.swift"
SERVER_FILE="IslandCore/Sources/IslandCore/Tunnel/WebhookServer.swift"
WEBHOOK_AUTH_TESTS="IslandCoreTests/Sources/IslandCoreTests/WebhookAuthenticationTests.swift"
LOOPBACK_READINESS="IslandCore/Sources/IslandCore/Internal/LoopbackHTTPReadinessProbe.swift"
UPDATE_CONTROLLER="IslandAppLib/Updates/AppUpdateController.swift"
UPDATE_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/AppUpdateConfigurationTests.swift"
BUILD_SCRIPT="scripts/build-app.sh"
BUILD_FLAVOR_FIXTURES="scripts/ci/verify-performance-fixture-isolation.sh"
RESOLVED_DEPENDENCY_FIXTURES="scripts/ci/verify-resolved-dependency-boundary.sh"
PRODUCT_VERSION_FIXTURES="scripts/ci/verify-product-version-boundary.sh"
APP_BUILD_OUTPUT_BOUNDARY="scripts/release/app-build-output-boundary.rb"
APP_BUILD_OUTPUT_FIXTURES="scripts/ci/verify-app-build-output-boundary.sh"
RELEASE_WORKFLOW=".github/workflows/release.yml"
SPARKLE_SECRET_RUNNER="scripts/release/run-sparkle-appcast-generator.sh"
SPARKLE_SECRET_FIXTURES="scripts/ci/verify-sparkle-secret-isolation.sh"
LICENSE_VERIFIER="IslandCore/Sources/IslandCore/Commerce/CommercialLicenseVerifier.swift"
LICENSE_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseVerifierTests.swift"
LICENSE_STORE="IslandCore/Sources/IslandCore/Commerce/CommercialLicenseDocumentStore.swift"
LICENSE_STORE_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseDocumentStoreTests.swift"
LICENSE_ACTIVATION="IslandCore/Sources/IslandCore/Commerce/CommercialLicenseActivation.swift"
LICENSE_ACTIVATION_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseActivationTests.swift"
LICENSE_SECURITY_DOC="docs/COMMERCIAL_LICENSE_SECURITY.md"
LICENSE_THREAT_MODEL="docs/COMMERCIAL_ACTIVATION_THREAT_MODEL.md"
COMMERCIAL_POLICY="scripts/commerce/commercial-policy.json"
COMMERCIAL_POLICY_VERIFIER="scripts/release/verify-commercial-policy.rb"
COMMERCIAL_POLICY_FIXTURES="scripts/ci/verify-commercial-policy.sh"
COMMERCIAL_POLICY_DOC="docs/COMMERCIAL_POLICY_DECISION.md"
INFO_PLIST="IslandApp/Resources/Info.plist"
LOCAL_HOOK_SERVER="IslandCore/Sources/IslandCore/LocalHooks/LocalHookServer.swift"
LOCAL_HOOK_AUTHORIZATION="IslandCore/Sources/IslandCore/LocalHooks/LocalHookAuthorization.swift"
LOCAL_HOOK_AUTHORIZATION_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalHookAuthorizationStoreTests.swift"
LOCAL_HOOK_HEALTH_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalHookServerHealthTests.swift"
SQLITE_STORE="IslandCore/Sources/IslandCore/Storage/SQLiteStore.swift"
SQLITE_FILE_BOUNDARY="IslandCore/Sources/IslandCore/Storage/SQLiteFileBoundary.swift"
TASK_STORE="IslandCore/Sources/IslandCore/TaskStore.swift"
ACTION_REQUEST_MODEL="IslandCore/Sources/IslandCore/Models/AgentActionRequest.swift"
TASK_STORE_ACTION_TESTS="IslandCoreTests/Sources/IslandCoreTests/TaskStoreActionRequestTests.swift"
CLAUDE_QUESTION_HOOK="IslandCore/Sources/IslandCore/Connectors/ClaudeCode/ClaudeQuestionHook.swift"
CLAUDE_QUESTION_TESTS="IslandCoreTests/Sources/IslandCoreTests/ClaudeQuestionHookTests.swift"
LOCAL_AGENT_EVENT="IslandCore/Sources/IslandCore/Connectors/Framework/LocalAgentEvent.swift"
LOCAL_SESSION_TABLE="IslandCore/Sources/IslandCore/Connectors/LocalSessionTable.swift"
LOCAL_AGENT_CONNECTOR="IslandCore/Sources/IslandCore/Connectors/Framework/LocalAgentConnector.swift"
LOCAL_AGENT_FRAMEWORK_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalAgentFrameworkTests.swift"
TASK_DESTINATION_POLICY="IslandCore/Sources/IslandCore/Internal/TaskDestinationPolicy.swift"
TASK_DESTINATION_TESTS="IslandCoreTests/Sources/IslandCoreTests/TaskDestinationPolicyTests.swift"
MANUS_REMOTE_CONTENT="IslandCore/Sources/IslandCore/Manus/ManusRemoteContentPolicy.swift"
WEBHOOK_PAYLOAD_TESTS="IslandCoreTests/Sources/IslandCoreTests/WebhookPayloadTests.swift"
STATE_RECONCILER="IslandCore/Sources/IslandCore/Sync/StateReconciler.swift"
STATE_RECONCILER_TESTS="IslandCoreTests/Sources/IslandCoreTests/StateReconcilerTests.swift"
TASK_TRANSITION_TESTS="IslandCoreTests/Sources/IslandCoreTests/TaskTransitionTests.swift"
TUNNEL_MANAGER="IslandCore/Sources/IslandCore/Tunnel/TunnelManager.swift"
TUNNEL_MANAGER_TESTS="IslandCoreTests/Sources/IslandCoreTests/TunnelManagerTests.swift"
POLLING_FALLBACK="IslandCore/Sources/IslandCore/Sync/PollingFallback.swift"
POLLING_FALLBACK_TESTS="IslandCoreTests/Sources/IslandCoreTests/PollingFallbackTests.swift"
MANUS_LIFECYCLE_TESTS="IslandCoreTests/Sources/IslandCoreTests/TaskStoreManusLifecycleTests.swift"
SLEEP_WAKE_STABILITY_FIXTURE="scripts/ci/verify-sleep-wake-lifecycle-stability.sh"
SETTINGS_VIEW="IslandAppLib/Views/Settings/SettingsView.swift"
AGENT_CONNECTIONS="IslandAppLib/Presentation/LocalAgentConnectionsPresentation.swift"
AGENT_CONNECTIONS_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/LocalAgentConnectionsPresentationTests.swift"
HOOK_MAINTENANCE="IslandCore/Sources/IslandCore/Connectors/Framework/LocalAgentHookMaintenance.swift"
HOOK_EDITOR="IslandCore/Sources/IslandCore/Connectors/HookConfigEditor.swift"
HOOK_MAINTENANCE_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalAgentHookMaintenanceTests.swift"
MANAGED_CONFIG_FILE="IslandCore/Sources/IslandCore/Connectors/Framework/ManagedConfigFile.swift"
MANAGED_CONFIG_TESTS="IslandCoreTests/Sources/IslandCoreTests/ManagedConfigFileTests.swift"
CLAUDE_PLAN_HOOK="IslandCore/Sources/IslandCore/Connectors/ClaudeCode/ClaudePlanReviewHook.swift"
CLAUDE_PLAN_TESTS="IslandCoreTests/Sources/IslandCoreTests/ClaudePlanReviewHookTests.swift"
LOCAL_ACTION_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalHookServerActionTests.swift"
KEYBOARD_CONTRACT_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/ActionRequestKeyboardContractTests.swift"
SESSION_JUMP_CONTEXT="IslandCore/Sources/IslandCore/Models/SessionJumpContext.swift"
TMUX_NAVIGATOR="IslandCore/Sources/IslandCore/Internal/TmuxSessionNavigator.swift"
TMUX_STABILITY_FIXTURE="scripts/ci/verify-tmux-process-stability.sh"
SOURCE_APP_RESOLVER="IslandCore/Sources/IslandCore/Internal/SourceAppResolver.swift"
LOCAL_HOOKS_INSTALLER="IslandCore/Sources/IslandCore/Connectors/Framework/LocalHooksInstaller.swift"
SOURCE_APP_TESTS="IslandCoreTests/Sources/IslandCoreTests/SourceAppResolverTests.swift"
SQLITE_MAINTENANCE_TESTS="IslandCoreTests/Sources/IslandCoreTests/SQLiteStoreMaintenanceTests.swift"
USAGE_MODEL="IslandCore/Sources/IslandCore/Models/AgentUsageSnapshot.swift"
USAGE_READER="IslandCore/Sources/IslandCore/Usage/CodexLocalUsageReader.swift"
USAGE_CONTROLLER="IslandAppLib/Usage/AgentUsageController.swift"
USAGE_SETTINGS="IslandAppLib/Views/Settings/SettingsView.swift"
USAGE_TESTS="IslandCoreTests/Sources/IslandCoreTests/AgentUsageReaderTests.swift"
QWEN_AGENT="IslandCore/Sources/IslandCore/Connectors/QwenCode/QwenCodeAgent.swift"
QWEN_PERMISSION="IslandCore/Sources/IslandCore/Connectors/QwenCode/QwenPermissionHook.swift"
QWEN_INSTALLER_TESTS="IslandCoreTests/Sources/IslandCoreTests/QwenCodeHooksInstallerTests.swift"
QWEN_PERMISSION_TESTS="IslandCoreTests/Sources/IslandCoreTests/QwenPermissionHookTests.swift"
QWEN_NOTES="docs/qwen-code-hooks-notes.md"
QWEN_LOGO="scripts/assets/agent-logos/qwen-code.svg"
QWEN_LOGO_LICENSE="scripts/licenses/qwen-code-desktop-Apache-2.0-LICENSE-NOTICE"
COPILOT_AGENT="IslandCore/Sources/IslandCore/Connectors/CopilotCLI/CopilotCLIAgent.swift"
COPILOT_EVENT="IslandCore/Sources/IslandCore/Connectors/CopilotCLI/CopilotCLIEvent.swift"
COPILOT_CONNECTOR_TESTS="IslandCoreTests/Sources/IslandCoreTests/CopilotCLIConnectorTests.swift"
COPILOT_INSTALLER_TESTS="IslandCoreTests/Sources/IslandCoreTests/CopilotCLIHooksInstallerTests.swift"
COPILOT_NOTES="docs/copilot-cli-hooks-notes.md"
COPILOT_LOGO="scripts/assets/agent-logos/copilot-cli.svg"
KIMI_AGENT="IslandCore/Sources/IslandCore/Connectors/KimiCode/KimiCodeAgent.swift"
KIMI_EVENT="IslandCore/Sources/IslandCore/Connectors/KimiCode/KimiCodeEvent.swift"
KIMI_TOML_EDITOR="IslandCore/Sources/IslandCore/Connectors/TomlHookConfigEditor.swift"
KIMI_CONNECTOR_TESTS="IslandCoreTests/Sources/IslandCoreTests/KimiCodeConnectorTests.swift"
KIMI_INSTALLER_TESTS="IslandCoreTests/Sources/IslandCoreTests/KimiCodeHooksInstallerTests.swift"
KIMI_NOTES="docs/kimi-code-hooks-notes.md"
KIMI_LOGO="scripts/assets/agent-logos/kimi-code.svg"
KIMI_LOGO_LICENSE="scripts/licenses/kimi-code-vscode-Apache-2.0-LICENSE"
OPENCODE_AGENT="IslandCore/Sources/IslandCore/Connectors/OpenCode/OpenCodeAgent.swift"
OPENCODE_EVENT="IslandCore/Sources/IslandCore/Connectors/OpenCode/OpenCodeEvent.swift"
OPENCODE_PLUGIN="IslandCore/Sources/IslandCore/Connectors/OpenCode/OpenCodePlugin.swift"
STANDALONE_PLUGIN_EDITOR="IslandCore/Sources/IslandCore/Connectors/Framework/StandalonePluginFileEditor.swift"
OPENCODE_CONNECTOR_TESTS="IslandCoreTests/Sources/IslandCoreTests/OpenCodeConnectorTests.swift"
OPENCODE_INSTALLER_TESTS="IslandCoreTests/Sources/IslandCoreTests/OpenCodePluginInstallerTests.swift"
OPENCODE_NOTES="docs/opencode-plugin-notes.md"
OPENCODE_LOGO="scripts/assets/agent-logos/opencode.svg"
OPENCODE_LOGO_LICENSE="scripts/licenses/opencode-MIT-LICENSE"
OPENCODE_LOGO_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/AgentBrandAssetTests.swift"
TOMLPLUSPLUS_LICENSE="scripts/licenses/tomlplusplus-LICENSE"
LAUNCH_HEALTH="IslandAppLib/Support/LaunchHealthTracker.swift"
LAUNCH_HEALTH_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/LaunchHealthTrackerTests.swift"
LAUNCH_HEALTH_DOC="docs/LAUNCH_HEALTH.md"
LAUNCH_CRASH_DOC="docs/LAUNCH_CRASH_ANALYSIS.md"
APP_ENTRY="IslandApp/IslandApp.swift"
ISLAND_ROOT_VIEW="IslandAppLib/Views/Island/IslandRootView.swift"
INTERFACE_COLORS="IslandAppLib/Theme/Colors.swift"
INTERFACE_CONTRAST_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/ActionRequestContrastPolicyTests.swift"
ACTION_REQUEST_SURFACE="IslandAppLib/Views/NotchPanel/ActionRequestSurface.swift"
SUPPORT_DIAGNOSTICS="IslandAppLib/Support/SupportDiagnostics.swift"
SUPPORT_EXPORTER="IslandAppLib/Support/SupportDiagnosticsExporter.swift"
SUPPORT_PRESENTATION="IslandAppLib/Presentation/SupportDiagnosticsPresentation.swift"
SUPPORT_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/SupportDiagnosticsTests.swift"
LEGAL_DOCUMENT_VIEW="IslandAppLib/Support/LegalDocument.swift"
LEGAL_DOCUMENT_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/LegalDocumentPresentationTests.swift"
LEGAL_DOCUMENT_VERIFIER="scripts/release/verify-legal-documents.rb"
STATUS_MENU="IslandAppLib/StatusBar/StatusItemController.swift"
STATUS_MENU_PRESENTATION="IslandAppLib/StatusBar/StatusMenuPresentation.swift"
STATUS_MENU_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/StatusMenuPresentationTests.swift"
DOCK_VISIBILITY="IslandAppLib/Coordinator/DockVisibilityCoordinator.swift"
DOCK_VISIBILITY_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/DockVisibilityCoordinatorTests.swift"
CODEX_TRUST_PROBE="IslandCore/Sources/IslandCore/Connectors/Codex/CodexHookTrustProbe.swift"
CODEX_TRUST_TESTS="IslandCoreTests/Sources/IslandCoreTests/CodexHookTrustProbeTests.swift"
CODEX_TRUST_STABILITY_FIXTURE="scripts/ci/verify-codex-hook-trust-process-stability.sh"
BOUNDED_STDIO_CHILD_PROCESS="IslandCore/Sources/IslandCore/Internal/BoundedStdioChildProcess.swift"
LOCAL_HOOK_DIAGNOSTICS="IslandCore/Sources/IslandCore/Connectors/Framework/LocalAgentHookDiagnostics.swift"
LOCAL_HOOK_DIAGNOSTIC_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalAgentHookDiagnosticsTests.swift"
LOCAL_LIVE_READINESS="IslandCore/Sources/IslandCore/Connectors/Framework/LocalLiveReadiness.swift"
HERMETIC_LOCAL_LISTENER="IslandCore/Sources/IslandCore/LocalHooks/HermeticLocalListenerReadiness.swift"
BOUNDED_CHILD_PROCESS="IslandCore/Sources/IslandCore/Internal/BoundedChildProcess.swift"
LOCAL_LIVE_READINESS_TESTS="IslandCoreTests/Sources/IslandCoreTests/LocalLiveReadinessTests.swift"
LOCAL_VERSION_STABILITY_FIXTURE="scripts/ci/verify-local-version-probe-stability.sh"
HERMETIC_LOCAL_LISTENER_FIXTURE="scripts/ci/verify-hermetic-local-listener.sh"
LOCAL_LIVE_READINESS_PRESENTATION="IslandAppLib/Presentation/LocalLiveReadinessPresentation.swift"
LOCAL_LIVE_READINESS_PRESENTATION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/LocalLiveReadinessPresentationTests.swift"
VISUAL_SNAPSHOT_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/VisualSnapshotTests.swift"
ONBOARDING_VIEW="IslandAppLib/Views/Onboarding/OnboardingView.swift"
ONBOARDING_LAYOUT_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/OnboardingLayoutTests.swift"
BUNDLE_DEPENDENCY_VERIFIER="scripts/release/verify-app-bundle-dependencies.rb"
BUNDLE_DEPENDENCY_FIXTURES="scripts/ci/verify-app-bundle-dependencies.sh"
BRAND_ASSET_VERIFIER="scripts/release/verify-brand-assets.rb"
CI_WORKFLOW=".github/workflows/ci.yml"
CI_DIAGNOSTIC_GENERATOR="scripts/ci/generate-ci-diagnostics.rb"
CI_DIAGNOSTIC_FIXTURES="scripts/ci/verify-ci-diagnostics.sh"
AUTHORITATIVE_TESTS="scripts/ci/run-authoritative-tests.sh"

rg -q 'liveV2AcceptanceComplete = false' "$TRUST_FILE" \
  || fail "Manus realtime must remain release-disabled until live v2 acceptance is reviewed"

rg -q 'https://api\.manus\.ai' "$MANUS_ENDPOINTS" \
  || fail "Manus v2 webhook trust must use the hard-coded official HTTPS origin"
for invariant in \
  'v2/webhook\.create' \
  'v2/webhook\.delete' \
  'v2/webhook\.publicKey' \
  'x-manus-api-key'; do
  rg -q "$invariant" "$MANUS_ENDPOINTS" \
    || fail "Official Manus v2 webhook endpoint invariant missing: $invariant"
done

for invariant in \
  'X-Webhook-Signature' \
  'X-Webhook-Timestamp' \
  'maximumClockSkew: TimeInterval = 300' \
  'SHA256\.hash\(data: body\)' \
  'rsaSignatureMessagePKCS1v15SHA256'; do
  rg -q "$invariant" "$WEBHOOK_SIGNATURE" \
    || fail "Official Manus v2 signature invariant missing: $invariant"
done

for invariant in 'eventID' 'eventType' 'taskDetail' 'task_created' 'task_stopped'; do
  rg -q "$invariant" "$WEBHOOK_PAYLOAD" \
    || fail "Official Manus v2 payload invariant missing: $invariant"
done

rg -q 'webhookPublicKeyTTL: TimeInterval = 3_600' "$MANUS_CLIENT" \
  || fail "Authenticated Manus webhook public-key cache must remain bounded to one hour"

for invariant in \
  'URLSessionConfiguration\.ephemeral' \
  'httpShouldSetCookies = false' \
  'completionHandler\(nil\)' \
  'responseOriginMatches' \
  'maximumBackoff: TimeInterval = 300'; do
  rg -q "$invariant" "$MANUS_CLIENT" \
    || fail "Manus credential-bearing transport invariant missing: $invariant"
done
for invariant in \
  'validIdentifier' \
  'validWebhookCallback' \
  'ManusCredentialPolicy\.validated' \
  'trycloudflare\.com'; do
  rg -q "$invariant" "$MANUS_ENDPOINTS" \
    || fail "Manus outbound request-construction invariant missing: $invariant"
done
for invariant in \
  'minimumLength = 16' \
  'maximumLength = 512' \
  '0x21\.\.\.0x7e'; do
  rg -q "$invariant" "$MANUS_CREDENTIAL" \
    || fail "Shared Manus credential boundary missing: $invariant"
done
for regression in \
  'testDefaultTransportIsEphemeralBoundedAndRedirectFree' \
  'testUnsafeCredentialIdentifiersAndCallbackNeverReachTransport' \
  'testOpaqueTaskIDStaysWithinOneReviewedRoute' \
  'testCrossOriginHTTPResponsesFailClosedForValueAndVoidRequests' \
  'testRetryAfterCannotSuspendTheClientBeyondFiveMinutes'; do
  rg -q "$regression" "$MANUS_CLIENT_TESTS" \
    || fail "Manus outbound trust regression missing: $regression"
done

for file in \
  "$TASK_DESTINATION_POLICY" \
  "$TASK_DESTINATION_TESTS" \
  "$MANUS_REMOTE_CONTENT" \
  "$WEBHOOK_PAYLOAD_TESTS"; do
  test -s "$file" || fail "Task destination/content trust artifact missing: $file"
done
for invariant in \
  'components.host == "manus.im"' \
  'components.percentEncodedPath == "/app/\(taskID)"' \
  'parsed.isFileURL' \
  'values.isApplication != true' \
  'values.isPackage != true'; do
  rg -Fq "$invariant" "$TASK_DESTINATION_POLICY" \
    || fail "Task destination policy invariant missing: $invariant"
done
for invariant in \
  'TaskDestinationPolicy\.destination\(for: task\)' \
  'private let openDestination: \(URL\) -> Bool' \
  'Rejected unsafe task destination'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "TaskStore destination boundary missing: $invariant"
done
if rg -n 'URL\(string: task\.taskURL\)' "$TASK_STORE"; then
  fail "TaskStore must not bypass the reviewed destination policy"
fi
for invariant in \
  'maximumResponseBytes = 1_048_576' \
  'maximumTaskCount = 1_000' \
  'maximumAttachmentCount = 64' \
  'isValidTitle' \
  'isValidMessage'; do
  rg -q "$invariant" "$MANUS_REMOTE_CONTENT" \
    || fail "Manus remote-content bound missing: $invariant"
done
for regression in \
  'testManusDestinationRejectsUntrustedSchemesOriginsAndRouteSyntax' \
  'testLocalDestinationRejectsFilesBundlesRemoteHostsAndMissingPaths' \
  'testTaskStoreNeverCallsOpenerForRejectedOrAmbiguousDestinations'; do
  rg -q "$regression" "$TASK_DESTINATION_TESTS" \
    || fail "Task destination attack regression missing: $regression"
done
for regression in \
  'testRemoteTaskFieldsFailClosedBeforeEnteringTheStore' \
  'testOversizedResponseFailsBeforeJSONDecode' \
  'testGetTaskRejectsMismatchedResponseIdentity'; do
  rg -q "$regression" "$MANUS_CLIENT_TESTS" \
    || fail "Manus remote-content regression missing: $regression"
done
for regression in \
  'testUnsafeTaskDestinationFailsClosedDuringWebhookDecode' \
  'testUnboundedRemoteDisplayFieldsFailClosedDuringWebhookDecode'; do
  rg -q "$regression" "$WEBHOOK_PAYLOAD_TESTS" \
    || fail "Manus webhook content regression missing: $regression"
done

for file in "$STATE_RECONCILER" "$STATE_RECONCILER_TESTS" "$TASK_TRANSITION_TESTS"; do
  test -s "$file" || fail "Composite task-identity artifact missing: $file"
done
for invariant in \
  'normalizedSnapshot(incoming, source: source)' \
  'remote.identity' \
  'TaskIdentity(source: "manus", id: d.taskId)' \
  'task.identity == identity' \
  'newestByIdentity: [TaskIdentity: AgentTask]'; do
  rg -Fq "$invariant" "$STATE_RECONCILER" \
    || fail "Composite task-identity reconcile invariant missing: $invariant"
done
rg -Fq 'StateReconciler.normalizedSnapshot(snapshot, source: source)' "$TASK_STORE" \
  || fail "Local connector snapshots must be source-scoped and de-duplicated"
if rg -n '\.id == d\.taskId|\$0\.id == d\.taskId|local\.map \{ \(\$0\.id' "$STATE_RECONCILER"; then
  fail "StateReconciler must not restore bare-ID task matching"
fi
for regression in \
  'testScopedReconcileIgnoresMalformedCrossSourceIncomingRows' \
  'testReconcileUsesCompositeIdentityForSameIDAcrossAgents' \
  'testDuplicateSnapshotRowsCoalesceWithoutCrashing' \
  'testNormalizedSnapshotDropsWrongSourceAndCoalescesDuplicates' \
  'testCreatedEventDoesNotTreatAnotherAgentSameIDAsDuplicate' \
  'testStoppedEventUpdatesOnlyMatchingManusIdentity' \
  'testStoppedEventRecoversManusTaskWithoutMutatingSameIDLocalTask' \
  'testStoppedReplayCannotRegressTerminalManusTask' \
  'testWaitingTaskCanStillAdvanceToCompleted'; do
  rg -q "$regression" "$STATE_RECONCILER_TESTS" \
    || fail "Composite task-identity regression missing: $regression"
done
rg -q 'testLocalSnapshotCannotInjectAnotherSourceOrDuplicateAnIdentity' "$TASK_TRANSITION_TESTS" \
  || fail "Local snapshot source-ownership regression missing"

rg -q 'public init\?\(port: Int = 7823, signaturePublicKeyPEM: String\)' "$SERVER_FILE" \
  || fail "WebhookServer must require an explicit signature trust anchor"

rg -q 'guard let authentication = await self\.authenticate\(' "$SERVER_FILE" \
  || fail "Webhook requests must fail closed through WebhookRequestAuthenticator"

for invariant in \
  'expirationByEventID[eventID] = max(retainedExpiration, expiration)' \
  'guard expirationByEventID.count < capacity else { return .saturated }' \
  'authentication.signedAt.timeIntervalSince1970' \
  '+ WebhookSignature.maximumClockSkew' \
  'payload.eventID,' \
  'authentication: authentication' \
  'return .serviceUnavailable'; do
  rg -Fq "$invariant" "$SERVER_FILE" \
    || fail "Webhook signature-window replay invariant missing: $invariant"
done
for regression in \
  'testReplayWindowRejectsDuplicateAndExtendsAuthenticatedLifetime' \
  'testReplayWindowFailsClosedInsteadOfEvictingLiveEventsAtCapacity' \
  'testLiveHTTPRouteKeepsDuplicatesIdempotentAndFailsClosedAtCapacity'; do
  rg -q "$regression" "$WEBHOOK_AUTH_TESTS" \
    || fail "Webhook replay-window regression missing: $regression"
done
for invariant in \
  'replayCapacity: Int' \
  'self.replayWindow = WebhookReplayWindow(capacity: Self.replayCacheLimit)' \
  'self.replayWindow = WebhookReplayWindow(capacity: replayCapacity)'; do
  rg -Fq "$invariant" "$SERVER_FILE" \
    || fail "Webhook replay transport-test boundary missing: $invariant"
done
if rg -n 'replayCapacity:' IslandCore IslandCoreCLI \
  --glob '!**/Tunnel/WebhookServer.swift'; then
  fail "Production Webhook call sites must not override the fixed replay capacity"
fi
if rg -n 'replayOrder|removeFirst\(\)|removeValue\(forKey: oldest' "$SERVER_FILE"; then
  fail "Webhook replay protection must not evict a still-live event ID"
fi

for file in \
  "$LOOPBACK_READINESS" \
  "$WEBHOOK_AUTH_TESTS" \
  "$TUNNEL_MANAGER" \
  "$TUNNEL_MANAGER_TESTS"; do
  test -s "$file" || fail "Webhook readiness boundary artifact missing: $file"
done
for invariant in \
  'session\.bytes\(for: request\)' \
  'maximumExpectedBytes = 256' \
  'maximumPathBytes = 512' \
  'expectedContentLength == Int64\(expectedResponse\.count\)' \
  'LoopbackNoRedirectDelegate' \
  'completionHandler\(nil\)' \
  'timeoutIntervalForResource = timeout'; do
  rg -q "$invariant" "$LOOPBACK_READINESS" \
    || fail "Bounded redirect-free loopback readiness invariant missing: $invariant"
done
for invariant in \
  'waitForReadiness\(token: readinessToken\)' \
  'WebhookServerStartError\.readinessFailed' \
  'func isReady\(\) async -> Bool' \
  'guard await server\.isReady\(\)' \
  'WebhookServer readiness lost'; do
  rg -q "$invariant" "$SERVER_FILE" "$TUNNEL_MANAGER" \
    || fail "Transactional WebhookServer readiness invariant missing: $invariant"
done
if rg -n 'URLSession[^\n]*data\(|session\.data\(|data\(from:' \
  "$LOOPBACK_READINESS" "$LOCAL_HOOK_SERVER"; then
  fail "Loopback ownership probes must not accumulate an unbounded URLSession response"
fi
for regression in \
  'testServerStartReturnsOnlyAfterPrivateReadinessProof' \
  'testServerStartFailsClosedWithinBoundWhenLoopbackPortIsOccupied'; do
  rg -q "$regression" "$WEBHOOK_AUTH_TESTS" \
    || fail "WebhookServer readiness regression missing: $regression"
done
for regression in \
  'testServerStartFailurePreventsTunnelAndRemoteRegistration' \
  'testServerLossDuringRegistrationDeletesAcceptedWebhookAndRollsBack' \
  'testHeartbeatServerFailureDeletesWebhookStopsProcessAndSignalsPollingOnly'; do
  rg -q "$regression" "$TUNNEL_MANAGER_TESTS" \
    || fail "Tunnel/Webhook readiness regression missing: $regression"
done

if rg -n 'webhookPublicKeyPEM|WebhookServer\(\)' IslandCore IslandCoreCLI IslandCoreTests; then
  fail "An optional or zero-argument WebhookServer signature bypass was reintroduced"
fi

if rg -n '(MANUS_WEBHOOK_PUBLIC_KEY|MANUS_SIGNATURE_PUBLIC_KEY|webhookSignaturePublicKey)' \
  IslandCore IslandAppLib IslandCoreCLI; then
  fail "The Manus trust anchor must not be overridden by environment or preferences"
fi

if rg -n 'Body:' IslandCore/Sources --glob '*.swift' \
  || rg -n 'IslandLogger\.[^\n]*String\(data:' IslandCore/Sources --glob '*.swift'; then
  fail "Raw API response bodies must not be written to diagnostics or unified logs"
fi

if rg -n 'String\(apiKey\.(prefix|suffix)|print\([^\n]*apiKey' \
  IslandCore IslandAppLib IslandCoreCLI --glob '*.swift'; then
  fail "API-key material must not be printed, even partially"
fi

for file in \
  "$MANUS_ACCEPTANCE" \
  "$MANUS_ACCEPTANCE_TESTS" \
  "$MANUS_CLI" \
  "$CLOUDFLARED_PROCESS" \
  "$CLOUDFLARED_TESTS"; do
  test -s "$file" || fail "Manus live-acceptance safety artifact missing: $file"
done
for invariant in \
  'ManusLiveAcceptanceChecklist' \
  'signedRegistrationProbe' \
  'createdTaskIDs\.contains\(payload\.taskId\)' \
  'Task\.detached\(priority: \.userInitiated\)' \
  'manualWebhookReviewRequired' \
  'if let tunnel \{ await tunnel\.stop\(\) \}' \
  'if let server \{ await server\.stop\(\) \}'; do
  rg -q "$invariant" "$MANUS_ACCEPTANCE" \
    || fail "Transactional Manus live-acceptance invariant missing: $invariant"
done
for invariant in \
  'manus-live-acceptance' \
  'readpassphrase' \
  'RPP_REQUIRE_TTY' \
  '60\.\.\.1_800' \
  'result=manual_webhook_review_required'; do
  rg -q "$invariant" "$MANUS_CLI" \
    || fail "Explicit Manus CLI safety invariant missing: $invariant"
done
if rg -n 'MANUS_API_KEY_DEV|ProcessInfo\.processInfo\.environment\[[^]]*MANUS' "$MANUS_CLI"; then
  fail "The live-acceptance CLI must never source a Manus credential from the environment"
fi
if rg -n 'print\([^\n]*\\\((publicURL|webhookURL|webhookID|identifier|payload|error)' "$MANUS_CLI" \
  || rg -n 'print\([^\n]*\.absoluteString' "$MANUS_CLI"; then
  fail "The live-acceptance CLI must not print provider IDs, callback URLs, payloads, or raw errors"
fi
for regression in \
  'testRunnerAcceptsOnlyFullLifecycleThenDeletesAndStops' \
  'testServerStartupFailureCannotStartTunnelOrAttemptRegistration' \
  'testCancelledRunnerUsesCleanupPathAndDeletesKnownWebhook' \
  'testUncertainRegistrationRequiresManualReviewButStillStopsTransports' \
  'testDeletionFailureNeverReportsAcceptanceAndRequiresManualReview' \
  'testCloudflaredChildEnvironmentExcludesParentCredentialsAndConfig'; do
  rg -q "$regression" "$MANUS_ACCEPTANCE_TESTS" \
    || fail "Manus live-acceptance cleanup regression missing: $regression"
done
rg -q 'proc\.environment = Self\.childEnvironment' "$CLOUDFLARED_PROCESS" \
  || fail "cloudflared must receive the reviewed minimal child environment"
if rg -n 'proc\.environment = ProcessInfo|proc\.environment = parent' "$CLOUDFLARED_PROCESS"; then
  fail "cloudflared must never inherit the full parent environment"
fi
for invariant in \
  'maximumStartupOutputBytes = 1 \* 1_024 \* 1_024' \
  'startStderrReader' \
  'fileHandleForWriting\.close' \
  'terminationGraceMicroseconds' \
  'SIGKILL' \
  'quickTunnelURL' \
  'lookupOnPath' \
  'outputLimitExceeded'; do
  rg -q "$invariant" "$CLOUDFLARED_PROCESS" \
    || fail "Bounded cloudflared process invariant missing: $invariant"
done
if rg -n 'withThrowingTaskGroup|readabilityHandler|/usr/bin/env|arguments = \["which"' \
  "$CLOUDFLARED_PROCESS"; then
  fail "cloudflared startup must not depend on cancellation-insensitive streams, run-loop reads, or a which subprocess"
fi
for regression in \
  'testFragmentedQuickTunnelURLStartsAndStopClosesTheChild' \
  'testSilentChildCannotOutliveStartupTimeoutEvenWhenItIgnoresTerm' \
  'testUnboundedStartupOutputFailsClosedAndStopsTheChild' \
  'testQuickTunnelParserRejectsLookalikesAndUnsafeLabels' \
  'testPathLookupNeverExecutesWhichAndRejectsWritableBinary'; do
  rg -q "$regression" "$CLOUDFLARED_TESTS" \
    || fail "Cloudflared process regression missing: $regression"
done

rg -q 'sparkle-project/Sparkle\.git", exact: "2\.9\.6"' Package.swift \
  || fail "Sparkle must stay exactly pinned until its update trust boundary is reviewed"
rg -q 'mattt/swift-toml\.git", exact: "2\.0\.0"' Package.swift \
  || fail "The TOML parser must stay exactly pinned because it protects user configuration"
test -s Package.resolved || fail "Package.resolved must exist for reproducible app builds"
rg -q '"identity" : "swift-toml"' Package.resolved \
  || fail "Package.resolved is missing swift-toml"
rg -q '"version" : "2\.0\.0"' Package.resolved \
  || fail "Package.resolved must pin swift-toml 2.0.0"
test -s "$TOMLPLUSPLUS_LICENSE" \
  || fail "The statically linked toml++ license notice must ship with the app"
test -x "$RESOLVED_DEPENDENCY_FIXTURES" \
  || fail "Executable resolved-dependency boundary fixtures are missing"
"$RESOLVED_DEPENDENCY_FIXTURES" >/dev/null \
  || fail "Resolved-dependency boundary fixtures failed"
test -x "$PRODUCT_VERSION_FIXTURES" \
  || fail "Executable product-version boundary fixtures are missing"
"$PRODUCT_VERSION_FIXTURES" >/dev/null \
  || fail "Product-version boundary fixtures failed"
test -x "$APP_BUILD_OUTPUT_BOUNDARY" \
  || fail "Executable App build output boundary is missing"
test -x "$APP_BUILD_OUTPUT_FIXTURES" \
  || fail "Executable App build output boundary fixtures are missing"
"$APP_BUILD_OUTPUT_FIXTURES" >/dev/null \
  || fail "App build output boundary fixtures failed"

for invariant in \
  'feed == Self\.productionFeedURLString' \
  'feedURL\.scheme\?\.lowercased\(\) == "https"' \
  'keyData\.count == 32' \
  'SUVerifyUpdateBeforeExtraction.*== true' \
  'SURequireSignedFeed.*== true' \
  'SUSignedFeedFailureExpirationInterval.*== 0' \
  'SUEnableAutomaticChecks.*== true' \
  'SUScheduledCheckInterval.*Self\.scheduledCheckInterval' \
  'SUAutomaticallyUpdate.*== false' \
  'SUEnableSystemProfiling.*== false'; do
  rg -q "$invariant" "$UPDATE_CONTROLLER" \
    || fail "Authenticated updater invariant missing: $invariant"
done
for regression in \
  'testRejectsAnyUnexpectedHTTPSFeedDestination' \
  'testRejectsAnyWeakenedSecurityFlag' \
  'testRejectsMissingAuthenticatedUpdateField' \
  'testKeylessControllerNeverConstructsOrStartsRuntime' \
  'testRuntimeStartsOnceAndManualCheckHasExplicitBusyState' \
  'testFailedStartDisablesControlsAndRejectsLateCallbacks' \
  'testAutomaticCheckPreferenceMirrorsRuntimeOnlyAfterStart'; do
  rg -q "$regression" "$UPDATE_TESTS" \
    || fail "Authenticated updater regression missing: $regression"
done
for invariant in \
  'startingUpdater: false' \
  'try updater.start()' \
  'runtimeGeneration &+= 1' \
  'status = .failed' \
  'canChangeAutomaticChecks = false'; do
  rg -Fq "$invariant" "$UPDATE_CONTROLLER" \
    || fail "Updater runtime fail-closed invariant missing: $invariant"
done
if rg -U -n 'SPUStandardUpdaterController\(\n[[:space:]]*startingUpdater: true' \
  "$UPDATE_CONTROLLER"; then
  fail "Updater runtime must expose and handle Sparkle start failure explicitly"
fi

for plist_key in \
  SUFeedURL \
  SUPublicEDKey \
  SUEnableAutomaticChecks \
  SUScheduledCheckInterval \
  SUAutomaticallyUpdate \
  SUEnableSystemProfiling \
  SUVerifyUpdateBeforeExtraction \
  SURequireSignedFeed \
  SUSignedFeedFailureExpirationInterval; do
  rg -q "$plist_key" "$BUILD_SCRIPT" \
    || fail "Release bundle is missing Sparkle plist key: $plist_key"
done

rg -q -- "-add_rpath '@executable_path/../Frameworks'" "$BUILD_SCRIPT" \
  || fail "The packaged executable must resolve Sparkle from Contents/Frameworks"

rg -q 'SPARKLE_PUBLIC_ED_KEY is required for release builds' "$RELEASE_WORKFLOW" \
  || fail "Release builds must fail closed without the Sparkle public key"
rg -q 'SPARKLE_PRIVATE_ED_KEY is required to sign updates' "$RELEASE_WORKFLOW" \
  || fail "Release builds must fail closed without the Sparkle private key"
test -x "$SPARKLE_SECRET_RUNNER" \
  || fail "Repository-owned Sparkle secret-isolation runner is missing"
test -x "$SPARKLE_SECRET_FIXTURES" \
  || fail "Sparkle secret-isolation attack fixtures are missing"
rg -Fq './scripts/release/run-sparkle-appcast-generator.sh' "$RELEASE_WORKFLOW" \
  || fail "Release workflow must isolate the Sparkle generator environment"
rg -q -- '--ed-key-file -' "$SPARKLE_SECRET_RUNNER" \
  || fail "Sparkle private keys must be passed through stdin, not command arguments"
rg -Fq 'unset \' "$SPARKLE_SECRET_RUNNER" \
  || fail "Sparkle runner must remove inherited release credential variables"
rg -Fq 'env -i' "$SPARKLE_SECRET_RUNNER" \
  || fail "Sparkle generator must receive a minimal environment"
"$SPARKLE_SECRET_FIXTURES" >/dev/null \
  || fail "Sparkle release secret-isolation fixtures failed"
rg -q 'sparkle-signatures:' "$RELEASE_WORKFLOW" \
  || fail "Release workflow must verify the signed appcast block"
rg -q 'sparkle:edSignature=' "$RELEASE_WORKFLOW" \
  || fail "Release workflow must verify the signed update enclosure"

if rg -n 'SPARKLE_PRIVATE_ED_KEY' \
  IslandApp IslandAppLib IslandCore IslandCoreCLI scripts/build-app.sh; then
  fail "Sparkle private signing material must never enter app/runtime sources"
fi

if rg -n 'codesign --force --deep' "$RELEASE_WORKFLOW"; then
  fail "Release signing must sign Sparkle leaves explicitly instead of using --deep"
fi

rg -q 'performance-QA fixtures cannot be combined with a production update key' "$BUILD_SCRIPT" \
  || fail "Performance fixtures must fail closed when production update material is present"

for invariant in \
  'SWIFT_SCRATCH_ROOT="\$\{DEV_ISLAND_SWIFT_SCRATCH_ROOT:-\$\{ROOT\}/\.build\}"' \
  'SWIFT_SCRATCH_FLAVOR="app-performance-qa"' \
  'SWIFT_SCRATCH_FLAVOR="app-debug"' \
  'SWIFT_SCRATCH_FLAVOR="app-production"' \
  'SWIFT_SCRATCH_INPUT="\$\{SWIFT_SCRATCH_ROOT%/\}/\$\{SWIFT_SCRATCH_FLAVOR\}"' \
  'DEV_ISLAND_SWIFT_SCRATCH_ROOT' \
  'prepare-scratch' \
  'CONFIG must be debug or release' \
  'swift build --disable-keychain --scratch-path "\$\{SWIFT_SCRATCH_DIR\}"' \
  'performance-QA builds must use CONFIG=release' \
  'build-flavor marker verifier is missing or not executable'; do
  rg -q "$invariant" "$BUILD_SCRIPT" \
    || fail "Hermetic performance build invariant missing: $invariant"
done
rg -Fq 'BUILD_FLAVOR_VERIFIER="${ROOT}/scripts/ci/verify-performance-fixture-isolation.sh"' "$BUILD_SCRIPT" \
  || fail "Every App build must use the shared build-flavor marker verifier"
rg -Fq -- '--binary "${BUILD_FLAVOR}"' "$BUILD_SCRIPT" \
  || fail "Every App build must verify its resolved production/performance/debug flavor"
test -x "$BUILD_FLAVOR_FIXTURES" \
  || fail "Executable performance fixture isolation gate is missing"
rg -q 'verify-performance-fixture-isolation\.sh' .github/workflows/ci.yml \
  || fail "PR CI must verify fixture/production artifact isolation"
for invariant in \
  'PERFORMANCE_MARKERS=(' \
  'DEBUG_ONLY_MARKERS=(' \
  'DEV_ISLAND_FORCE_INCREASED_CONTRAST' \
  'Seed 3 (preview set)' \
  'Sandbox-injected waiting prompt' \
  'Release-shaped binary contains debug-only marker' \
  'Debug binary is missing debug-only marker' \
  'Build-flavor marker fixtures: PASS (18 negative cases)'; do
  rg -Fq "$invariant" "$BUILD_FLAVOR_FIXTURES" \
    || fail "Build-flavor artifact invariant missing: $invariant"
done
"$BUILD_FLAVOR_FIXTURES" --self-test >/dev/null

for file in \
  PRIVACY.md \
  TERMS.md \
  "$LEGAL_DOCUMENT_VIEW" \
  "$LEGAL_DOCUMENT_TESTS" \
  "$LEGAL_DOCUMENT_VERIFIER"; do
  test -s "$file" || fail "Bundled legal-document artifact missing: $file"
done
test -x "$LEGAL_DOCUMENT_VERIFIER" \
  || fail "Legal-document verifier must be executable"
"$LEGAL_DOCUMENT_VERIFIER" --self-test >/dev/null
"$LEGAL_DOCUMENT_VERIFIER" --source PRIVACY.md TERMS.md >/dev/null
for invariant in \
  'File::NOFOLLOW' \
  'must have exactly one hard link' \
  'MAX_DOCUMENT_BYTES = 512 \* 1024' \
  'bilingual review dates do not match' \
  'differs from its canonical source' \
  'Legal document fixtures: PASS \(10 negative cases\)'; do
  rg -q "$invariant" "$LEGAL_DOCUMENT_VERIFIER" \
    || fail "Legal-document verifier invariant missing: $invariant"
done
for invariant in \
  'legal-document verifier is missing or not executable' \
  '--source' \
  '"${ROOT}/PRIVACY.md"' \
  '"${ROOT}/TERMS.md"' \
  'Contents/Resources/Legal' \
  '--bundle' \
  'Bundled verified offline Privacy and Terms'; do
  rg -Fq -- "$invariant" "$BUILD_SCRIPT" \
    || fail "App build legal-document invariant missing: $invariant"
done
for invariant in \
  'Legal Documents' \
  'Offline review copies bundled with this build' \
  'LegalDocumentSheet(kind: kind)' \
  'BundledLegalDocumentLoader.load' \
  'DescriptorBackedResourceReader.read' \
  'O_RDONLY \| O_NOFOLLOW \| O_CLOEXEC \| O_NONBLOCK' \
  'snapshot.linkCount == 1' \
  'snapshot.mode & unsafeWriteBits' \
  'initial == finalDescriptor' \
  'initial == finalPath' \
  'minimumDocumentBytes = 1 \* 1024' \
  'maximumDocumentBytes = 512 \* 1024' \
  'subdirectory: "Legal"' \
  'LegalDocumentLinkPolicy.allows'; do
  if [[ "$invariant" == 'Legal Documents' \
     || "$invariant" == 'Offline review copies bundled with this build' \
     || "$invariant" == 'LegalDocumentSheet(kind: kind)' ]]; then
    rg -Fq "$invariant" "$SETTINGS_VIEW" \
      || fail "Settings legal-document entry invariant missing: $invariant"
  else
    rg -q "$invariant" "$LEGAL_DOCUMENT_VIEW" \
      || fail "Legal-document presentation invariant missing: $invariant"
  fi
done
for regression in \
  'testEnglishAndChineseSectionsUseExactReviewedTitlesAndDates' \
  'testBlockParserPreservesHeadingsBulletsAndWrappedLanguageRhythm' \
  'testMalformedBilingualStructureFailsClosed' \
  'testByteAndEncodingBoundsFailBeforePresentation' \
  'testDescriptorReaderAcceptsOnlyBoundedSingleLinkRegularFile' \
  'testDescriptorReaderRejectsSymbolicLinks' \
  'testDescriptorReaderRejectsHardLinks' \
  'testDescriptorReaderRejectsGroupOrWorldWritableResources' \
  'testDescriptorReaderRejectsFilesOutsideOneTo512KiBBoundary' \
  'testDescriptorReaderRejectsPathReplacementDuringRead' \
  'testOnlyReviewedMailAndProductLinksCanLeaveTheSheet' \
  'testInlineMarkdownStripsUnreviewedDestinations'; do
  rg -Fq "$regression" "$LEGAL_DOCUMENT_TESTS" \
    || fail "Legal-document regression missing: $regression"
done
if rg -Fq 'Data(contentsOf:' "$LEGAL_DOCUMENT_VIEW" \
   || rg -Fq 'resourceValues(forKeys:' "$LEGAL_DOCUMENT_VIEW"; then
  fail "Legal documents must be read atomically from one validated descriptor"
fi

test -x "$BUNDLE_DEPENDENCY_VERIFIER" \
  || fail "Executable app bundle dependency verifier is missing"
test -x "$BUNDLE_DEPENDENCY_FIXTURES" \
  || fail "Executable app bundle dependency attack fixtures are missing"
rg -Fq 'verify-app-bundle-dependencies.rb' "$BUILD_SCRIPT" \
  || fail "Every local app build must verify its complete dependency closure"
for workflow in .github/workflows/ci.yml "$RELEASE_WORKFLOW"; do
  rg -Fq 'verify-app-bundle-dependencies.rb' "$workflow" \
    || fail "Workflow must verify the built app dependency closure: $workflow"
done
rg -Fq 'verify-app-bundle-dependencies.sh' .github/workflows/ci.yml \
  || fail "PR CI must exercise app dependency attack fixtures"
rg -Fq 'verify-app-bundle-dependencies.sh' "$RELEASE_WORKFLOW" \
  || fail "Tagged releases must exercise app dependency attack fixtures"

if rg -n 'DEV_ISLAND_PERFORMANCE_QA' "$RELEASE_WORKFLOW"; then
  fail "The production release workflow must never compile performance fixtures"
fi

for file in \
  "$LAUNCH_HEALTH" \
  "$LAUNCH_HEALTH_TESTS" \
  "$LAUNCH_HEALTH_DOC" \
  "$LAUNCH_CRASH_DOC" \
  "$SUPPORT_DIAGNOSTICS" \
  "$SUPPORT_EXPORTER" \
  "$SUPPORT_PRESENTATION" \
  "$SUPPORT_TESTS"; do
  test -s "$file" || fail "Privacy-safe launch-health artifact missing: $file"
done
for invariant in \
  'devIsland\.launchHealth\.didStart' \
  'devIsland\.launchHealth\.startupReady' \
  'devIsland\.launchHealth\.schemaVersion' \
  'devIsland\.launchHealth\.consecutiveStartupInterruptions' \
  'maximumConsecutiveStartupInterruptions = 3' \
  'startupStabilityDelay: TimeInterval = 2' \
  'case firstLaunch' \
  'case ready' \
  'case startupInterrupted' \
  'case legacyUnknown' \
  '#if DEV_ISLAND_PERFORMANCE_QA'; do
  rg -q "$invariant" "$LAUNCH_HEALTH" \
    || fail "Launch-health invariant missing: $invariant"
done
rg -q 'LaunchHealthTracker\.shared\.beginLaunch\(\)' "$APP_ENTRY" \
  || fail "App launch must arm the local startup-readiness sentinel"
rg -q 'scheduleStartupHealthMilestone\(afterLayingOut: window\)' "$APP_ENTRY" \
  || fail "App launch must schedule the bounded startup-readiness milestone"
rg -q 'LaunchHealthTracker\.shared\.markStartupReady\(\)' "$APP_ENTRY" \
  || fail "App lifecycle must close the startup-readiness marker"
rg -q 'Previous Launch:' "$SUPPORT_DIAGNOSTICS" \
  || fail "Redacted diagnostics must include the coarse previous-launch state"
rg -q 'There is no automatic safe mode' "$LAUNCH_HEALTH_DOC" \
  || fail "Launch-health recovery must document the non-invasive safe-mode boundary"
rg -q '@rpath/Sparkle\.framework' "$LAUNCH_CRASH_DOC" \
  || fail "Historical launch-time framework failure must stay documented"
rg -q 'swift_task_dealloc' "$LAUNCH_CRASH_DOC" \
  || fail "Historical root-view concurrency failure must stay documented"
if rg -n '\bDate\b|ProcessInfo|URLSession|NSCrash|CrashReporter|Sentry|FileManager' "$LAUNCH_HEALTH"; then
  fail "Launch health must remain bounded and must never inspect, timestamp, or upload crash artifacts"
fi

test -s "$ISLAND_ROOT_VIEW" || fail "Island root view missing"
rg -q 'schedulePresentationRefresh\(at:' "$ISLAND_ROOT_VIEW" \
  || fail "Completion-expiry refresh must use the cancellable main-queue scheduler"
rg -q 'presentationRefreshID' "$ISLAND_ROOT_VIEW" \
  || fail "Completion-expiry refresh must invalidate stale callbacks"
if rg -n 'Task\.sleep' "$ISLAND_ROOT_VIEW"; then
  fail "IslandRootView must not use sleeping Swift tasks; historical builds aborted during task teardown"
fi

for file in \
  "$INTERFACE_COLORS" \
  "$INTERFACE_CONTRAST_TESTS" \
  "$ACTION_REQUEST_SURFACE"; do
  test -s "$file" || fail "Product-wide Increase Contrast artifact missing: $file"
done
for invariant in \
  'accessibilityDisplayShouldIncreaseContrast' \
  'DEV_ISLAND_FORCE_INCREASED_CONTRAST' \
  'case secondaryText' \
  'case tertiaryText' \
  'case hairline' \
  'case islandBorder' \
  'case idleState' \
  'systemPrefersIncreasedContrast' \
  'usesIncreasedContrast'; do
  rg -Fq "$invariant" "$INTERFACE_COLORS" \
    || fail "Product-wide Increase Contrast invariant missing: $invariant"
done
rg -Uq '#if DEBUG\n[[:space:]]*if ProcessInfo\.processInfo\.environment\[' "$INTERFACE_COLORS" \
  || fail "Forced Increase Contrast override must remain DEBUG-only"
rg -Fq 'Palette.islandBorder.opacity' "$ISLAND_ROOT_VIEW" \
  || fail "Expanded island boundary must use the adaptive contrast token"
rg -Fq 'InterfaceContrastPolicy.usesIncreasedContrast' "$ACTION_REQUEST_SURFACE" \
  || fail "Decision surfaces must share the product-wide contrast policy"
for regression in \
  'testHighContrastPaletteStrengthensEveryQuietRole' \
  'testRequiredTextRolesRetainAndIncreaseContrastOnRaisedSurface' \
  'testIncreasedBorderWidthNeverThinsExistingGeometry'; do
  rg -Fq "$regression" "$INTERFACE_CONTRAST_TESTS" \
    || fail "Product-wide Increase Contrast regression missing: $regression"
done

for invariant in \
  'maximumReportBytes = 128 * 1_024' \
  'O_NOFOLLOW' \
  'S_IRUSR | S_IWUSR' \
  'Darwin.fsync' \
  'Darwin.lstat' \
  'Darwin.rename'; do
  rg -Fq "$invariant" "$SUPPORT_EXPORTER" \
    || fail "Private diagnostic-file export invariant missing: $invariant"
done
for invariant in 'NSSavePanel' 'Nothing is uploaded'; do
  rg -Fq "$invariant" "$SETTINGS_VIEW" \
    || fail "User-controlled diagnostic save invariant missing: $invariant"
done
if rg -n 'SupportDiagnosticsExporter\.write\(' "$SETTINGS_VIEW"; then
  fail "Settings must never perform synchronous diagnostic-file I/O on the main actor"
fi
for invariant in \
  'SupportDiagnosticsIOExecutor\.run\(' \
  'SupportDiagnosticsExportWorker\.write\(report, to: destination\)' \
  'diagnosticsOperation\.invalidate\(\)' \
  'diagnosticsFeedback\.invalidate\(\)'; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Diagnostic save operation-ownership invariant missing: $invariant"
done
for regression in \
  'testExporterWritesPrivateUTF8FileAndNormalizesFinalNewline' \
  'testExporterAtomicallyReplacesARegularFileAndKeepsPrivateMode' \
  'testExporterRejectsSymlinkWithoutChangingItsTarget' \
  'testExporterRejectsEmptyOversizedAndUnavailableDestinations' \
  'testSuggestedFilenameIsStableAndContainsNoUserData' \
  'testDiagnosticOperationInvalidationRejectsLateCompletion' \
  'testDiagnosticFeedbackUsesIdentityInsteadOfMessageEquality' \
  'testDiagnosticIOExecutorLeavesTheMainThread' \
  'testDiagnosticExportWorkerReturnsBoundedOutcome'; do
  rg -q "$regression" "$SUPPORT_TESTS" \
    || fail "Diagnostic-file export regression missing: $regression"
done
if rg -n 'URLSession|NSSharingService|NSPasteboard|NSWorkspace' "$SUPPORT_EXPORTER"; then
  fail "Diagnostic-file exporter must remain local-file-only and own no upload, clipboard, sharing, or app-launch behavior"
fi

for file in "$STATUS_MENU" "$STATUS_MENU_PRESENTATION" "$STATUS_MENU_TESTS"; do
  test -s "$file" || fail "Privacy-minimal status-menu artifact missing: $file"
done
for invariant in \
  'StatusMenuPresentation.snapshot' \
  'setAccessibilityValue' \
  'withObservationTracking' \
  'Check for Updates…'; do
  rg -Fq "$invariant" "$STATUS_MENU" \
    || fail "Live status-menu invariant missing: $invariant"
done
for invariant in \
  'struct StatusMenuSnapshot' \
  'static func snapshot' \
  'static func headline' \
  'static func overview' \
  'static func nextRefreshDate' \
  'static func localAgents' \
  'static func manus' \
  'Local agents: Ready' \
  'Manus: Polling only' \
  'Available in signed release builds.'; do
  rg -Fq "$invariant" "$STATUS_MENU_PRESENTATION" \
    || fail "Low-cardinality status-menu copy missing: $invariant"
done
for regression in \
  'testHeadlineUsesAttentionPriorityAndCorrectGrammar' \
  'testHeadlineLetsStaleCompletionYieldToRunningAndHandlesIdle' \
  'testOverviewKeepsAttentionPriorityAndAddsTotalSessionCount' \
  'testSnapshotAccessibilityValueIsLowCardinalityAndPrivate' \
  'testNextRefreshDateUsesOnlyEarliestFutureCompletionExpiry' \
  'testLocalAgentHealthUsesCompactTransportOnlyCopy' \
  'testManusAndUpdateCopyNeverExposeRawReason' \
  'testMenuHealthCopyFollowsExplicitSimplifiedChineseLanguage'; do
  rg -q "$regression" "$STATUS_MENU_TESTS" \
    || fail "Status-menu regression missing: $regression"
done
if rg -n 'LocalAgentRegistry\.all\.map|task\.title|task\.id|taskURL|degraded\(let reason\)' \
  "$STATUS_MENU" "$STATUS_MENU_PRESENTATION"; then
  fail "Status menu must not render raw connector, title, session, URL, or degraded-reason data"
fi
for stale_copy in \
  '后台运行中' \
  '本地管线' \
  '打开面板' \
  '检查更新'; do
  if rg -Fq "$stale_copy" "$STATUS_MENU" "$STATUS_MENU_PRESENTATION"; then
    fail "Status menu must use the same English product language as the App: $stale_copy"
  fi
done

for file in "$DOCK_VISIBILITY" "$DOCK_VISIBILITY_TESTS"; do
  test -s "$file" || fail "Deterministic Dock-policy retry artifact missing: $file"
done
for invariant in \
  'typealias RetryScheduler' \
  '16 << retryAttempt' \
  'scheduleRetryAfterDelay' \
  'self.retryID == scheduledRetryID'; do
  rg -Fq "$invariant" "$DOCK_VISIBILITY" \
    || fail "Bounded Dock-policy retry invariant missing: $invariant"
done
for regression in \
  'testFailedPromotionRetriesAutomaticallyOnTheNextTurn' \
  'testFailedDemotionRetriesAutomaticallyOnTheNextTurn' \
  'testRepeatedPromotionFailuresRemainBoundedAndCanRecover' \
  'testAutomaticRetriesStopAfterTheBound' \
  'testPendingPromotionRetryUsesLatestStateAfterRelease' \
  'testPendingDemotionRetryUsesLatestStateAfterNewLease' \
  'testExplicitSynchronizeCanRecoverAfterRetryLimit'; do
  rg -q "$regression" "$DOCK_VISIBILITY_TESTS" \
    || fail "Dock-policy retry regression missing: $regression"
done
rg -Fq 'XCTAssertEqual(scheduler.delays, [16, 32, 64])' "$DOCK_VISIBILITY_TESTS" \
  || fail "Dock-policy tests must pin the production exponential backoff sequence"
if rg -n 'Task\.sleep|Thread\.sleep|usleep' "$DOCK_VISIBILITY_TESTS"; then
  fail "Dock-policy tests must use deterministic scheduler draining instead of wall-clock sleeps"
fi

for file in \
  "$OPENCODE_AGENT" \
  "$OPENCODE_EVENT" \
  "$OPENCODE_PLUGIN" \
  "$STANDALONE_PLUGIN_EDITOR" \
  "$OPENCODE_CONNECTOR_TESTS" \
  "$OPENCODE_INSTALLER_TESTS" \
  "$OPENCODE_NOTES" \
  "$OPENCODE_LOGO" \
  "$OPENCODE_LOGO_LICENSE" \
  "$OPENCODE_LOGO_TESTS"; do
  test -s "$file" || fail "OpenCode Preview security artifact missing: $file"
done
[[ "$(shasum -a 256 "$OPENCODE_LOGO" | awk '{print $1}')" == \
  "d6a0e3b8a295f413543f41cb73957e670351b5cb088c8d9dbd186b9e9d633cca" ]] \
  || fail "OpenCode official square logo must match the reviewed upstream asset"
rg -q 'Copyright \(c\) 2025 opencode' "$OPENCODE_LOGO_LICENSE" \
  || fail "OpenCode logo license notice is missing"
rg -q 'testOfficialOpenCodeMarkLoadsAsAdaptiveTemplateAsset' "$OPENCODE_LOGO_TESTS" \
  || fail "OpenCode logo bundle regression is missing"
for invariant in \
  'pinnedVersion = "1\.18\.23"' \
  'pinnedCommit = "13c27598d35f6f91fa4763a0b61a220ab7fcb263"' \
  'configPath: "~/\.config/opencode/plugins/dev-island\.js"' \
  'releaseStage: \.preview' \
  'permissionRequests: \.observeOnly' \
  'Dev Island managed local plugin: opencode'; do
  rg -q "$invariant" "$OPENCODE_AGENT" "$OPENCODE_PLUGIN" \
    || fail "OpenCode Preview pinned contract invariant missing: $invariant"
done
for invariant in \
  'schema_version: 1' \
  'new AbortController\(\)' \
  'setTimeout\(\(\) => controller\.abort\(\), 1000\)' \
  'void fetch\(endpoint' \
  '\.catch\(\(\) => \{\}\)\.finally\(\(\) => clearTimeout\(timeout\)\)' \
  'case "session\.created"' \
  'case "session\.status"' \
  'case "session\.idle"' \
  'case "session\.deleted"' \
  'case "session\.error"' \
  'case "permission\.updated"' \
  'case "permission\.replied"'; do
  rg -q "$invariant" "$OPENCODE_PLUGIN" \
    || fail "OpenCode privacy-minimal plugin invariant missing: $invariant"
done
if rg -n 'permission\.ask|await fetch\(endpoint|(^|[[:space:]])(require\(|import[[:space:]].*from)' \
  "$OPENCODE_PLUGIN"; then
  fail "OpenCode Preview must remain dependency-free, fail-open, and must not modify permission.ask output"
fi
if rg -n 'public let (title|prompt|message|tool|permission|metadata|error|errorMessage|output)' \
  "$OPENCODE_EVENT"; then
  fail "OpenCode Preview must not model vendor-authored content fields"
fi
for invariant in \
  'maximumPluginBytes = 256 \* 1_024' \
  'installedPermissions = 0o600' \
  'case \.occupied' \
  'ManagedConfigFile\.snapshotIfExists' \
  'pathEntryExists'; do
  rg -q "$invariant" "$STANDALONE_PLUGIN_EDITOR" \
    || fail "Standalone plugin ownership boundary missing: $invariant"
done
for regression in \
  'testPinnedPrivacyEnvelopeIgnoresVendorContentAndMetadata' \
  'testSchemaSessionEventAndStatusAllowlistRejectsUnsupportedPayloads' \
  'testOpenCodePreviewHTTPRouteDeliversPrivacyMinimalWaitingEvent' \
  'testRendererIsExactAndPinsReviewedUpstreamContract' \
  'testRendererIsDependencyFreePrivacyMinimalAndFailOpen' \
  'testInstallIsIdempotentUpdatesOwnedFileAndUninstalls' \
  'testUnownedCollisionIsNeverOverwrittenOrRemoved' \
  'testSymlinkAndDirectoryCollisionsFailClosed' \
  'testOversizedManagedLookingFileIsNeverReadAsOwnedOrChanged' \
  'testLaterWriteFailureRestoresDeletedOpenCodePluginAndPermissions' \
  'testRollbackNeverOverwritesExternallyRecreatedPluginFile' \
  'testRollbackTreatsDanglingPluginSymlinkAsExternalConflict'; do
  rg -q "$regression" \
    "$OPENCODE_CONNECTOR_TESTS" \
    "$OPENCODE_INSTALLER_TESTS" \
    "$LOCAL_ACTION_TESTS" \
    "$HOOK_MAINTENANCE_TESTS" \
    || fail "OpenCode Preview regression missing: $regression"
done

for file in \
  "$LICENSE_VERIFIER" \
  "$LICENSE_TESTS" \
  "$LICENSE_STORE" \
  "$LICENSE_STORE_TESTS" \
  "$LICENSE_ACTIVATION" \
  "$LICENSE_ACTIVATION_TESTS" \
  "$LICENSE_SECURITY_DOC" \
  "$LICENSE_THREAT_MODEL" \
  "$COMMERCIAL_POLICY" \
  "$COMMERCIAL_POLICY_DOC"; do
  test -s "$file" || fail "Commercial license security artifact missing: $file"
done

test -x "$COMMERCIAL_POLICY_VERIFIER" \
  || fail "Executable commercial policy verifier is missing"
test -x "$COMMERCIAL_POLICY_FIXTURES" \
  || fail "Executable commercial policy fixtures are missing"
"$COMMERCIAL_POLICY_VERIFIER" --policy "$COMMERCIAL_POLICY" >/dev/null \
  || fail "Commercial policy record failed validation"
"$COMMERCIAL_POLICY_FIXTURES" >/dev/null \
  || fail "Commercial policy attack fixtures failed"
if "$COMMERCIAL_POLICY_VERIFIER" \
  --policy "$COMMERCIAL_POLICY" \
  --require-approved >/dev/null 2>&1; then
  fail "Commercial policy must remain unapproved until owner/legal review"
fi
for invariant in \
  'MAXIMUM_POLICY_BYTES = 131_072' \
  'File::RDONLY | File::NOFOLLOW | File::NONBLOCK' \
  'before\.uid == Process\.uid' \
  'before\.nlink == 1' \
  '\(before\.mode & 0o022\)\.zero\?' \
  'stable_metadata\?\(before, after\)' \
  'stable_metadata\?\(after, path_after\)' \
  'stable_metadata\?\(parent_before, parent_after\)' \
  'object_class: CommercialPolicyObject' \
  'contains a duplicate JSON key'; do
  rg -q "$invariant" "$COMMERCIAL_POLICY_VERIFIER" \
    || fail "Commercial policy input-boundary invariant missing: $invariant"
done
for regression in \
  'hard-link' \
  'unsafe-mode' \
  'oversized' \
  'directory' \
  'parent-symlink' \
  'duplicate-root' \
  'duplicate-nested' \
  'replaced-during-read' \
  'leaked a fixture path'; do
  rg -Fq "$regression" "$COMMERCIAL_POLICY_FIXTURES" \
    || fail "Commercial policy input-boundary regression missing: $regression"
done

for invariant in \
  'Curve25519\.Signing\.PublicKey' \
  'case commercialModeDisabled' \
  'domainSeparator = "DevIsland\.CommercialLicense\\0v1\\0"' \
  'let generation: Int64' \
  'payload\.generation > 0' \
  'Set\(dictionary\.keys\) == payloadKeys' \
  'public init\(\)'; do
  rg -q "$invariant" "$LICENSE_VERIFIER" \
    || fail "Commercial verifier invariant missing: $invariant"
done

if rg -n 'Signing\.PrivateKey|ProcessInfo|UserDefaults|URLSession' \
  IslandCore/Sources/IslandCore/Commerce --glob '*.swift'; then
  fail "Commercial runtime trust must remain public-key-only, local, and code-reviewed"
fi

if rg -n 'CommercialLicenseVerifier\(trustedKeys:' \
  IslandApp IslandAppLib IslandCore/Sources/IslandCore --glob '*.swift'; then
  fail "Commercial mode must remain disabled until a production trust-anchor review"
fi

for invariant in \
  'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' \
  'kSecAttrSynchronizable: false' \
  'case storedDocumentTooLarge' \
  'case storedDocumentRejected' \
  'case rollbackRejected' \
  'case conflictingGeneration' \
  'guard case \.valid\(let incomingLicense\) = evaluation' \
  'private func saveAuthenticated' \
  'CommercialLicenseStoreMutationLock' \
  'incomingLicense\.generation' \
  'storedLicense\.generation' \
  'maximumDocumentBytes ='; do
  rg -q "$invariant" "$LICENSE_STORE" \
    || fail "Commercial license storage invariant missing: $invariant"
done
rg -q 'CommercialLicenseVerifier\.maximumDocumentBytes' "$LICENSE_STORE" \
  || fail "Commercial verifier and Keychain store must share one document-size bound"
if rg -n 'CommercialLicenseDocumentStore\(\)' \
  IslandApp IslandAppLib IslandCore/Sources/IslandCore --glob '*.swift'; then
  fail "Commercial license storage must remain disconnected until activation is approved"
fi
if rg -n 'public func (save|load)\(' "$LICENSE_STORE"; then
  fail "Commercial license bearer bytes must only cross the verify-before-save API"
fi
for storage_regression in \
  'testVerifiedImportRoundTripsAndReplacesDocument' \
  'testDisabledOrInvalidReplacementPreservesVerifiedDocument' \
  'testStoredOversizedDocumentFailsClosedOnEvaluation' \
  'testImportedDocumentUsesDeviceOnlyNonSynchronizingProtection' \
  'testOlderGenerationCannotReplaceNewerStoredLicense' \
  'testEqualGenerationIsIdempotentButConflictingBytesAreRejected' \
  'testHigherGenerationCannotMoveSignedIssuanceTimeBackward' \
  'testConcurrentImportsCannotLeaveAnOlderGenerationStored'; do
  rg -q "$storage_regression" "$LICENSE_STORE_TESTS" \
    || fail "Commercial license storage regression missing: $storage_regression"
done

for invariant in \
  'minimumUTF8Bytes = 16' \
  'maximumUTF8Bytes = 128' \
  '<redacted activation code>' \
  'CommercialActivationSecretStorage' \
  'Self\.secureErase' \
  'memset_s' \
  'public protocol CommercialActivationTransport: Sendable' \
  'case codeRejected' \
  'case transportUnavailable' \
  'case licenseRejected' \
  'case secureStorageUnavailable' \
  'previous\.state\.invalidate\(as: \.superseded\)' \
  'state\.invalidate\(as: \.cancelled\)' \
  'guard state\.claimCommit\(\)' \
  'evaluationClock' \
  'now: evaluationClock\(\)' \
  'store\.importDocument\('; do
  rg -q "$invariant" "$LICENSE_ACTIVATION" \
    || fail "Commercial activation invariant missing: $invariant"
done
if rg -n 'public (let|var) (rawValue|value|code|utf8Bytes)' "$LICENSE_ACTIVATION"; then
  fail "Commercial activation codes must not expose a reusable raw-value property"
fi
if rg -n 'URL\(|https?://|URLRequest|IslandLogger|os_log|print\(' \
  "$LICENSE_ACTIVATION"; then
  fail "Provider-neutral activation core must remain endpoint-free and unlogged"
fi
if rg -n 'CommercialLicenseActivationService\(' \
  IslandApp IslandAppLib IslandCore/Sources/IslandCore --glob '*.swift'; then
  fail "Commercial activation must remain disconnected until provider and policy review"
fi
for activation_regression in \
  'testActivationCodeUsesBoundedAlphabetAndAlwaysRedacts' \
  'testActivationCodeUsesSharedDedicatedStorageAndSecureErase' \
  'testDisabledVerifierRejectsBeforeCallingTransport' \
  'testSuccessfulActivationVerifiesAndRoundTripsThroughKeychain' \
  'testTamperedAndOversizedResponsesNeverReplaceValidDocument' \
  'testTransportErrorsAreNormalizedWithoutLeakingRawDetails' \
  'testLatestConcurrentActivationIsTheOnlyDocumentSaved' \
  'testExplicitCancellationRejectsLateTransportResponse' \
  'testResponseIsEvaluatedAtCommitTimeNotRequestStart' \
  'testSignedRollbackIsRejectedWithoutReplacingCurrentLicense'; do
  rg -q "$activation_regression" "$LICENSE_ACTIVATION_TESTS" \
    || fail "Commercial activation regression missing: $activation_regression"
done
for documented_control in \
  'raw-body signature verification' \
  'durable event-ID uniqueness' \
  'Single-use short-lived activation code' \
  'WhenUnlockedThisDeviceOnly' \
  'Hardware fingerprint.*Rejected baseline' \
  'commercial mode must stay disabled'; do
  rg -qi "$documented_control" "$LICENSE_THREAT_MODEL" \
    || fail "Commercial activation threat model control missing: $documented_control"
done

rg -q 'address: \.hostname\("127\.0\.0\.1", port: port\)' "$LOCAL_HOOK_SERVER" \
  || fail "Local Agent hooks must bind only to numeric loopback"
for invariant in \
  'requestHeaderName = "X-Dev-Island-Hook"' \
  'requestHeaderValue = "v1"'; do
  rg -Fq "$invariant" "$LOCAL_HOOKS_INSTALLER" \
    || fail "Local Hook browser-preflight request contract missing: $invariant"
done
rg -Fq 'request.headers[hookHeaderName] == LocalHooksInstaller.requestHeaderValue' \
  "$LOCAL_HOOK_SERVER" \
  || fail "Local Hook listener must fail closed without the exact custom header"
for file in "$LOCAL_HOOK_AUTHORIZATION" "$LOCAL_HOOK_AUTHORIZATION_TESTS"; do
  test -s "$file" || fail "Local Hook cross-user authorization artifact missing: $file"
done
for invariant in \
  'headerName = "X-Dev-Island-Authorization"' \
  'randomByteCount = 32' \
  'maximumHeaderFileBytes = 128' \
  'SecRandomCopyBytes' \
  'ManagedConfigFile.replace' \
  'permissions: ManagedConfigFile.privatePermissions' \
  'memset_s'; do
  rg -Fq "$invariant" "$LOCAL_HOOK_AUTHORIZATION" \
    || fail "Local Hook cross-user authorization invariant missing: $invariant"
done
rg -Fq 'authorization.matches(request.headers[authorizationHeaderName])' \
  "$LOCAL_HOOK_SERVER" \
  || fail "Local Hook listener must verify the current random authorization value"
rg -Fq '"-H \"@\(LocalHookAuthorizationStore.shellHeaderFilePath)\" "' \
  "$LOCAL_HOOKS_INSTALLER" \
  || fail "Managed curl Hooks must read authorization from the private header file"
rg -Fq 'LocalHooksInstaller.requestHeaderName' "$OPENCODE_PLUGIN" \
  || fail "OpenCode plugin must carry the local Hook custom header"
for invariant in \
  'LocalHookAuthorizationStore.relativeHeaderFilePath' \
  'Bun.file(authorizationPath)' \
  'file.slice(0, \(LocalHookAuthorizationStore.maximumHeaderFileBytes + 1))' \
  'LocalHookAuthorization.headerName'; do
  rg -Fq "$invariant" "$OPENCODE_PLUGIN" \
    || fail "OpenCode private authorization-file boundary missing: $invariant"
done
for invariant in \
  'maxConsecutiveFailures: 5' \
  '\.seconds\(min\(30, failure \* 5\)\)' \
  'guard onEvent != nil, !isServing'; do
  rg -q "$invariant" "$LOCAL_HOOK_SERVER" \
    || fail "Local Hook wake-recovery production invariant missing: $invariant"
done
rg -q 'NSWorkspace\.didWakeNotification' "$TASK_STORE" \
  || fail "TaskStore must observe system wake"
rg -Fq 'await localHookServer?.ensureRunning()' "$TASK_STORE" \
  || fail "System wake must re-arm an exhausted local Hook listener"
for regression in \
  'testWakeHealthCheckRecoversAfterAutomaticRetriesAreExhausted' \
  'testWakeHealthCheckDoesNotRestartHealthyListener' \
  'testAuthorizationPreparationFailureNeverBindsTheHookListener' \
  'testListenerRestartRotatesCredentialAndRejectsThePriorEpoch' \
  'testPermissionHTTPRoundTripAndBrowserRequestBoundary' \
  'testRotationCreatesPrivateBoundedHeaderAndInvalidatesOldCredential' \
  'testSymlinkAndHardLinkTargetsFailClosedWithoutMutation'; do
  rg -q "$regression" "$LOCAL_HOOK_HEALTH_TESTS" "$LOCAL_ACTION_TESTS" "$LOCAL_HOOK_AUTHORIZATION_TESTS" \
    || fail "Local Hook wake-recovery regression missing: $regression"
done

for file in "$TUNNEL_MANAGER" "$TUNNEL_MANAGER_TESTS"; do
  test -s "$file" || fail "Manus realtime lifecycle artifact missing: $file"
done
for invariant in \
  'private var activeTransport: RegisteredTransport?' \
  'func handleSleepWake\(\) async throws' \
  'await process.stop()' \
  'onRealtimeUnavailable' \
  'case lifecycleSuperseded'; do
  rg -q "$invariant" "$TUNNEL_MANAGER" \
    || fail "Manus realtime lifecycle invariant missing: $invariant"
done
for invariant in \
  'handleManusRealtimeUnavailable' \
  'ManusConnectionStatusPolicy\.restoredStatus' \
  'Manus realtime wake recovery failed' \
  'try await tunnel\.handleSleepWake\(\)'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "TaskStore realtime downgrade invariant missing: $invariant"
done
for regression in \
  'testRegistrationFailureStopsUnregisteredProcessAndRollsBackServer' \
  'testWakeFailureIsReturnedAndCannotLeaveProcessOnlyRealtime' \
  'testSuccessfulWakeRestoresOnlyAfterWebhookRegistration' \
  'testHeartbeatRegistrationFailureSignalsPollingOnlyAndStopsReplacement' \
  'testSuccessfulPollCannotPromotePollingOnlyModeToConnected' \
  'testStopDuringRegistrationDeletesLateWebhookAndLeavesNoTransport'; do
  rg -q "$regression" "$TUNNEL_MANAGER_TESTS" \
    || fail "Manus realtime lifecycle regression missing: $regression"
done
for file in "$POLLING_FALLBACK" "$POLLING_FALLBACK_TESTS"; do
  test -s "$file" || fail "Manus polling lifecycle artifact missing: $file"
done
for invariant in \
  'actor PollingFallback' \
  'private var lifecycleGeneration: UInt64' \
  'onUnauthorized' \
  'guard isCurrent\(generation\)' \
  'pollingTask\?\.cancel\(\)'; do
  rg -q "$invariant" "$POLLING_FALLBACK" \
    || fail "Manus polling lifecycle invariant missing: $invariant"
done
if rg -n 'nonisolated\(unsafe\)' "$POLLING_FALLBACK"; then
  fail "PollingFallback must not restore unsafe shared task state"
fi
for invariant in \
  'ingestManusWebhookEvent' \
  'applyManusPollingSnapshot' \
  'handleManusPollingUnauthorized' \
  'serviceGeneration == manusServiceGeneration'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "TaskStore stale-callback invariant missing: $invariant"
done
for regression in \
  'testStopSuppressesLateSnapshotFromCancellationUnawareConnector' \
  'testRestartInvalidatesOlderInFlightPoll' \
  'testNetworkEdgesAreCoalescedAndUnauthorizedStopsPolling'; do
  rg -q "$regression" "$POLLING_FALLBACK_TESTS" \
    || fail "Manus polling lifecycle regression missing: $regression"
done
test -s "$MANUS_LIFECYCLE_TESTS" \
  || fail "TaskStore Manus account-lifecycle regressions are missing"
test -x "$SLEEP_WAKE_STABILITY_FIXTURE" \
  || fail "Sleep/wake lifecycle stability fixture must be executable"
for invariant in \
  'private var manusConfigurationGeneration: UInt64' \
  'struct TaskStoreManusDependencies: Sendable' \
  'public func clearAPIKey\(\) async throws' \
  'detachManusServices' \
  'configurationGeneration == manusConfigurationGeneration'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "TaskStore Manus account-lifecycle invariant missing: $invariant"
done
for invariant in \
  'protocol ManusTunnelLifecycleProtocol: Sendable' \
  'private var manusSleepSuspension: ManusSleepSuspension?' \
  'private var systemPowerGeneration: UInt64' \
  'guard let pendingSuspension = manusSleepSuspension else \{ return \}' \
  'await pendingSuspension\.task\.value' \
  'wakeGeneration == systemPowerGeneration' \
  'handleSystemWillSleep\(\)' \
  'handleSystemDidWake\(\)'; do
  rg -q "$invariant" "$TUNNEL_MANAGER" "$TASK_STORE" \
    || fail "Ordered system sleep/wake invariant missing: $invariant"
done
SLEEP_WAKE_BODY="$(sed -n '/MARK: - Sleep \/ wake/,$p' "$TASK_STORE")"
if printf '%s\n' "$SLEEP_WAKE_BODY" | rg -n 'Task\.detached'; then
  fail "System sleep suspend must remain an awaited wake barrier, not detached work"
fi
for invariant in \
  'try await store\.clearAPIKey\(\)' \
  'saved key couldn’t be removed'; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Settings disconnect integrity invariant missing: $invariant"
done
for regression in \
  'testDisconnectSupersedesValidationBeforeItCanPersistOrRestart' \
  'testLatestConcurrentConfigurationIsTheOnlyKeyPersisted' \
  'testReplacingServiceRejectsLateSnapshotFromPreviousKey' \
  'testRuntimeUnauthorizedInvalidatesVisibleAccountState' \
  'testUnauthorizedCandidateNeverOverwritesKeychain' \
  'testKeychainDeleteFailureNeverPretendsCredentialWasRemoved' \
  'testWakeWaitsForBlockedSuspendBeforeRestartingRealtime' \
  'testDuplicateWakeDoesNotRestartRealtimeTwice' \
  'testDisconnectDuringBlockedSuspendPreventsObsoleteWakeRecovery' \
  'testNewSleepSupersedesInFlightWakeFailureWithoutFalseDegradation'; do
  rg -q "$regression" "$MANUS_LIFECYCLE_TESTS" \
    || fail "TaskStore Manus account-lifecycle regression missing: $regression"
done
for invariant in \
  'ITERATIONS=20' \
  "FILTER='TaskStoreManusLifecycleTests'" \
  '--scratch-path "$TEST_SCRATCH"' \
  '--skip-build --filter' \
  'Test Case .* failed|error:' \
  'Sleep/wake lifecycle stability: PASS'; do
  rg -Fq -- "$invariant" "$SLEEP_WAKE_STABILITY_FIXTURE" \
    || fail "Sleep/wake lifecycle stability fixture missing: $invariant"
done
rg -Fq './scripts/ci/verify-sleep-wake-lifecycle-stability.sh' "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative tests must repeat sleep/wake lifecycle ordering after the full suite"
rg -q '<key>NSAllowsLocalNetworking</key>' "$INFO_PLIST" \
  || fail "The loopback readiness probe requires an explicit local-only ATS exception"
if rg -n 'NSAllowsArbitraryLoads' "$INFO_PLIST"; then
  fail "The app must not weaken ATS for external destinations"
fi

rg -q 't\.primaryKey\(colSource, colId\)' "$SQLITE_STORE" \
  || fail "Persisted tasks must use source-aware composite identity"
rg -q 'public private\(set\) var storedTaskHistory:' "$TASK_STORE" \
  || fail "Persisted history must have a dedicated read-only presentation state"
if rg -n 'setTasks\((storedTaskHistory|page\.tasks)' "$TASK_STORE"; then
  fail "Persisted history must never be restored into the live island task queue"
fi

for file in \
  "$HOOK_MAINTENANCE" \
  "$HOOK_EDITOR" \
  "$HOOK_MAINTENANCE_TESTS" \
  "$MANAGED_CONFIG_FILE" \
  "$MANAGED_CONFIG_TESTS" \
  "$AGENT_CONNECTIONS" \
  "$AGENT_CONNECTIONS_TESTS"; do
  test -s "$file" || fail "Managed-Hook maintenance artifact missing: $file"
done
for invariant in \
  'O_DIRECTORY \| O_NOFOLLOW \| O_CLOEXEC' \
  'AT_SYMLINK_NOFOLLOW' \
  'information\.st_nlink == 1' \
  'maximumConfigBytes = 4 \* 1_024 \* 1_024' \
  'case snapshot\(Snapshot\)' \
  'fsync\(parentDescriptor\)' \
  'RENAME_EXCL' \
  'RENAME_SWAP' \
  'restoreAfterFailedSwap' \
  'restoreQuarantinedFile' \
  'configurationChanged'; do
  rg -q "$invariant" "$MANAGED_CONFIG_FILE" \
    || fail "Managed configuration file boundary missing: $invariant"
done
for invariant in \
  '\.snapshot\(change\.originalSnapshot\)' \
  'committedSnapshot' \
  'expected = \.absent' \
  'preparedUninstall' \
  'rollback\(written\)'; do
  rg -q "$invariant" "$HOOK_MAINTENANCE" "$HOOK_EDITOR" \
    || fail "Bulk managed-Hook rollback invariant missing: $invariant"
done
for regression in \
  'testMalformedManagedConfigFailsBeforeAnyWrite' \
  'testLaterWriteFailureRollsBackEarlierFilesByteForByte' \
  'testConcurrentEditIsPreservedAndEarlierWriteRollsBack' \
  'testRollbackNeverOverwritesAnExternalEdit' \
  'testIndividualUninstallRemovesOnlyManagedHandlerFromMixedGroup' \
  'testSymlinkedManagedJSONIsVisibleButNeverTrustedOrMutated' \
  'testHardLinkedManagedJSONIsNeverTrustedOrMutated' \
  'testSymlinkedManagedTOMLIsVisibleButNeverMutated' \
  'testOversizedJSONAndDirectoryTargetsFailWithoutMutation' \
  'testSnapshotComparisonRejectsInPlaceMutationWithSameInode' \
  'testAbsentCommitNeverOverwritesAFileCreatedAtTheFinalRace' \
  'testExistingCommitRestoresAReplacementCreatedAtTheFinalRace' \
  'testRemoveRestoresAReplacementCreatedAtTheFinalRace' \
  'testNewConfigsArePrivateAndExistingPermissionsSurviveUpdate' \
  'testSymlinkedParentDirectoryIsSafelyResolvedAndAnchored' \
  'testDanglingParentDirectoryLinkIsRejectedWithoutCreatingTarget' \
  'testGroupWritableParentDirectoryIsRejectedWithoutCreatingTarget' \
  'testUnsafeStructuredConfigStopsBulkRemovalBeforeAnyWrite'; do
  rg -q "$regression" "$HOOK_MAINTENANCE_TESTS" "$MANAGED_CONFIG_TESTS" \
    || fail "Managed-Hook removal regression missing: $regression"
done

for invariant in \
  'enum LocalAgentMaintenanceOutcome' \
  'case noChanges' \
  'case disconnected\(count: Int\)' \
  'case failed' \
  'guard activeOperationID == nil else \{ return nil \}' \
  'activeMutation == \.disconnectAll' \
  'LocalAgentHookMaintenance\.removeAllManagedHooks\(\)' \
  'return \.failed'; do
  rg -q "$invariant" "$AGENT_CONNECTIONS" \
    || fail "Settings bulk-disconnect ownership or low-cardinality outcome invariant missing: $invariant"
done
if rg -n 'localizedDescription|configPath|String\(describing:|String\(reflecting:' \
    "$AGENT_CONNECTIONS"; then
  fail "Settings bulk-disconnect worker must not return paths or raw errors to presentation"
fi
for invariant in \
  '@State private var localAgentConnectionsOperation =' \
  'connectionsOperation: \$localAgentConnectionsOperation' \
  'connectionsOperation\.beginAgentMutation\(' \
  'connectionsOperation\.beginDisconnectAll\('; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Settings must enforce one cross-pane local-Agent mutation owner: $invariant"
done
for regression in \
  'testAgentMutationOwnsTheSurfaceUntilItsExactCompletion' \
  'testDisconnectAllExcludesEveryAgentMutationAcrossPaneChanges' \
  'testLateOrWrongKindCompletionCannotReleaseAnotherMutation' \
  'testBeginningANewMutationClearsStaleMaintenanceFeedback'; do
  rg -q "$regression" "$AGENT_CONNECTIONS_TESTS" \
    || fail "Settings Agent mutation-ownership regression missing: $regression"
done

for file in \
  "$KIMI_AGENT" \
  "$KIMI_EVENT" \
  "$KIMI_TOML_EDITOR" \
  "$KIMI_CONNECTOR_TESTS" \
  "$KIMI_INSTALLER_TESTS" \
  "$KIMI_NOTES" \
  "$KIMI_LOGO" \
  "$KIMI_LOGO_LICENSE"; do
  test -s "$file" || fail "Kimi Code Preview security artifact missing: $file"
done
[[ "$(shasum -a 256 "$KIMI_LOGO" | awk '{print $1}')" == \
  "60685e25b2db869030290485a35eed8ca77e535d2c6b7731374df49edbfa98c8" ]] \
  || fail "Kimi Code logo must remain the exact pinned upstream SVG"
[[ "$(shasum -a 256 "$KIMI_LOGO_LICENSE" | awk '{print $1}')" == \
  "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" ]] \
  || fail "Kimi Code Apache-2.0 brand notice must match the reviewed schema-v3 asset"
for invariant in \
  '@moonshot-ai/kimi-code@0\.38\.0' \
  'releaseStage: \.preview' \
  'configPath: "~/\.kimi-code/config\.toml"' \
  'permissionRequests: \.observeOnly' \
  '"TurnStarted"' \
  '"PermissionRequest", "PermissionResult"'; do
  rg -q "$invariant" "$KIMI_AGENT" \
    || fail "Kimi Code Preview contract invariant missing: $invariant"
done
if rg -q '"UserPromptSubmit"' "$KIMI_AGENT"; then
  fail "Kimi status observation must not enter the blockable UserPromptSubmit path"
fi
if rg -n 'public let (prompt|toolName|toolInput|display|decision|feedback|errorMessage|sessionTitle)' \
  "$KIMI_EVENT"; then
  fail "Kimi Preview must not model vendor-authored content fields"
fi
for invariant in \
  'import TOML' \
  'managedBlockRanges' \
  'ownsLeadingNewline' \
  'Unknown Kimi Hook fields' \
  'try parsedConfig\(from: updated'; do
  rg -q "$invariant" "$KIMI_TOML_EDITOR" \
    || fail "Lossless TOML safety invariant missing: $invariant"
done
for regression in \
  'testInstallAndUninstallPreserveComplexUserTOMLByteForByte' \
  'testNoTrailingNewlineRoundTripIsExactlyLosslessAndIdempotent' \
  'testMarkerLookingTextInsideMultilineStringsIsNeverEdited' \
  'testMalformedIncompleteAndUnwrappedManagedEntriesFailClosed' \
  'testUnknownFieldInsideManagedBlockFailsClosed' \
  'testBulkRemovalComposesJSONAndTOMLWithoutReformattingUserConfig' \
  'testMalformedTOMLStopsDisconnectAllBeforeAnyJSONWrite' \
  'testTOMLWriteFailureRollsBackEarlierJSONByteForByte' \
  'testKimiCodePreviewManagedCommandDeliversObserveOnlyWaitingEvent'; do
  rg -q "$regression" \
    "$KIMI_CONNECTOR_TESTS" \
    "$KIMI_INSTALLER_TESTS" \
    "$HOOK_MAINTENANCE_TESTS" \
    "$LOCAL_ACTION_TESTS" \
    || fail "Kimi Code Preview regression missing: $regression"
done

for file in \
  "$COPILOT_AGENT" \
  "$COPILOT_EVENT" \
  "$COPILOT_CONNECTOR_TESTS" \
  "$COPILOT_INSTALLER_TESTS" \
  "$COPILOT_NOTES" \
  "$COPILOT_LOGO"; do
  test -s "$file" || fail "Copilot CLI Preview security artifact missing: $file"
done
for invariant in \
  '@github/copilot@1\.0\.80' \
  'releaseStage: \.preview' \
  'configPath: "~/\.copilot/hooks/dev-island\.json"' \
  'permissionRequests: \.observeOnly' \
  'questionRequests: \.observeOnly'; do
  rg -q "$invariant" "$COPILOT_AGENT" \
    || fail "Copilot CLI Preview contract invariant missing: $invariant"
done
if rg -n 'public let (message|title|prompt|transcriptPath|errorMessage|stack|toolArgs)' \
  "$COPILOT_EVENT"; then
  fail "Copilot Preview must not model vendor-authored content fields"
fi
for regression in \
  'testDecodesPinnedCompatiblePayloadWithoutModelingSensitiveContent' \
  'testInformationalNotificationsDoNotInventAttention' \
  'testInstallPreservesUserFieldsAndHooksAndIsIdempotent' \
  'testInvalidJSONAndWrongVersionRemainByteForByteUnchanged' \
  'testCopilotPreviewManagedCommandDeliversPrivacyMinimalWaitingEvent'; do
  rg -q "$regression" "$COPILOT_CONNECTOR_TESTS" "$COPILOT_INSTALLER_TESTS" "$LOCAL_ACTION_TESTS" \
    || fail "Copilot CLI Preview regression missing: $regression"
done

for file in \
  "$QWEN_AGENT" \
  "$QWEN_PERMISSION" \
  "$QWEN_INSTALLER_TESTS" \
  "$QWEN_PERMISSION_TESTS" \
  "$QWEN_NOTES" \
  "$QWEN_LOGO" \
  "$QWEN_LOGO_LICENSE"; do
  test -s "$file" || fail "Qwen Code Preview security artifact missing: $file"
done
[[ "$(shasum -a 256 "$QWEN_LOGO" | awk '{print $1}')" == \
  "7c7b987b0dba797addc54f59c16c1a74085b68c837f863f312c2521a4e165a03" ]] \
  || fail "Qwen Code adapted logo must match the reviewed schema-v3 asset"
[[ "$(shasum -a 256 "$QWEN_LOGO_LICENSE" | awk '{print $1}')" == \
  "fa668918263f754d5339c3fd84fb65123525e48db72cfbbb3fff250d3775afeb" ]] \
  || fail "Qwen Code Apache-2.0 brand notice must match the reviewed schema-v3 asset"
for invariant in \
  '@qwen-code/qwen-code@0\.22\.0' \
  'releaseStage: \.preview' \
  'actionHookTimeoutUnit: \.milliseconds' \
  'actionHookEvents: \["PermissionRequest"\]'; do
  rg -q "$invariant" "$QWEN_AGENT" \
    || fail "Qwen Code Preview contract invariant missing: $invariant"
done
for regression in \
  'testInstallUsesQwenMillisecondTimeoutAndPreservesOtherSettings' \
  'testWrongLegacyTimeoutIsReportedAsUpdateRequired' \
  'testInvalidExistingConfigRemainsByteForByteUnchanged' \
  'testResponseMatchesPinnedStructuredDecisionContract'; do
  rg -q "$regression" "$QWEN_INSTALLER_TESTS" "$QWEN_PERMISSION_TESTS" \
    || fail "Qwen Code Preview regression missing: $regression"
done

for file in \
  "$SESSION_JUMP_CONTEXT" \
  "$TMUX_NAVIGATOR" \
  "$TMUX_STABILITY_FIXTURE" \
  "$BOUNDED_CHILD_PROCESS" \
  "$SOURCE_APP_RESOLVER" \
  "$SOURCE_APP_TESTS"; do
  test -s "$file" || fail "Safe terminal jump artifact missing: $file"
done
for header in \
  X-Dev-Island-Terminal-Bundle \
  X-Dev-Island-Terminal-Program \
  X-Dev-Island-TTY \
  X-Dev-Island-Tmux \
  X-Dev-Island-Tmux-Pane; do
  rg -q "$header" "$LOCAL_HOOKS_INSTALLER" "$LOCAL_HOOK_SERVER" \
    || fail "Terminal jump header is not captured and consumed: $header"
done
for invariant in \
  'safeBundleIdentifier' \
  'safeTmuxSocket' \
  'safeTmuxPane' \
  'BoundedChildProcess\.run' \
  'maximumOutputBytes = 4 \* 1_024' \
  'validatedExecutable' \
  'POSIX_SPAWN_SETPGROUP' \
  'signalProcessGroup\(spawned\.pid, signal: SIGKILL\)' \
  'preferredTerminalBundleIdentifier'; do
  rg -q "$invariant" "$SESSION_JUMP_CONTEXT" "$TMUX_NAVIGATOR" "$BOUNDED_CHILD_PROCESS" "$SOURCE_APP_RESOLVER" \
    || fail "Terminal jump safety invariant missing: $invariant"
done
if rg -n '/bin/(sh|zsh)|-c' "$TMUX_NAVIGATOR"; then
  fail "tmux jump must never interpret captured metadata through a shell"
fi
if rg -n 'Process\(|waitUntilExit|readDataToEndOfFile' "$TMUX_NAVIGATOR"; then
  fail "tmux jump must use the bounded POSIX child runner"
fi
rg -q 'static let defaultTimeout: TimeInterval = 2\.0' "$TMUX_NAVIGATOR" \
  || fail "Production tmux navigation timeout must stay bounded at two seconds"
rg -q 'timeout: 10' "$SOURCE_APP_TESTS" \
  || fail "Ephemeral tmux command test must isolate host startup jitter"
for regression in \
  'testSessionJumpContextRejectsControlCharactersAndPartialTmuxTargets' \
  'testTmuxNavigationUsesValidatedPaneAndWindowWithoutAShell' \
  'testTmuxNavigatorRunsTheTwoExpectedArgumentOnlyCommands' \
  'testTmuxProductionTimeoutRemainsTwoSeconds' \
  'testTmuxNavigatorKillsBackgroundDescendantAfterLeaderExits' \
  'testTmuxNavigatorKillsTermIgnoringChildAtDeadline' \
  'testTmuxNavigatorRejectsUnboundedOutputWithoutDeadlock' \
  'testTmuxNavigatorNeverLaunchesWritableExecutable' \
  'testCapturedTerminalBeatsGenericCodexDesktopFallback'; do
  rg -q "$regression" "$SOURCE_APP_TESTS" \
    || fail "Terminal jump regression missing: $regression"
done
for invariant in \
  'ITERATIONS=20' \
  'testTmuxNavigatorKillsBackgroundDescendantAfterLeaderExits' \
  '--scratch-path "$TEST_SCRATCH"' \
  '--skip-build --filter' \
  'Test Case .* failed|error:' \
  'tmux descendant cleanup stability: PASS'; do
  rg -Fq -- "$invariant" "$TMUX_STABILITY_FIXTURE" \
    || fail "tmux process stability fixture missing: $invariant"
done
rg -Fq './scripts/ci/verify-tmux-process-stability.sh' "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative tests must repeat tmux descendant cleanup after the full suite"
rg -q 'testManagedHookCommandCarriesValidatedTerminalContextEndToEnd' "$LOCAL_ACTION_TESTS" \
  || fail "Managed Hook command must prove terminal context transport end to end"
rg -q 'testEphemeralTerminalJumpContextIsNeverPersisted' "$SQLITE_MAINTENANCE_TESTS" \
  || fail "Terminal/tmux jump metadata must remain absent from SQLite history"

for file in \
  "$USAGE_MODEL" \
  "$USAGE_READER" \
  "$USAGE_CONTROLLER" \
  "$USAGE_TESTS"; do
  test -s "$file" || fail "Local usage privacy artifact missing: $file"
done
for invariant in \
  'usedPercent\.isFinite' \
  'maximumTailBytes' \
  'maximumCandidateFiles' \
  'maximumEnumeratedEntries' \
  'O_NOFOLLOW' \
  'Darwin\.pread\(' \
  'information\.st_uid == geteuid\(\)' \
  'information\.st_mode & 0o022' \
  'insertCandidate\(' \
  'payload\.type == "token_count"' \
  'Non-usage content fields are never modeled' \
  'devIsland\.usage\.localInsightsEnabled' \
  'private var isEnabled = false'; do
  rg -q "$invariant" "$USAGE_MODEL" "$USAGE_READER" "$USAGE_SETTINGS" \
    || fail "Local usage privacy invariant missing: $invariant"
done
if rg -n 'URLSession|KeychainStore|SQLiteStore|IslandLogger' \
  "$USAGE_MODEL" "$USAGE_READER" "$USAGE_CONTROLLER"; then
  fail "Local usage insight must remain on-demand, in-memory, credential-free, and unlogged"
fi
if rg -n 'readToEnd|seekToEnd|Data\(contentsOf:' "$USAGE_READER"; then
  fail "Local usage insight must use the descriptor-backed exact tail reader"
fi
for regression in \
  'testReadsLatestProviderAuthoredWindowsWithoutReturningContent' \
  'testMalformedNewestRecordFallsBackWithoutInventingLimits' \
  'testReaderUsesBoundedSuffixAndSnapshotStalenessIsExplicit' \
  'testMissingLocalActivityReturnsNil' \
  'testConcurrentGrowthCannotEscapeMeasuredTailBoundary' \
  'testEnumerationPressureFailsAtHardEntryBudget' \
  'testWritableRolloutCandidateFailsClosedBeforeReading'; do
  rg -q "$regression" "$USAGE_TESTS" \
    || fail "Local usage regression missing: $regression"
done

for file in "$CLAUDE_PLAN_HOOK" "$CLAUDE_PLAN_TESTS" "$LOCAL_ACTION_TESTS"; do
  test -s "$file" || fail "Claude plan-review security artifact missing: $file"
done

for file in \
  "$ACTION_REQUEST_MODEL" \
  "$TASK_STORE" \
  "$TASK_STORE_ACTION_TESTS" \
  "$CLAUDE_QUESTION_HOOK" \
  "$CLAUDE_QUESTION_TESTS"; do
  test -s "$file" || fail "Local action resource-bound artifact missing: $file"
done
for invariant in \
  'public static let maximumTimeout: TimeInterval = 120' \
  'safeTimeout = timeout\.isFinite' \
  'min\(max\(1, timeout\), Self\.maximumTimeout\)' \
  'maximumUTF8Bytes: Int' \
  'byteCount \+ fragmentBytes <= maximumUTF8Bytes'; do
  rg -q "$invariant" "$ACTION_REQUEST_MODEL" \
    || fail "Local action text/lifetime bound missing: $invariant"
done
for invariant in \
  'static let maximumPendingActionRequests = 32' \
  'static let maximumPendingActionRequestsPerSession = 4' \
  'pendingActionRequests\.count < Self\.maximumPendingActionRequests' \
  'requestsForSession < Self\.maximumPendingActionRequestsPerSession'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "Local action queue resource bound missing: $invariant"
done
for regression in \
  'testActionRequestBoundsVisibleTextAndLifetime' \
  'testGlobalQueueOverflowFailsNeutralWithoutRetainingContinuation' \
  'testPerSessionQueueOverflowRecoversCapacityAfterResolution' \
  'testBoundsQuestionHeaderOptionAndDescriptionByUTF8Bytes'; do
  rg -q "$regression" "$TASK_STORE_ACTION_TESTS" "$CLAUDE_QUESTION_TESTS" \
    || fail "Local action resource-bound regression missing: $regression"
done
for invariant in \
  'await eventDelivery.deliverBeforeAction(' \
  'actionRequest.source == descriptor.source' \
  'decodedEvent?.sessionId == actionRequest.sessionId'; do
  rg -Fq "$invariant" "$LOCAL_HOOK_SERVER" \
    || fail "Synchronous local-action ordering/identity invariant missing: $invariant"
done
rg -Fq 'await self?.ingestLocalAgentEvent(source: source, event: event)' "$TASK_STORE" \
  || fail "TaskStore must await same-request lifecycle ingestion before action queuing"
if rg -U -n \
  '\) \{ \[weak self\] source, event in\n[[:space:]]+Task \{ @MainActor' \
  "$TASK_STORE"; then
  fail "Local action lifecycle delivery must not regress to an unawaited MainActor Task"
fi
for regression in \
  'testSynchronousActionCommitsWaitingEventBeforeQueueAndReturnsDecisionEndToEnd' \
  'testPassiveLifecycleResponseDoesNotWaitForEventPersistence' \
  'testRouteRejectsMismatchedActionIdentityBeforeCallback'; do
  rg -q "$regression" "$LOCAL_ACTION_TESTS" \
    || fail "Synchronous local-action ordering regression missing: $regression"
done
for invariant in \
  'actor LocalHookEventDelivery' \
  'static let maximumQueuedEventsPerSource = 256' \
  'state.queue.lastIndex(where:' \
  'state.queue.count < maximumQueuedEventsPerSource' \
  'await eventDelivery.enqueuePassive(' \
  'await eventDelivery.deliverBeforeAction('; do
  rg -Fq "$invariant" "$LOCAL_HOOK_SERVER" \
    || fail "Bounded local lifecycle delivery invariant missing: $invariant"
done
for regression in \
  'testActionRequestCannotOvertakeEarlierPassiveLifecycleHTTPEvent' \
  'testDeliveryQueueSerializesAndCoalescesPendingPassiveSessionState' \
  'testDeliveryQueueKeepsAgentSourcesIndependent' \
  'testDeliveryQueueBoundsPassiveFloodAndPreservesActionBarrier' \
  'testDeliveryQueueFailsNeutralWhenCapacityContainsOnlyActions' \
  'testDeliveryQueueRejectsQueuedWorkAfterListenerEpochExpires'; do
  rg -q "$regression" "$LOCAL_ACTION_TESTS" \
    || fail "Bounded local lifecycle delivery regression missing: $regression"
done

for file in \
  "$LOCAL_AGENT_EVENT" \
  "$LOCAL_SESSION_TABLE" \
  "$LOCAL_AGENT_CONNECTOR" \
  "$LOCAL_AGENT_FRAMEWORK_TESTS" \
  "$SQLITE_STORE" \
  "$SQLITE_FILE_BOUNDARY" \
  "$SQLITE_MAINTENANCE_TESTS"; do
  test -s "$file" || fail "Local session/history resource-bound artifact missing: $file"
done
for invariant in \
  'static let privateDirectoryPermissions = 0o700' \
  'static let privateFilePermissions = 0o600' \
  'O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK' \
  'O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK' \
  'Darwin.openat(' \
  'Darwin.fstatat(' \
  'directoryAnchor: OpenAnchor' \
  'databaseAnchor: OpenAnchor' \
  'information.st_mode & S_IFMT == S_IFREG' \
  'information.st_uid == geteuid()' \
  'information.st_nlink == 1' \
  'FileIdentity(information) == expected' \
  'sidecarSuffixes = ["-wal", "-shm", "-journal"]'; do
  rg -Fq "$invariant" "$SQLITE_FILE_BOUNDARY" \
    || fail "SQLite file ownership boundary missing: $invariant"
done
for invariant in \
  'SQLiteFileBoundary.prepare(at: requestedURL)' \
  'SQLiteFileBoundary.verify(prepared)' \
  'SQLiteFileBoundary.secureExistingSidecars(for: prepared)' \
  'fileBoundary = prepared' \
  'performVerifiedWrite' \
  'performVerifiedRead' \
  'terminalBoundaryFailure' \
  'disablePersistenceIfBoundaryFailure'; do
  rg -Fq "$invariant" "$SQLITE_STORE" \
    || fail "SQLite store must apply its file boundary: $invariant"
done
for invariant in \
  'maximumSessionIDBytes = 256' \
  'maximumGenerationIDBytes = 256' \
  'maximumCWDBytes = 4_096' \
  'maximumMessageBytes = 4_096' \
  'value\.utf8\.count <= maximumUTF8Bytes' \
  'CharacterSet\.controlCharacters\.contains'; do
  rg -q "$invariant" "$LOCAL_AGENT_EVENT" \
    || fail "Local Hook field resource bound missing: $invariant"
done
for invariant in \
  'static let maximumSessions = 128' \
  'enforceCapacity\(\)' \
  'lhs\.status == \.waiting' \
  'pruneBookkeeping\(\)'; do
  rg -q "$invariant" "$LOCAL_SESSION_TABLE" "$LOCAL_AGENT_CONNECTOR" \
    || fail "Local session-table resource bound missing: $invariant"
done
for invariant in \
  'static let maximumStoredTasks = 5_000' \
  'static let maximumStoredProgressEvents = 20_000' \
  'static let maximumStoredSourceBytes = 64' \
  'static let maximumStoredTaskIDBytes = 256' \
  'static let maximumStoredTitleBytes = 1_024' \
  'static let maximumStoredPhaseBytes = 1_024' \
  'static let maximumStoredTaskURLBytes = 16_384' \
  'static let maximumStoredWaitingMessageBytes = 16_384' \
  'static let maximumStoredProgressTypeBytes = 256' \
  'static let maximumStoredProgressMessageBytes = 16_384' \
  'try sanitizeExistingRecords\(in: connection\)' \
  'Expression<Bool>\(literal: Self\.boundedTaskRowSQLPredicate\)' \
  'length\(CAST\("title" AS BLOB\)\)' \
  'try enforceRetention\(in: connection\)' \
  'WHERE NOT EXISTS'; do
  rg -q "$invariant" "$SQLITE_STORE" \
    || fail "SQLite history resource bound missing: $invariant"
done
for invariant in \
  'LIMIT -1 OFFSET \(taskRetentionLimit)' \
  'LIMIT -1 OFFSET \(progressRetentionLimit)'; do
  rg -Fq "$invariant" "$SQLITE_STORE" \
    || fail "SQLite history fixed retention query missing: $invariant"
done
for regression in \
  'testOversizedAndControlSessionIDsDropAtTheSharedBoundary' \
  'testLocalEventBoundsPathGenerationPhaseMessageAndDerivedTitle' \
  'testSessionCapacityPrefersWaitingAndRejectsNewestWaitingOverflow' \
  'testRetentionKeepsNewestTasksAndDeletesOrphanedProgress' \
  'testProgressRetentionIsFiniteAndDeterministic' \
  'testOpeningExistingDatabaseAppliesCurrentRetentionLimits' \
  'testWriteRejectsOversizedRowsWithoutPartialBatchOrProgressMutation' \
  'testOpeningCurrentDatabasePurgesOversizedRowsAndOrphanedProgress' \
  'testHistoryReadFiltersOversizedExternalRowModifiedAfterOpen' \
  'testDatabaseLocationTightensDirectoryAndFileToOwnerOnly' \
  'testOpenRejectsSymlinkDatabaseWithoutTouchingTarget' \
  'testOpenRejectsSymlinkDatabaseDirectoryWithoutCreatingTargetFile' \
  'testOpenRejectsNonRegularDatabaseEntry' \
  'testOpenRejectsHardLinkedDatabaseWithoutTouchingPeer' \
  'testOpenRejectsSymlinkSQLiteSidecarBeforeSchemaMutation' \
  'testPreparedBoundaryRejectsReplacedDirectoryEvenWhenDatabaseInodeReturns' \
  'testSidecarHardeningDoesNotTouchAReplacedDirectoryEntry' \
  'testRuntimeDirectoryReplacementRejectsWriteWhenDatabaseInodeReturns' \
  'testRuntimeDirectoryReplacementRollsBackClearHistory' \
  'testRuntimeDirectoryReplacementRejectsMaterializedHistory' \
  'testRuntimeSidecarSymlinkIsRejectedBeforeWrite'; do
  rg -q "$regression" "$LOCAL_AGENT_FRAMEWORK_TESTS" "$SQLITE_MAINTENANCE_TESTS" \
    || fail "Local session/history resource-bound regression missing: $regression"
done

for invariant in \
  'data\.count <= AgentPlanReview\.maximumInputBytes' \
  'originalInput\["plan"\] as\? String == review\.markdown' \
  'output\["updatedInput"\] = originalInput' \
  'permissionDecisionReason'; do
  rg -q "$invariant" "$CLAUDE_PLAN_HOOK" \
    || fail "Claude plan-review trust invariant missing: $invariant"
done
for regression in \
  'testApprovalEchoesCompleteOriginalInput' \
  'testInvalidOversizedAndMismatchedValuesFailNeutral' \
  'testExitPlanModeHTTPRoundTripPreservesInjectedInput'; do
  rg -q "$regression" "$CLAUDE_PLAN_TESTS" "$LOCAL_ACTION_TESTS" \
    || fail "Claude plan-review regression missing: $regression"
done

test -s "$KEYBOARD_CONTRACT_TESTS" \
  || fail "Window-level action-request keyboard contract tests are missing"
for regression in \
  'testPrimaryPermissionCommandReturnAllowsOnce' \
  'testPrimaryPermissionCommandDDeniesButEscapeNeverDecides' \
  'testSecondaryPermissionDoesNotOwnPanelShortcuts' \
  'testPlanReviewRoutesApproveRejectAndContinueToDistinctCallbacks' \
  'testQuestionCannotCommandReturnWithoutSelectionAndCanContinueInClaude'; do
  rg -q "$regression" "$KEYBOARD_CONTRACT_TESTS" \
    || fail "Action-request keyboard regression missing: $regression"
done
if rg -n 'keyboardShortcut\(\.cancelAction\)' \
  IslandAppLib/Views/NotchPanel/ActionRequestSurface.swift; then
  fail "Escape must collapse Dev Island and must never decide an Agent request"
fi

for file in \
  "$CODEX_TRUST_PROBE" \
  "$CODEX_TRUST_TESTS" \
  "$CODEX_TRUST_STABILITY_FIXTURE" \
  "$BOUNDED_STDIO_CHILD_PROCESS" \
  "$LOCAL_HOOK_DIAGNOSTICS" \
  "$LOCAL_HOOK_DIAGNOSTIC_TESTS"; do
  test -s "$file" || fail "Codex Hook trust artifact missing: $file"
done
test -x "$CODEX_TRUST_STABILITY_FIXTURE" \
  || fail "Codex Hook trust process stability fixture must be executable"
for invariant in \
  'codexBundleIdentifier = "com\.openai\.codex"' \
  'openAITeamIdentifier = "2DC432GLL2"' \
  'SecStaticCodeCheckValidity' \
  'BoundedStdioChildProcess\.requestResponse' \
  'arguments: \["app-server", "--stdio"\]' \
  'currentDirectoryURL: cwd' \
  'outputLimit: Self\.responseLimitBytes' \
  'responseLimitBytes = 2 \* 1_024 \* 1_024' \
  'defaultTimeout: TimeInterval = 3' \
  'timeout <= 10' \
  'collector\.erase\(\)' \
  'response\.resetBytes' \
  'hook\.handlerType == "command"' \
  'hook\.eventName == expectedEvent' \
  'hook\.command == expectedCommand' \
  'hook\.sourcePath' \
  'hook\.enabled && \(hook\.trustStatus == "trusted" \|\| hook\.trustStatus == "managed"\)'; do
  rg -q "$invariant" "$CODEX_TRUST_PROBE" \
    || fail "Codex Hook trust invariant missing: $invariant"
done
for invariant in \
  'POSIX_SPAWN_SETPGROUP' \
  'F_DUPFD_CLOEXEC' \
  'F_SETNOSIGPIPE' \
  'O_NONBLOCK' \
  'DispatchTime\.now\(\)\.uptimeNanoseconds' \
  'POLLIN' \
  'POLLOUT' \
  'STDERR_FILENO' \
  'SIGTERM' \
  'SIGKILL' \
  'waitpid' \
  'signalProcessGroup'; do
  rg -q "$invariant" "$BOUNDED_STDIO_CHILD_PROCESS" \
    || fail "Codex stdio process boundary invariant missing: $invariant"
done
if rg -n 'Process\(\)|Thread\s*\{|DispatchSemaphore' "$CODEX_TRUST_PROBE"; then
  fail "Codex trust verification must not depend on Process, helper threads, or run-loop callbacks"
fi
if rg -n '/usr/local|/opt/homebrew|which codex|executableURL = URL\(fileURLWithPath:.*codex' \
  "$CODEX_TRUST_PROBE"; then
  fail "Codex trust verification must not execute PATH or package-manager shims"
fi
if rg -n 'IslandLogger|Logger\(|os_log|NSLog|print\(' "$CODEX_TRUST_PROBE"; then
  fail "Codex trust verification must never log App Server output"
fi
for regression in \
  'testExactEnabledTrustedDefinitionsVerifyWhileUnrelatedHooksAreIgnored' \
  'testEveryExpectedDefinitionMustBeEnabledAndTrustedOrManaged' \
  'testMissingWrongCommandWrongPathAndDiscoveryErrorsFailClosed' \
  'testMalformedWrongIDAndOversizedResponsesFailClosed' \
  'testShortLivedProcessProbeAcceptsAValidResponse' \
  'testSilentProcessIsTerminatedAtTheBoundedTimeout' \
  'testImmediateExitFailsWithoutWaitingForTheFullTimeout' \
  'testClosedChildStdinCannotTerminateTheProbeWithSIGPIPE' \
  'testTimeoutTerminatesTheCompleteProcessGroup' \
  'testOversizedOutputFailsClosedAndTerminatesTheCompleteProcessGroup'; do
  rg -q "$regression" "$CODEX_TRUST_TESTS" \
    || fail "Codex Hook trust regression missing: $regression"
done
for invariant in \
  'processFixtureSchedulingBudget: TimeInterval = 5' \
  'timeout: processFixtureSchedulingBudget' \
  'FixtureError.pidNotPublished'; do
  rg -Fq "$invariant" "$CODEX_TRUST_TESTS" \
    || fail "Codex process-fixture scheduling isolation missing: $invariant"
done
rg -Fq 'static let defaultTimeout: TimeInterval = 3' "$CODEX_TRUST_PROBE" \
  || fail "Codex production trust-probe timeout must remain three seconds"
for invariant in \
  'ITERATIONS=5' \
  "FILTER='CodexHookTrustProbeTests'" \
  '--scratch-path "$TEST_SCRATCH"' \
  '--skip-build --filter' \
  'Test Case .* failed|error:' \
  'Codex Hook trust process stability: PASS'; do
  rg -Fq -- "$invariant" "$CODEX_TRUST_STABILITY_FIXTURE" \
    || fail "Codex Hook trust process stability fixture missing: $invariant"
done
rg -Fq './scripts/ci/verify-codex-hook-trust-process-stability.sh' "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative tests must repeat the Codex Hook trust process boundary after the full suite"
rg -q 'snapshotResolvingVendorActivation' "$LOCAL_HOOK_DIAGNOSTICS" \
  || fail "Codex vendor trust must be resolved through the shared diagnostic snapshot"
rg -q 'testVerifiedVendorActivationPromotesOnlyItsConfiguredSource' \
  "$LOCAL_HOOK_DIAGNOSTIC_TESTS" \
  || fail "Codex trust promotion regression is missing"

for file in \
  "$LOCAL_LIVE_READINESS" \
  "$BOUNDED_CHILD_PROCESS" \
  "$LOCAL_LIVE_READINESS_TESTS" \
  "$LOCAL_VERSION_STABILITY_FIXTURE" \
  "$LOCAL_HOOK_SERVER" \
  "$LOCAL_HOOK_HEALTH_TESTS"; do
  test -s "$file" || fail "Local live-readiness artifact missing: $file"
done
for invariant in \
  'verifiedClaudeCodeVersion = "2\.1\.197"' \
  'verifiedCodexVersion = "0\.149\.0-alpha\.4\.3"' \
  'case checkFailed = "check-failed"' \
  'outputLimitBytes = 4 \* 1_024' \
  'defaultTimeout: TimeInterval = 2' \
  'arguments: \["--version"\]' \
  'posix_spawn\(' \
  'POSIX_SPAWN_SETPGROUP' \
  'Darwin\.waitpid\(' \
  'signalProcessGroup\(spawned\.pid, signal: SIGKILL\)' \
  'data\.resetBytes\(in: data\.indices\)' \
  'O_NONBLOCK' \
  'CodexHookTrustProbe\.verifiedCodexExecutable\(\)' \
  'connectionProxyDictionary = \[:\]' \
  'httpShouldSetCookies = false' \
  'challengeHeader = "X-Dev-Island-Readiness-Challenge"' \
  'originName = HTTPField\.Name\("Origin"\)'; do
  rg -q "$invariant" "$LOCAL_LIVE_READINESS" "$BOUNDED_CHILD_PROCESS" "$LOCAL_HOOK_SERVER" \
    || fail "Local live-readiness security invariant missing: $invariant"
done
for invariant in \
  'timeout: 5' \
  'XCTAssertLessThan\(Date\(\)\.timeIntervalSince\(started\), 15\)' \
  'XCTAssertLessThan\(Date\(\)\.timeIntervalSince\(started\), 5\.5\)' \
  'newly spawned fixture receives CPU within 1\.5 seconds' \
  'Fast version probe failed at iteration'; do
  rg -q "$invariant" "$LOCAL_LIVE_READINESS_TESTS" \
    || fail "Scheduler-tolerant fast version regression missing: $invariant"
done
for invariant in \
  'ITERATIONS=20' \
  'CHILD_PROCESSES_PER_ITERATION=12' \
  '--scratch-path "$TEST_SCRATCH"' \
  '--skip-build --filter' \
  'Test Case .* failed|error:' \
  'Local version probe stability: PASS'; do
  rg -Fq -- "$invariant" "$LOCAL_VERSION_STABILITY_FIXTURE" \
    || fail "Local version probe stability fixture missing: $invariant"
done
rg -Fq './scripts/ci/verify-local-version-probe-stability.sh' "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative tests must repeat the local version probe boundary after the full suite"
for file in "$HERMETIC_LOCAL_LISTENER" "$HERMETIC_LOCAL_LISTENER_FIXTURE"; do
  test -s "$file" || fail "Hermetic local listener artifact missing: $file"
done
for invariant in \
  'LocalHookAuthorizationStore.makeEphemeralAuthorization()' \
  'maxConsecutiveFailures: 1' \
  'authorization: authorization' \
  'suppressFrameworkLogs: true' \
  'server.start(agents: [], onEvent:' \
  'await server.stop()' \
  'if await probe.probe() == .unavailable { return .verified }'; do
  rg -Fq "$invariant" "$HERMETIC_LOCAL_LISTENER" \
    || fail "Hermetic local listener isolation invariant missing: $invariant"
done
if rg -n 'TaskStore\(|SQLiteStore\(|KeychainStore\.|\.rotate\(' "$HERMETIC_LOCAL_LISTENER"; then
  fail "Hermetic local listener must not enter TaskStore, SQLite, Keychain, or persistent authorization"
fi
for invariant in \
  'ITERATIONS=10' \
  'local-hermetic-listener-check' \
  '[[ ! -s "$STDERR_LOG" ]]' \
  'authorization=memory-only' \
  'agent-routes=disabled' \
  'Hermetic local listener: PASS'; do
  rg -Fq "$invariant" "$HERMETIC_LOCAL_LISTENER_FIXTURE" \
    || fail "Hermetic local listener stability fixture missing: $invariant"
done
rg -Fq './scripts/ci/verify-hermetic-local-listener.sh' "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative tests must run the hermetic local listener stability boundary"
rg -Fq 'set -euo pipefail' "$CI_WORKFLOW" \
  || fail "PR test logging must preserve early full-suite failures"
if rg -n 'IslandLogger|Logger\(|os_log|NSLog|print\(' "$LOCAL_LIVE_READINESS"; then
  fail "Local live-readiness must never log raw CLI or listener output"
fi
for regression in \
  'testPinnedClaudeAndCodexVersionOutputsVerifyExactly' \
  'testVersionDriftAndMalformedOutputRequireReview' \
  'testOversizedCompatibilityOutputIsAFailedCheck' \
  'testProductionVersionProbeTimeoutRemainsTwoSeconds' \
  'testBoundedVersionProcessVerifiesExactOutput' \
  'testRepeatedFastVersionProcessesDoNotLoseTerminationOrOutput' \
  'testHangingVersionProcessIsKilledAndReportsFailedCheck' \
  'testTermIgnoringVersionProcessIsKilledAtBoundedDeadline' \
  'testVersionProcessRequiresZeroExitEvenWithExactOutput' \
  'testVersionProcessRejectsOversizedOutputWithoutDeadlock' \
  'testTransientExecutionFailuresNeverClaimCompatibilityReview' \
  'testSnapshotRequiresListenerCLIHooksAndVendorActivation' \
  'testFullyVerifiedSnapshotIsReadyForBothLiveSessions' \
  'testStoppedAppForcesReadyAgentCountToZero' \
  'testHermeticListenerHarnessVerifiesChallengeAndCleanShutdown' \
  'testEphemeralListenerAuthorizationIsRandomAndMemoryOnly'; do
  rg -q "$regression" "$LOCAL_LIVE_READINESS_TESTS" \
    || fail "Local live-readiness regression missing: $regression"
done
for regression in \
  'testExternalReadinessChallengeProvesTheRunningAppListener' \
  'testExternalReadinessRejectsBrowserOrigin'; do
  rg -q "$regression" "$LOCAL_HOOK_HEALTH_TESTS" \
    || fail "Local listener external-readiness regression missing: $regression"
done
rg -q 'case "local-live-readiness"' "$MANUS_CLI" \
  || fail "The explicit local-live-readiness CLI command is missing"
rg -q 'case "local-hermetic-listener-check"' "$MANUS_CLI" \
  || fail "The explicit hermetic local listener CLI command is missing"
for invariant in \
  'authorization=memory-only' \
  'agent-routes=disabled'; do
  rg -Fq "$invariant" "$MANUS_CLI" \
    || fail "Hermetic local listener CLI output invariant missing: $invariant"
done
rg -q 'action=check-\\\(agent\.source\)-version-again' "$MANUS_CLI" \
  || fail "A transient CLI version-check failure must expose a retry action"

# Settings exposes the same probe as a quiet, explicit preflight. Preserve the
# consent and side-effect boundary: opening Settings must not run a CLI probe,
# and checking readiness must never install, remove, or rewrite Agent Hooks.
for file in \
  "$LOCAL_LIVE_READINESS_PRESENTATION" \
  "$LOCAL_LIVE_READINESS_PRESENTATION_TESTS" \
  "$VISUAL_SNAPSHOT_TESTS" \
  "$ONBOARDING_VIEW" \
  "$ONBOARDING_LAYOUT_TESTS"; do
  test -s "$file" || fail "Settings live-readiness artifact missing: $file"
done
for invariant in \
  'static let width: CGFloat = 760' \
  'static let contentHorizontalPadding: CGFloat = 32' \
  'static let editorialWidth: CGFloat = 264' \
  'static let editorialSpacing: CGFloat = 28' \
  'static let stageWidth: CGFloat = 404' \
  'spacing: OnboardingMetrics.editorialSpacing' \
  '.frame(width: OnboardingMetrics.editorialWidth)' \
  '.padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)'; do
  rg -Fq "$invariant" "$ONBOARDING_VIEW" \
    || fail "Welcome editorial geometry invariant missing: $invariant"
done
for invariant in \
  'testEditorialColumnsConsumeTheFixedWindowWithoutImplicitSlack' \
  '(OnboardingMetrics.contentHorizontalPadding * 2)' \
  '+ OnboardingMetrics.editorialWidth' \
  '+ OnboardingMetrics.editorialSpacing' \
  '+ OnboardingMetrics.stageWidth' \
  'XCTAssertEqual(occupiedWidth, OnboardingMetrics.width)'; do
  rg -Fq "$invariant" "$ONBOARDING_LAYOUT_TESTS" \
    || fail "Welcome editorial geometry regression missing: $invariant"
done
for invariant in \
  'LocalLiveReadinessCard\(' \
  'Button\(action: onCheck\)' \
  'Checks local CLI versions, managed Hooks, Codex trust, and the private listener without changing configuration\.'; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Explicit Settings live-readiness invariant missing: $invariant"
done
for invariant in \
  'struct LocalLiveReadinessCheckState' \
  'guard activeCheckID == checkID else \{ return false \}' \
  'mutating func invalidate\(\)' \
  'Live check incomplete' \
  'knownSetupActionCount == 0' \
  "Couldn't verify %@ right now\."; do
  rg -q "$invariant" "$LOCAL_LIVE_READINESS_PRESENTATION" \
    || fail "Settings readiness late-result invariant missing: $invariant"
done
if [[ "$(rg -c 'liveReadinessCheckState\.invalidate\(\)' "$SETTINGS_VIEW")" -lt 2 ]]; then
  fail "Hook and listener changes must both invalidate Settings readiness"
fi
READINESS_CHECK_BODY="$({
  sed -n \
    '/private func checkLiveReadiness()/,/private func disconnectAllLocalAgents()/p' \
    "$SETTINGS_VIEW"
} || true)"
for invariant in \
  'Task\.detached\(priority: \.userInitiated\)' \
  'LocalLiveReadinessProbe\(\)\.snapshot\(\)'; do
  printf '%s\n' "$READINESS_CHECK_BODY" | rg -q "$invariant" \
    || fail "Settings readiness must stay explicit and off the MainActor: $invariant"
done
if printf '%s\n' "$READINESS_CHECK_BODY" | rg -n \
  'LocalHooksInstaller|LocalAgentHookMaintenance|\.install\(|\.uninstall\(|write\('; then
  fail "Settings readiness check must remain read-only and must not modify Agent configuration"
fi
if rg -n \
  'onAppear[^{]*\{[[:space:]]*checkLiveReadiness\(|\.task[^{]*\{[[:space:]]*checkLiveReadiness\(' \
  "$SETTINGS_VIEW"; then
  fail "Settings must not run live-readiness automatically on appearance"
fi
for regression in \
  'testCheckStateAcceptsOnlyItsActiveResult' \
  'testInvalidationRejectsLateResultAndAllowsFreshCheck' \
  'testIdleAndCheckingCopyExplainTheReadOnlyBoundary' \
  'testUpdateGuidanceCombinesAgentNamesWithoutRepeatingRows' \
  'testCodexTrustGuidanceNamesTheDocumentedReviewSurface' \
  'testFailedVersionCheckAsksForRetryWithoutClaimingCompatibilityReview' \
  'testFailedVersionCheckDoesNotMaskAKnownSetupAction' \
  'testSimplifiedChineseFailedVersionCheckKeepsRetryMeaning'; do
  rg -q "$regression" "$LOCAL_LIVE_READINESS_PRESENTATION_TESTS" \
    || fail "Settings live-readiness presentation regression missing: $regression"
done
rg -q 'testCaptureSettingsLiveReadinessAttention' "$VISUAL_SNAPSHOT_TESTS" \
  || fail "Settings live-readiness attention snapshot regression is missing"
rg -q 'testCaptureSettingsLiveReadinessCheckFailed' "$VISUAL_SNAPSHOT_TESTS" \
  || fail "Settings live-readiness retry snapshot regression is missing"
for invariant in \
  'case \.retry:[[:space:]]+return Palette\.stateRunning' \
  'case \.retry:[[:space:]]+return \.ring' \
  'case \.retry:[[:space:]]+return 0\.90'; do
  rg -q "$invariant" "$SETTINGS_VIEW" \
    || fail "Settings readiness retry visual invariant missing: $invariant"
done

for file in \
  "$CI_WORKFLOW" \
  "$CI_DIAGNOSTIC_GENERATOR" \
  "$CI_DIAGNOSTIC_FIXTURES" \
  "$AUTHORITATIVE_TESTS"; do
  test -s "$file" || fail "CI diagnostic security artifact missing: $file"
done
test -x "$AUTHORITATIVE_TESTS" \
  || fail "Authoritative test runner must be executable"
for invariant in \
  '.build/tests-authoritative' \
  '.build/tests-authoritative.lock' \
  'SwiftPM build root must not be a symbolic link' \
  'authoritative test scratch must not be a symbolic link' \
  'authoritative test lock must not be a symbolic link' \
  'authoritative test lock permissions must be 0600' \
  '/usr/bin/lockf -s -t 0 9' \
  'another authoritative test run is already using the shared test graph' \
  'swift test --disable-keychain' \
  '--scratch-path "$TEST_SCRATCH"' \
  '--only-use-versions-from-resolved-file' \
  './scripts/ci/verify-local-version-probe-stability.sh' \
  './scripts/ci/verify-tmux-process-stability.sh' \
  './scripts/ci/verify-codex-hook-trust-process-stability.sh' \
  './scripts/ci/verify-sleep-wake-lifecycle-stability.sh'; do
  rg -Fq -- "$invariant" "$AUTHORITATIVE_TESTS" \
    || fail "Authoritative test isolation invariant missing: $invariant"
done
rg -Fq './scripts/ci/run-authoritative-tests.sh 2>&1 \' "$CI_WORKFLOW" \
  || fail "PR CI must use the isolated authoritative test runner"
if rg -n 'swift test' "$CI_WORKFLOW" "$RELEASE_WORKFLOW"; then
  fail "Workflows must not bypass the isolated authoritative test runner"
fi
for invariant in \
  'File::NOFOLLOW | File::NONBLOCK' \
  'metadata.uid == Process.euid' \
  'metadata.nlink == 1' \
  'metadata.mode & 0o022' \
  'file.pread(metadata.size, 0)' \
  '"sourceStatus"' \
  '"schemaVersion" => 2' \
  '"brand" => "Bundled brand asset inventory"'; do
  rg -Fq "$invariant" "$CI_DIAGNOSTIC_GENERATOR" \
    || fail "Descriptor-backed CI diagnostic boundary invariant missing: $invariant"
done
if rg -n 'File\.(binread|read)\(path' "$CI_DIAGNOSTIC_GENERATOR"; then
  fail "CI diagnostics must not reopen raw logs by pathname"
fi
for invariant in \
  'persist-credentials: false' \
  'id: brand' \
  'id: diagnostics' \
  'dev-island-ci-diagnostics.XXXXXX' \
  'steps.diagnostics.outputs.artifact_path'; do
  rg -Fq "$invariant" "$CI_WORKFLOW" \
    || fail "PR CI diagnostic workflow invariant missing: $invariant"
done
for regression in \
  'brand-failure-output' \
  'symlink-test.log' \
  'oversized-test.log' \
  'hardlink-test.log' \
  'fake-swift.log' \
  'authoritative-contended.output' \
  'A contended authoritative test run executed Swift' \
  'did not fail immediately' \
  'lock-symlink' \
  'lock-directory' \
  'lock-hardlink' \
  'lock-mode' \
  'lock-content' \
  'EXPECTED_SCRATCH="$ROOT/.build/tests-authoritative"' \
  'executed an unexpected Swift command count' \
  '--skip-build --filter' \
  'sourceStatus") == "unsafe-file"' \
  'sourceStatus") == "oversized"'; do
  rg -Fq -- "$regression" "$CI_DIAGNOSTIC_FIXTURES" \
    || fail "CI diagnostic attack regression missing: $regression"
done

for test_invariant in \
  'testSafeDefaultCannotEnableCommercialState' \
  'testRawPayloadSignatureCannotCrossIntoLicenseProtocol' \
  'testSigningKeyIdentifierIsDomainBound' \
  'testAuthenticatedPayloadMustUseCanonicalJSON' \
  'testUnauthenticatedMalformedPayloadIsNotParsed'; do
  rg -q "$test_invariant" "$LICENSE_TESTS" \
    || fail "Commercial verifier attack regression missing: $test_invariant"
done

./scripts/ci/verify-localizations.sh
./scripts/ci/verify-legal-data-flows.sh
./scripts/ci/verify-ci-diagnostics.sh
./scripts/ci/verify-manus-live-acceptance-evidence.sh
./scripts/ci/verify-github-repository-controls.sh
"$BRAND_ASSET_VERIFIER" \
  --manifest scripts/assets/agent-logos/manifest.json \
  --trademark-reviews scripts/assets/agent-logos/trademark-reviews.json \
  --source-dir scripts/assets/agent-logos \
  --bundle-dir IslandApp/Resources \
  --licenses-dir scripts/licenses
./scripts/ci/verify-release-foundation.sh
./scripts/ci/verify-performance-analysis.sh
./scripts/ci/verify-signal-sounds.sh
bash ./scripts/ci/verify-log-privacy.sh

echo "Security invariants: PASS"
