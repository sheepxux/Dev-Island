#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

# Extract one Swift brace-delimited declaration from a stable declaration
# prefix. This keeps ordering checks local to the reviewed function without
# snapshotting an entire implementation or depending on exact line numbers.
extract_braced_region() {
  local file="$1"
  local declaration_prefix="$2"
  local output_mode="${3:-source}"
  awk -v declaration_prefix="$declaration_prefix" -v output_mode="$output_mode" '
    function swift_code_line(line, output, index_in_line, character, pair, triple) {
      output = ""
      index_in_line = 1
      while (index_in_line <= length(line)) {
        pair = substr(line, index_in_line, 2)
        triple = substr(line, index_in_line, 3)

        if (block_comment_depth > 0) {
          if (pair == "/*") {
            block_comment_depth += 1
            index_in_line += 2
          } else if (pair == "*/") {
            block_comment_depth -= 1
            index_in_line += 2
          } else {
            index_in_line += 1
          }
          continue
        }

        if (string_mode == 3) {
          if (triple == "\"\"\"") {
            string_mode = 0
            index_in_line += 3
          } else {
            index_in_line += 1
          }
          continue
        }

        if (string_mode == 1) {
          character = substr(line, index_in_line, 1)
          if (character == "\\") {
            index_in_line += 2
          } else {
            if (character == "\"") {
              string_mode = 0
            }
            index_in_line += 1
          }
          continue
        }

        if (pair == "//") {
          break
        }
        if (pair == "/*") {
          block_comment_depth = 1
          index_in_line += 2
          continue
        }
        if (triple == "\"\"\"") {
          string_mode = 3
          index_in_line += 3
          continue
        }

        character = substr(line, index_in_line, 1)
        if (character == "\"") {
          string_mode = 1
          index_in_line += 1
          continue
        }
        output = output character
        index_in_line += 1
      }
      return output
    }

    {
      code_line = swift_code_line($0)
    }
    !capturing && index(code_line, declaration_prefix) {
      capturing = 1
    }
    capturing {
      if (output_mode == "code") {
        print code_line
      } else {
        print
      }
      open_line = code_line
      close_line = code_line
      opens = gsub(/\{/, "", open_line)
      closes = gsub(/\}/, "", close_line)
      depth += opens - closes
      if (opens > 0) {
        opened = 1
      }
      if (opened && depth == 0) {
        exit
      }
    }
  ' "$file"
}

require_fixed_order() {
  local content="$1"
  local first="$2"
  local second="$3"
  local label="$4"
  local ordered
  ordered="$(printf '%s\n' "$content" | awk -v first="$first" -v second="$second" '
    first_line == 0 && index($0, first) {
      first_line = NR
    }
    second_line == 0 && index($0, second) {
      second_line = NR
    }
    END {
      if (first_line > 0 && second_line > first_line) {
        print first_line ":" second_line
      }
    }
  ')"
  [[ -n "$ordered" ]] || fail "$label"
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
SPARKLE_CREDENTIAL_VALIDATOR="scripts/ci/validate-release-credentials.sh"
SPARKLE_SIGNATURE_VERIFIER="scripts/release/verify-sparkle-ed25519-signatures.swift"
SPARKLE_OLD_TO_NEW_GATE="scripts/ci/verify-sparkle-old-to-new-update.sh"
SPARKLE_LIVE_GATE_HELPER="scripts/qa/sparkle-live-gate-helper.rb"
SPARKLE_DISPOSABLE_SOURCE_PREPARER="scripts/qa/prepare-sparkle-disposable-source.rb"
RELEASE_ASSET_VERIFIER="scripts/release/verify-release-assets.sh"
RELEASE_ASSET_FIXTURES="scripts/ci/verify-release-asset-verifier.sh"
LICENSE_VERIFIER="IslandCore/Sources/IslandCore/Commerce/CommercialLicenseVerifier.swift"
LICENSE_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseVerifierTests.swift"
LICENSE_STORE="IslandCore/Sources/IslandCore/Commerce/CommercialLicenseDocumentStore.swift"
LICENSE_STORE_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseDocumentStoreTests.swift"
LICENSE_STORE_TEST_BACKEND="IslandCoreTests/Sources/IslandCoreTests/InMemoryCommercialLicenseDocumentStorage.swift"
LICENSE_ACTIVATION="IslandCore/Sources/IslandCore/Commerce/CommercialLicenseActivation.swift"
LICENSE_ACTIVATION_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseActivationTests.swift"
LICENSE_ACTIVATION_HTTPS="IslandCore/Sources/IslandCore/Commerce/CommercialActivationHTTPSTransport.swift"
LICENSE_ACTIVATION_HTTPS_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialActivationHTTPSTransportTests.swift"
LICENSE_ACTIVATION_SANDBOX_TESTS="IslandCoreTests/Sources/IslandCoreTests/CommercialActivationSandboxTests.swift"
KEYCHAIN_STORE="IslandCore/Sources/IslandCore/Storage/KeychainStore.swift"
KEYCHAIN_STORE_TESTS="IslandCoreTests/Sources/IslandCoreTests/KeychainStoreTests.swift"
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
SINGLE_INSTANCE_GATE="IslandAppLib/Support/AppSingleInstanceGate.swift"
SINGLE_INSTANCE_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/AppSingleInstanceGateTests.swift"
APP_TERMINATION_COORDINATOR="IslandAppLib/Coordinator/AppTerminationCoordinator.swift"
APP_TERMINATION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/AppTerminationCoordinatorTests.swift"
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
  'v2/webhook\.list' \
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

LIST_WEBHOOK_BODY="$(extract_braced_region "$MANUS_CLIENT" 'public func listWebhooks')"
for invariant in \
  'let req = try ManusEndpoints.listWebhooks(apiKey: apiKey)' \
  'operation: .listWebhooks' \
  'rows.count <= ManusWebhookPolicy.maximumWebhookCount' \
  'identifiers.insert(webhook.id).inserted'; do
  printf '%s\n' "$LIST_WEBHOOK_BODY" | rg -Fq "$invariant" \
    || fail "Strict Manus webhook.list invariant missing: $invariant"
done
for invariant in \
  'private struct ManusWebhookDTO: Decodable' \
  'let createdAt: Int64' \
  'ManusWebhookPolicy.isCanonicalHTTPSURL(url)' \
  'let status = ManusWebhook.Status(rawValue: status)' \
  'createdAt >= 0' \
  'private struct WebhookListResponse: Decodable'; do
  rg -Fq "$invariant" "$MANUS_CLIENT" \
    || fail "Strict Manus webhook.list DTO invariant missing: $invariant"
done
for regression in \
  'testListWebhooksUsesOfficialEndpointAndReturnsValidatedModels' \
  'testListWebhooksRejectsRedirectWithoutFollowingCredential' \
  'testListWebhooksRejectsOversizedBodyBeforeDecode' \
  'testListWebhooksRejectsAmbiguousOrUnsafeProviderRows' \
  'testListWebhooksRequiresAllOfficialFieldsWithExactTypes' \
  'testListWebhooksRejectsMoreThan1024Rows'; do
  rg -Fq "$regression" "$MANUS_CLIENT_TESTS" \
    || fail "Strict Manus webhook.list regression missing: $regression"
done

DELETE_WEBHOOK_BODY="$(extract_braced_region "$MANUS_CLIENT" 'public func deleteWebhook')"
for invariant in \
  'let response: WebhookDeletionResponse = try await execute(' \
  'operation: .deleteWebhook' \
  'guard response.ok else { throw ManusError.invalidResponse }'; do
  printf '%s\n' "$DELETE_WEBHOOK_BODY" | rg -Fq "$invariant" \
    || fail "Manus webhook deletion confirmation invariant missing: $invariant"
done
if printf '%s\n' "$DELETE_WEBHOOK_BODY" | rg -q 'executeVoid'; then
  fail "A successful HTTP status alone must not confirm Manus webhook deletion"
fi
[[ "$(rg -Fc 'private struct WebhookDeletionResponse: Decodable' "$MANUS_CLIENT")" -eq 1 ]] \
  || fail "Manus webhook deletion must use exactly one explicit response DTO"
WEBHOOK_DELETION_RESPONSE="$(
  extract_braced_region "$MANUS_CLIENT" 'private struct WebhookDeletionResponse'
)"
printf '%s\n' "$WEBHOOK_DELETION_RESPONSE" | rg -Fq 'let ok: Bool' \
  || fail "Manus webhook deletion confirmation must decode a Boolean ok field"
for regression in \
  'testDeleteWebhookUsesOfficialV2RPCShape' \
  'testDeleteWebhookRejectsExplicitFailureResponse' \
  'testDeleteWebhookRejectsNon2xxEvenWithSuccessJSON' \
  'testDeleteWebhookTreatsOfficialNotFoundAsIdempotentSuccess' \
  'testDeleteWebhookRejectsOrdinaryOrMalformedNotFoundResponses' \
  'testDeleteWebhookRejectsNotFoundFromWrongOrigin' \
  'testDeleteWebhookRejectsRedirectEvenWithNotFoundBody' \
  'testDeleteWebhookRejectsOversizedNotFoundBeforeDecode' \
  'testDeleteWebhookRejectsMissingOrInvalidSuccessConfirmation' \
  'testStopTaskStillAcceptsEmptySuccessfulResponse'; do
  rg -Fq "$regression" "$MANUS_CLIENT_TESTS" \
    || fail "Manus webhook deletion confirmation regression missing: $regression"
done

EXECUTE_BODY="$(extract_braced_region "$MANUS_CLIENT" 'private func execute<T: Decodable>')"
for invariant in \
  'case 404:' \
  'operation == .deleteWebhook' \
  'response.ok == false' \
  'response.error.code == "not_found"' \
  'return idempotentNotFoundValue'; do
  printf '%s\n' "$EXECUTE_BODY" | rg -Fq "$invariant" \
    || fail "Strict Manus delete not_found invariant missing: $invariant"
done

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

WEBHOOK_KEY_IDENTITY_BODY="$(
  extract_braced_region "$SERVER_FILE" 'private enum WebhookPublicKeyIdentity'
)"
rg -Fxq 'import Security' "$SERVER_FILE" \
  || fail "Canonical Manus RSA trust identity must use Security.framework"
for invariant in \
  'SecKeyCopyAttributes(key)' \
  'kSecAttrKeySizeInBits' \
  'keySizeInBits >= 2_048' \
  'SecKeyCopyExternalRepresentation(' \
  'Data(SHA256.hash(data: canonicalBytes))'; do
  printf '%s\n' "$WEBHOOK_KEY_IDENTITY_BODY" | rg -Fq "$invariant" \
    || fail "Canonical Manus RSA trust identity invariant missing: $invariant"
done
rg -Fq 'let canonicalPublicKeyIdentity: Data' "$SERVER_FILE" \
  || fail "Webhook authentication must retain the canonical RSA public-key identity"
WEBHOOK_TRUST_CONFIGURATION="$(
  extract_braced_region "$SERVER_FILE" 'private struct WebhookTrustConfiguration'
)"
for invariant in 'let externalURL: String' 'let publicKeyIdentity: Data'; do
  printf '%s\n' "$WEBHOOK_TRUST_CONFIGURATION" | rg -Fq "$invariant" \
    || fail "Webhook trust tuple invariant missing: $invariant"
done

WEBHOOK_CONFIGURE_BODY="$(
  extract_braced_region "$SERVER_FILE" 'public func configure(externalURL:'
)"
for invariant in \
  'let candidateConfiguration = WebhookTrustConfiguration(' \
  'externalURL: externalURL' \
  'publicKeyIdentity: authenticator.canonicalPublicKeyIdentity' \
  'if trustConfiguration != candidateConfiguration {' \
  'replayWindow = WebhookReplayWindow(capacity: replayWindow.capacity)' \
  'trustGeneration = UUID()' \
  'self.trustConfiguration = candidateConfiguration'; do
  printf '%s\n' "$WEBHOOK_CONFIGURE_BODY" | rg -Fq "$invariant" \
    || fail "Webhook trust-generation rotation invariant missing: $invariant"
done
require_fixed_order \
  "$WEBHOOK_CONFIGURE_BODY" \
  'let candidateConfiguration = WebhookTrustConfiguration(' \
  'if trustConfiguration != candidateConfiguration {' \
  "Webhook trust tuple must be validated before generation comparison"
require_fixed_order \
  "$WEBHOOK_CONFIGURE_BODY" \
  'if trustConfiguration != candidateConfiguration {' \
  'self.authenticator = authenticator' \
  "Webhook trust generation must rotate before the candidate authenticator is committed"

WEBHOOK_DELIVERY_BODY="$(
  extract_braced_region "$SERVER_FILE" 'private func markEventForDelivery'
)"
for invariant in \
  'authentication.trustGeneration == trustGeneration' \
  'return .staleTrustGeneration'; do
  printf '%s\n' "$WEBHOOK_DELIVERY_BODY" | rg -Fq "$invariant" \
    || fail "Stale webhook trust-generation rejection invariant missing: $invariant"
done
for regression in \
  'testRSAKeyBelow2048BitsCannotCreateAuthenticator' \
  'testLiveHTTPReplayWindowTracksCanonicalTrustGeneration' \
  'testLiveHTTPRequestAuthenticatedBeforeRotationCannotEnterNewTrustGeneration'; do
  rg -Fq "$regression" "$WEBHOOK_AUTH_TESTS" \
    || fail "Webhook trust-generation regression missing: $regression"
done

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
  'private static let replayCacheLimit = 1_024' \
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

if rg -n 'webhookPublicKeyPEM|(^|[^[:alnum:]_])WebhookServer\(\)' \
  IslandCore IslandCoreCLI IslandCoreTests; then
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
for file in \
  "$SPARKLE_CREDENTIAL_VALIDATOR" \
  "$SPARKLE_SIGNATURE_VERIFIER" \
  "$SPARKLE_OLD_TO_NEW_GATE" \
  "$SPARKLE_LIVE_GATE_HELPER" \
  "$SPARKLE_DISPOSABLE_SOURCE_PREPARER" \
  "$RELEASE_ASSET_VERIFIER" \
  "$RELEASE_ASSET_FIXTURES"; do
  test -s "$file" || fail "Sparkle cryptographic release artifact is missing: $file"
done
for invariant in \
  'EXPECTED_HASHES' \
  'remote package reference remained in disposable Sparkle project' \
  'DevIslandDisposableEnvironment' \
  '__CFPREFERENCES_AVOID_DAEMON' \
  'private cache/home + launch-job environment'; do
  rg -Fq "$invariant" "$SPARKLE_DISPOSABLE_SOURCE_PREPARER" \
    || fail "Sparkle disposable-source invariant missing: $invariant"
done
test -x "$SPARKLE_OLD_TO_NEW_GATE" && test -x "$SPARKLE_LIVE_GATE_HELPER" \
  || fail "Sparkle old-to-new live gate is not executable"
for invariant in \
  'ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a' \
  'SPUCommandLineDriver.m' \
  'SUVerifyUpdateBeforeExtraction' \
  'SURequireSignedFeed' \
  '--check-immediately' \
  'feed-wrong-feed.xml' \
  'feed-wrong-archive.xml' \
  'feed-wrong-key.xml' \
  'feed-corrupt-code-signature.xml' \
  '__CFPREFERENCES_AVOID_DAEMON' \
  'prepare-sparkle-disposable-source.rb' \
  'mktemp -d -t dev-island-sparkle-old-to-new' \
  'HOME="$BUILD_HOME"' \
  'HOME="$DISPOSABLE_HOME"' \
  '/bin/ps -wwaxo pid=,command=' \
  '-disableAutomaticPackageResolution' \
  'native Sparkle ad-hoc helper identities preserved' \
  'signal_disposable_helpers TERM' \
  'signal_disposable_helpers KILL' \
  'env -i'; do
  rg -Fq -- "$invariant" "$SPARKLE_OLD_TO_NEW_GATE" \
    || fail "Sparkle old-to-new gate invariant missing: $invariant"
done
if rg -q '(?:/usr/bin/)?defaults[[:space:]]+(write|delete)' "$SPARKLE_OLD_TO_NEW_GATE"; then
  fail "Disposable Sparkle gate must not mutate real-user preferences"
fi
if rg -q 'CODE_SIGNING_(ALLOWED|REQUIRED)=NO|inject_disposable_environment' \
    "$SPARKLE_OLD_TO_NEW_GATE"; then
  fail "Disposable Sparkle gate must preserve source-built helper identities"
fi
for invariant in \
  'TCPServer.new("127.0.0.1", 0)' \
  'File::RDONLY | File::NOFOLLOW | File::NONBLOCK' \
  'Process.spawn(*command, pgroup: true' \
  'Process.kill("TERM", -process_group)' \
  'Process.kill("KILL", -process_group)'; do
  rg -Fq "$invariant" "$SPARKLE_LIVE_GATE_HELPER" \
    || fail "Sparkle live-gate helper invariant missing: $invariant"
done
if rg -q 'SPARKLE_(PUBLIC|PRIVATE)_ED_KEY' "$SPARKLE_OLD_TO_NEW_GATE"; then
  fail "Disposable Sparkle gate must never read production update keys"
fi
[[ "$(rg -Fc './scripts/ci/verify-sparkle-old-to-new-update.sh' "$CI_WORKFLOW")" -eq 1 ]] \
  || fail "PR CI must run the disposable Sparkle old-to-new gate exactly once"
[[ "$(rg -Fc './scripts/ci/verify-sparkle-old-to-new-update.sh' "$RELEASE_WORKFLOW")" -eq 1 ]] \
  || fail "Tagged Release must run the disposable Sparkle old-to-new gate exactly once"
for invariant in \
  'Curve25519.Signing.PublicKey' \
  'publicKey.isValidSignature' \
  'O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC' \
  'Sparkle archive Ed25519 signature verification failed' \
  'Sparkle feed Ed25519 signature verification failed'; do
  rg -Fq "$invariant" "$SPARKLE_SIGNATURE_VERIFIER" \
    || fail "Sparkle CryptoKit verification invariant missing: $invariant"
done
rg -Fq 'SPARKLE_PUBLIC_ED_KEY and SPARKLE_PRIVATE_ED_KEY must form one Ed25519 key pair' \
  "$SPARKLE_CREDENTIAL_VALIDATOR" \
  || fail "Release credentials must prove the Sparkle public/private key pairing"
rg -Fq "'Dev Island.app/Contents/Info.plist'" "$RELEASE_ASSET_VERIFIER" \
  || fail "Release verification must extract the public key from the shipped App"
rg -Fq 'verify-sparkle' "$RELEASE_ASSET_VERIFIER" \
  || fail "Release verification must cryptographically verify both Sparkle signatures"
for regression in \
  'unrelated-archive-signature' \
  'unrelated-feed-signature' \
  'tampered-signed-feed-prefix' \
  'mismatched-embedded-public-key'; do
  rg -Fq "$regression" "$RELEASE_ASSET_FIXTURES" \
    || fail "Sparkle Ed25519 attack fixture is missing: $regression"
done
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
for invariant in \
  '/bin/sh -c' \
  'dev-island-sparkle-generator-supervisor' \
  '"$@" <&3 3<&- &' \
  'generator_pid=$!' \
  'exec 3<&-' \
  '3<&0' \
  'wait "$generator_pid"'; do
  rg -Fq "$invariant" "$SPARKLE_SECRET_RUNNER" \
    || fail "Sparkle clean-parent supervisor invariant missing: $invariant"
done
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
  'Build-flavor marker fixtures: PASS (21 negative cases)'; do
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
  "$LICENSE_VERIFIER" "$LICENSE_STORE" "$LICENSE_ACTIVATION"; then
  fail "Commercial verifier, store, and activation coordinator must remain public-key-only, local, and endpoint-free"
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
  'CommercialLicenseDocumentStorageBackend' \
  'CommercialLicenseKeychainBackend' \
  'private let backend: any CommercialLicenseDocumentStorageBackend' \
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
  'testShippingKeychainPolicyIsDeviceOnlyAndNonSynchronizing' \
  'testOlderGenerationCannotReplaceNewerStoredLicense' \
  'testEqualGenerationIsIdempotentButConflictingBytesAreRejected' \
  'testHigherGenerationCannotMoveSignedIssuanceTimeBackward' \
  'testConcurrentImportsCannotLeaveAnOlderGenerationStored'; do
  rg -q "$storage_regression" "$LICENSE_STORE_TESTS" \
    || fail "Commercial license storage regression missing: $storage_regression"
done
test -s "$LICENSE_STORE_TEST_BACKEND" \
  || fail "Hermetic commercial-license storage backend is missing"
for hermetic_storage_invariant in \
  'CommercialLicenseDocumentStorageBackend' \
  'InMemoryCommercialLicenseDocumentStorage' \
  'CommercialLicenseDocumentStore\(backend: storage\)' \
  'never touches a.*login Keychain'; do
  rg -q "$hermetic_storage_invariant" \
    "$LICENSE_STORE_TEST_BACKEND" "$LICENSE_STORE_TESTS" "$LICENSE_ACTIVATION_TESTS" \
    || fail "Hermetic commercial-license test invariant missing: $hermetic_storage_invariant"
done
if rg -n 'SecItem(Add|Update|CopyMatching|Delete)|CommercialLicenseDocumentStore\(service:' \
  "$LICENSE_STORE_TESTS" "$LICENSE_ACTIVATION_TESTS" "$LICENSE_STORE_TEST_BACKEND"; then
  fail "Ordinary commercial-license tests must never access the real Keychain"
fi

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
  'guard !Task\.isCancelled else \{ return \.cancelled \}' \
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
  'testSuccessfulActivationVerifiesAndRoundTripsThroughSecureStorage' \
  'testTamperedAndOversizedResponsesNeverReplaceValidDocument' \
  'testTransportErrorsAreNormalizedWithoutLeakingRawDetails' \
  'testLatestConcurrentActivationIsTheOnlyDocumentSaved' \
  'testPreCancelledActivationCannotSupersedePendingOperationOrCallTransport' \
  'testExplicitCancellationRejectsLateTransportResponse' \
  'testResponseIsEvaluatedAtCommitTimeNotRequestStart' \
  'testSignedRollbackIsRejectedWithoutReplacingCurrentLicense'; do
  rg -q "$activation_regression" "$LICENSE_ACTIVATION_TESTS" \
    || fail "Commercial activation regression missing: $activation_regression"
done

test -s "$LICENSE_ACTIVATION_HTTPS" \
  || fail "Hardened commercial activation HTTPS transport is missing"
test -s "$LICENSE_ACTIVATION_HTTPS_TESTS" \
  || fail "Commercial activation HTTPS transport regressions are missing"
for https_transport_invariant in \
  'public struct CommercialActivationHTTPSTransport' \
  'init\(endpoint: URL\) throws' \
  'activationPath = "/v1/activate"' \
  'licenseContentType = "application/vnd.devisland.license"' \
  'requestTimeout: TimeInterval = 10' \
  'components\.scheme\?\.lowercased\(\) == "https"' \
  'components\.port == nil \|\| components\.port == 443' \
  'components\.user == nil' \
  'components\.password == nil' \
  'components\.percentEncodedPath == activationPath' \
  'components\.percentEncodedQuery == nil' \
  'components\.fragment == nil' \
  'isPublicDNSName' \
  'URLSessionConfiguration\.ephemeral' \
  'connectionProxyDictionary = \[:\]' \
  'httpShouldSetCookies = false' \
  'urlCredentialStorage = nil' \
  'urlCache = nil' \
  'waitsForConnectivity = false' \
  'httpMaximumConnectionsPerHost = 1' \
  'CommercialActivationHTTPSNoRedirectDelegate' \
  'willPerformHTTPRedirection' \
  'completionHandler\(nil\)' \
  'session\.bytes\(for: request\)' \
  'response\.url == endpoint' \
  'response\.expectedContentLength' \
  'guard document\.count < maximumBytes' \
  'Task\.checkCancellation\(\)' \
  'case 400, 401, 404' \
  'case 429' \
  'case 500\.\.\.599'; do
  rg -q "$https_transport_invariant" "$LICENSE_ACTIVATION_HTTPS" \
    || fail "Commercial activation HTTPS invariant missing: $https_transport_invariant"
done
if rg -n '^\s*public\s+(init|static\s+func)\b' \
  "$LICENSE_ACTIVATION_HTTPS"; then
  fail "Commercial activation HTTPS endpoint construction must remain module-internal until provider review"
fi
if rg -n 'IslandLogger|os_log|print\(|URLProtocol|XCTest|Signing\.PrivateKey' \
  "$LICENSE_ACTIVATION_HTTPS"; then
  fail "Commercial activation HTTPS transport must remain log-free and fixture-free"
fi
if rg -n 'CommercialActivationHTTPSTransport\(' \
  IslandApp IslandAppLib IslandCore/Sources/IslandCore \
  --glob '*.swift'; then
  fail "Commercial activation HTTPS transport must remain disconnected until provider and policy review"
fi
for https_transport_regression in \
  'testEndpointPolicyAcceptsOnlyExactPublicDNSHTTPSOrigin' \
  'testSessionConfigurationIsEphemeralBoundedAndCredentialFree' \
  'testRedirectDelegateNeverAcceptsReplacementRequest' \
  'testExactRequestAndStreamedDocumentResponse' \
  'testStatusMappingNeverReturnsProviderBody' \
  'testDeclaredAndStreamedOversizeResponsesFailBeforeReturningBytes' \
  'testMaximumUnknownLengthResponseIsAcceptedExactlyAtBoundary' \
  'testEmptyWrongMediaTypeUnknownStatusAndMismatchedURLFailClosed' \
  'testTransportErrorIsNormalizedAndCodeNeverAppearsInErrors' \
  'testCallerCancellationStopsInFlightRequestAndStaysCancellation'; do
  rg -q "$https_transport_regression" "$LICENSE_ACTIVATION_HTTPS_TESTS" \
    || fail "Commercial activation HTTPS regression missing: $https_transport_regression"
done
for https_cancellation_invariant in \
  'let requestStopped = expectation\(description: "request stopped"\)' \
  'CommercialActivationHTTPSURLProtocol\.install\(onStop:' \
  'await fulfillment\(of: \[requestStopped\], timeout: 1\)' \
  'override func stopLoading\(\)' \
  'let handler = stopHandler' \
  'handler\?\(\)'; do
  rg -q "$https_cancellation_invariant" "$LICENSE_ACTIVATION_HTTPS_TESTS" \
    || fail "Commercial activation HTTPS cancellation evidence missing: $https_cancellation_invariant"
done
for https_transport_document in \
  "$LICENSE_SECURITY_DOC" \
  "$LICENSE_THREAT_MODEL" \
  docs/CI_DIAGNOSTICS.md \
  docs/INTERFACE_CONTRACT.md \
  docs/DATA_FLOW_INVENTORY.md \
  docs/LEGAL_RELEASE_CHECKLIST.md; do
  rg -q 'CommercialActivationHTTPSTransport|HTTPS transport' \
    "$https_transport_document" \
    || fail "Commercial activation HTTPS boundary is undocumented: $https_transport_document"
done

test -s "$LICENSE_ACTIVATION_SANDBOX_TESTS" \
  || fail "Provider-neutral commercial activation sandbox is missing"
for sandbox_invariant in \
  'import Hummingbird' \
  'http://127\.0\.0\.1:' \
  'endpoint\.host == "127\.0\.0\.1"' \
  'endpoint\.path == "/v1/activate"' \
  'connectionProxyDictionary = \[:\]' \
  'httpShouldSetCookies = false' \
  'willPerformHTTPRedirection' \
  'CommercialLicenseDocumentStore\.maximumDocumentBytes' \
  'InMemoryCommercialLicenseDocumentStorage' \
  'testRealLoopbackRoundTripVerifiesAndStoresSignedLicense' \
  'testUnsignedLoopbackResponseFailsClosedWithoutStorage' \
  'testRealLoopbackStatusMappingIsLowCardinalityAndNeverStoresBodies' \
  'testRedirectUnknownStatusAndOversizedBodyFailClosedWithoutStorage' \
  'testExplicitCancelRejectsCancellationInsensitiveRealHTTPResponse' \
  'testLatestOperationWinsWhenSupersededRealHTTPResponseArrives' \
  'testPreCancelledActivationCannotSupersedeOrSendRealHTTPRequest' \
  'ignoresCallerCancellation' \
  'Task\.detached' \
  'responseDelayMilliseconds' \
  'responseCount' \
  'redirectTargetRequestCount' \
  'http://127\.0\.0\.1:0/v1/activate' \
  'testSandboxTransportAcceptsOnlyExactNumericLoopbackEndpoint'; do
  rg -q "$sandbox_invariant" "$LICENSE_ACTIVATION_SANDBOX_TESTS" \
    || fail "Commercial activation sandbox invariant missing: $sandbox_invariant"
done
if rg -n 'SecItem(Add|Update|CopyMatching|Delete)|kSecClassGenericPassword' \
  "$LICENSE_ACTIVATION_SANDBOX_TESTS"; then
  fail "Commercial activation sandbox must use process-memory storage only"
fi
if rg -n 'CommercialActivationLoopback|/_sandbox/ready' \
  IslandApp IslandAppLib IslandCore/Sources/IslandCore --glob '*.swift'; then
  fail "Commercial activation sandbox implementation must remain test-only"
fi

for keychain_invariant in \
  'protocol KeychainStoreBackend: Sendable' \
  'struct KeychainStoreClient: Sendable' \
  'struct KeychainStoreSecurityBackend: KeychainStoreBackend' \
  'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' \
  'kSecAttrSynchronizable: false'; do
  rg -q "$keychain_invariant" "$KEYCHAIN_STORE" \
    || fail "API-key Keychain boundary invariant missing: $keychain_invariant"
done
for keychain_regression in \
  'testSaveAndLoad' \
  'testSaveOverwritesExistingValue' \
  'testDeleteRemovesValue' \
  'testInvalidUTF8FailsClosedWithoutExposingBytes' \
  'testShippingPolicyIsDeviceOnlyAndNonSynchronizing' \
  'InMemoryKeychainStoreBackend'; do
  rg -q "$keychain_regression" "$KEYCHAIN_STORE_TESTS" \
    || fail "Hermetic API-key storage regression missing: $keychain_regression"
done
if rg -n 'KeychainStore\.(save|load|delete)|SecItem(Add|Update|CopyMatching|Delete)' \
  "$KEYCHAIN_STORE_TESTS"; then
  fail "Ordinary API-key storage tests must never access the production Keychain"
fi
if rg -n 'SecItem(Add|Update|CopyMatching|Delete)' \
  IslandCoreTests IslandAppLibTests --glob '*.swift'; then
  fail "The ordinary Swift test graph must not call Security.framework Keychain mutations"
fi
for documented_control in \
  'raw-body signature verification' \
  'durable event-ID uniqueness' \
  'Single-use short-lived activation code' \
  'WhenUnlockedThisDeviceOnly' \
  'Hardware fingerprint.*Rejected baseline' \
  'pre-provider test-only loopback sandbox' \
  'not evidence for TLS/server identity' \
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
  'case webhookCleanupFailed(underlying: Error)' \
  '@TaskLocal private static var lifecycleCallbackToken: UUID?' \
  'private struct HeartbeatOperation: Sendable' \
  'private struct LifecycleCallbackOperation: Sendable' \
  'private var heartbeatOperation: HeartbeatOperation?' \
  'private var retiringHeartbeatOperations: [UUID: HeartbeatOperation] = [:]' \
  'private var lifecycleCallbackOperations: [UUID: LifecycleCallbackOperation] = [:]' \
  'private var knownWebhookIDs: [String]' \
  'private var webhookDeletionOperations: [String: WebhookDeletionOperation] = [:]' \
  'private var webhookDeletionAttemptSequence: UInt64 = 0' \
  'private var latestWebhookDeletionAttemptByID: [String: UInt64] = [:]' \
  'private var webhookLaunchOperations: [UUID: WebhookLaunchOperation] = [:]' \
  'private var unresolvedRegistrationTokens: Set<String>' \
  'private var unresolvedRegistrationAttempts:' \
  'private var unresolvedRegistrationAttemptStateIsCorrupt: Bool' \
  'private var webhookListingOperation: WebhookListingOperation?' \
  'static let webhookIDsPreferenceKey = "webhookIds"' \
  'static let unresolvedRegistrationTokensPreferenceKey =' \
  '"unresolvedWebhookRegistrationTokens"' \
  'static let unresolvedRegistrationAttemptsPreferenceKey =' \
  '"unresolvedWebhookRegistrationAttemptsV1"' \
  'static let webhookRecoveryStatePreferenceKey =' \
  '"webhookRecoveryStateV1"' \
  'private static let registrationTimestampToleranceSeconds: Int64 = 300' \
  'private static let maximumKnownWebhookCount = 1_024' \
  'private static let maximumRegistrationAttemptCount = 64' \
  'private static let maximumRecoveryStateBytes = 512 * 1_024' \
  'struct TunnelPreferencesHandle: @unchecked Sendable' \
  'static let shipping = TunnelPreferencesHandle(' \
  'let restoredRecoveryState = Self.restoreWebhookRecoveryState(' \
  'self.knownWebhookIDs = restoredRecoveryState.knownWebhookIDs' \
  'self.unresolvedRegistrationTokens =' \
  'self.unresolvedRegistrationAttempts =' \
  'self.unresolvedRegistrationAttemptStateIsCorrupt =' \
  'actor CleanupOnlyWebhookServer: WebhookServerProtocol'; do
  rg -Fq "$invariant" "$TUNNEL_MANAGER" \
    || fail "Persisted Manus webhook cleanup invariant missing: $invariant"
done
[[ "$(rg -Fc 'func stop() async throws' "$TUNNEL_MANAGER")" -eq 2 ]] \
  || fail "Both the Manus tunnel protocol and TunnelManager stop must report cleanup failure"

TUNNEL_STOP_WRAPPER="$(
  extract_braced_region "$TUNNEL_MANAGER" 'func stop() async throws {'
)"
for invariant in \
  'private struct StopOperation: Sendable' \
  'private var stopOperation: StopOperation?' \
  'private var stopWaiterCounts: [UUID: Int] = [:]'; do
  rg -Fq "$invariant" "$TUNNEL_MANAGER" \
    || fail "Single-flight TunnelManager stop ownership missing: $invariant"
done
for invariant in \
  'if let existing = stopOperation' \
  'if let callerCallbackToken,' \
  'lifecycleCallbackOperations[callerCallbackToken] != nil' \
  'throw TunnelError.lifecycleSuperseded' \
  'operation = existing' \
  'stopWaiterCounts[existing.token, default: 0] += 1' \
  'let token = UUID()' \
  'let task = Task.detached' \
  'try await performStop(' \
  'excludingLifecycleCallback: callerCallbackToken' \
  'let created = StopOperation(token: token, task: task)' \
  'stopOperation = created' \
  'stopWaiterCounts[token] = 1' \
  'let stopError: (any Error)?' \
  'try await operation.task.value' \
  'if callerCallbackToken == nil {' \
  'await joinLifecycleCallbacks()' \
  'releaseStopWaiter(ifMatching: operation.token)' \
  'if let stopError {' \
  'throw stopError'; do
  printf '%s\n' "$TUNNEL_STOP_WRAPPER" | rg -Fq "$invariant" \
    || fail "Single-flight TunnelManager stop wrapper missing: $invariant"
done
if ! printf '%s\n' "$TUNNEL_STOP_WRAPPER" | rg -Uq \
    'if let callerCallbackToken,[[:space:]]+lifecycleCallbackOperations\[callerCallbackToken\] != nil \{[[:space:][:print:]]*throw TunnelError\.lifecycleSuperseded'; then
  fail "A lifecycle callback joining its externally-owned stop must fail superseded without forming a wait cycle"
fi
require_fixed_order \
  "$TUNNEL_STOP_WRAPPER" \
  'stopOperation = created' \
  'try await operation.task.value' \
  "TunnelManager must publish credential-release ownership before callers join it"
require_fixed_order \
  "$TUNNEL_STOP_WRAPPER" \
  'try await operation.task.value' \
  'await joinLifecycleCallbacks()' \
  "External TunnelManager stop must join lifecycle callbacks after the stop transaction"
require_fixed_order \
  "$TUNNEL_STOP_WRAPPER" \
  'await joinLifecycleCallbacks()' \
  'releaseStopWaiter(ifMatching: operation.token)' \
  "External TunnelManager stop must join callbacks before releasing its single-flight waiter"
require_fixed_order \
  "$TUNNEL_STOP_WRAPPER" \
  'releaseStopWaiter(ifMatching: operation.token)' \
  'throw stopError' \
  "Failed external TunnelManager stop must release its waiter before returning the shared error"

TUNNEL_RELEASE_STOP_WAITER="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func releaseStopWaiter'
)"
for invariant in \
  'guard let count = stopWaiterCounts[token], count > 0 else { return }' \
  'if count == 1 {' \
  'stopWaiterCounts[token] = nil' \
  'if stopOperation?.token == token {' \
  'stopOperation = nil' \
  'stopWaiterCounts[token] = count - 1'; do
  printf '%s\n' "$TUNNEL_RELEASE_STOP_WAITER" | rg -Fq "$invariant" \
    || fail "TunnelManager stop waiter-retirement invariant missing: $invariant"
done

TUNNEL_STOP_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func performStop('
)"
TUNNEL_STOP_CODE="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func performStop(' code
)"
for invariant in \
  'let launchOperations = await cancelLaunchesAndJoinHeartbeat(' \
  'excludingLifecycleCallback: callbackToken' \
  'let deletionAttemptSequenceAtStart = webhookDeletionAttemptSequence' \
  'let deletionOperationsAtStart = Array(webhookDeletionOperations.values)' \
  'var attemptedWebhookIDs: Set<String> = []' \
  'for operation in deletionOperationsAtStart' \
  'try await awaitWebhookDeletionOperation(operation)' \
  'let completed = await waitForLaunchCompletion(' \
  'timeout: launchCancellationGrace' \
  'guard completed else {' \
  'WebhookCleanupInvariantError.registrationOutcomeUnresolved' \
  'try await operation.task.value' \
  'while let operation = webhookDeletionOperations.values.first {' \
  'for webhookID in knownWebhookIDs {' \
  'latestWebhookDeletionAttemptByID[webhookID, default: 0]' \
  '> deletionAttemptSequenceAtStart' \
  'guard !attemptedWebhookIDs.contains(webhookID),' \
  '!attemptStartedDuringStop else { continue }' \
  'try await reconcileUnresolvedRegistrationOutcomes()' \
  'await stopServerOnly()' \
  'throw firstCleanupError' \
  'guard knownWebhookIDs.isEmpty,' \
  'unresolvedRegistrationTokens.isEmpty,' \
  'unresolvedRegistrationAttempts.isEmpty,' \
  '!unresolvedRegistrationAttemptStateIsCorrupt,' \
  'webhookLaunchOperations.isEmpty,' \
  'webhookDeletionOperations.isEmpty,' \
  'webhookListingOperation == nil else {' \
  'WebhookCleanupInvariantError.persistedWebhookIDsRemain'; do
  printf '%s\n' "$TUNNEL_STOP_BODY" | rg -Fq "$invariant" \
    || fail "Credential-releasing TunnelManager stop invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'let deletionOperationsAtStart = Array(webhookDeletionOperations.values)' \
  'try await cleanupActiveTransport()' \
  "TunnelManager stop must snapshot in-flight stored deletion ownership before its first suspension"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'try await cleanupActiveTransport()' \
  'for operation in deletionOperationsAtStart' \
  "TunnelManager stop must join stored deletions that were active at credential-release entry"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'try await awaitWebhookDeletionOperation(operation)' \
  'let completed = await waitForLaunchCompletion(' \
  "TunnelManager stop must join entry-time deletion ownership before waiting on registrations"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'let completed = await waitForLaunchCompletion(' \
  'try await operation.task.value' \
  "TunnelManager stop must prove launch completion before joining its retained result"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'try await operation.task.value' \
  'while let operation = webhookDeletionOperations.values.first {' \
  "TunnelManager stop must join registrations before draining their late deletion ownership"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'while let operation = webhookDeletionOperations.values.first {' \
  'for webhookID in knownWebhookIDs {' \
  "TunnelManager stop must join launch-exposed deletion ownership before draining persisted IDs"

TUNNEL_POST_RECONCILIATION_DRAIN="$(
  printf '%s\n' "$TUNNEL_STOP_CODE" | awk '
    !capturing && index($0, "try await reconcileUnresolvedRegistrationOutcomes()") {
      capturing = 1
    }
    capturing {
      print
    }
    capturing && index($0, "await stopServerOnly()") {
      exit
    }
  '
)"
for invariant in \
  'try await reconcileUnresolvedRegistrationOutcomes()' \
  'while let operation = webhookDeletionOperations.values.first {' \
  'try await awaitWebhookDeletionOperation(operation)' \
  'await stopServerOnly()'; do
  printf '%s\n' "$TUNNEL_POST_RECONCILIATION_DRAIN" | rg -Fq "$invariant" \
    || fail "Post-reconciliation TunnelManager deletion drain invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_POST_RECONCILIATION_DRAIN" \
  'try await reconcileUnresolvedRegistrationOutcomes()' \
  'while let operation = webhookDeletionOperations.values.first {' \
  "TunnelManager stop must reconcile before joining deletion ownership published by another list waiter"
require_fixed_order \
  "$TUNNEL_POST_RECONCILIATION_DRAIN" \
  'while let operation = webhookDeletionOperations.values.first {' \
  'try await awaitWebhookDeletionOperation(operation)' \
  "TunnelManager post-reconciliation drain must join each retained deletion operation"
require_fixed_order \
  "$TUNNEL_POST_RECONCILIATION_DRAIN" \
  'try await awaitWebhookDeletionOperation(operation)' \
  'await stopServerOnly()' \
  "TunnelManager stop must join every post-reconciliation deletion operation before closing local resources"
if printf '%s\n' "$TUNNEL_POST_RECONCILIATION_DRAIN" \
  | rg -Fq 'attemptedWebhookIDs'; then
  fail "Post-reconciliation deletion drain must not exclude replacement operations by stale webhook-ID history"
fi
if printf '%s\n' "$TUNNEL_POST_RECONCILIATION_DRAIN" \
  | rg -Fq 'deleteKnownWebhook('; then
  fail "Post-reconciliation deletion drain must join existing ownership without retrying the persisted-ID ledger"
fi
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'try await reconcileUnresolvedRegistrationOutcomes()' \
  'await stopServerOnly()' \
  "TunnelManager stop must reconcile process-death registration outcomes before closing local resources"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'await stopServerOnly()' \
  'throw firstCleanupError' \
  "TunnelManager stop must close local resources before reporting remote cleanup failure"
require_fixed_order \
  "$TUNNEL_STOP_BODY" \
  'throw firstCleanupError' \
  'guard knownWebhookIDs.isEmpty,' \
  "TunnelManager stop must enforce its complete terminal recovery-state gate after cleanup errors are absent"

TUNNEL_LAUNCH_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func launchAndRegister'
)"
for invariant in \
  'try await reconcileUnresolvedRegistrationOutcomes()' \
  'try requireNoUnresolvedRegistrationOutcome()' \
  'webhookLaunchOperations[token] = operation' \
  'while webhookLaunchOperations[token] != nil {' \
  'try Task.checkCancellation()' \
  'try await task.value'; do
  printf '%s\n' "$TUNNEL_LAUNCH_BODY" | rg -Fq "$invariant" \
    || fail "Joinable Manus webhook launch invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_LAUNCH_BODY" \
  'try await reconcileUnresolvedRegistrationOutcomes()' \
  'try requireNoUnresolvedRegistrationOutcome()' \
  "Manus launch must attempt conservative recovery before unresolved state blocks replacement"
require_fixed_order \
  "$TUNNEL_LAUNCH_BODY" \
  'try requireNoUnresolvedRegistrationOutcome()' \
  'let token = UUID()' \
  "Unknown Manus registration outcomes must block before allocating replacement launch ownership"
require_fixed_order \
  "$TUNNEL_LAUNCH_BODY" \
  'webhookLaunchOperations[token] = operation' \
  'while webhookLaunchOperations[token] != nil {' \
  "Webhook launch ownership must be recorded before the caller can suspend"

TUNNEL_REGISTRATION_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func performLaunchAndRegister'
)"
for invariant in \
  'try beginRegistrationOutcomeTracking(' \
  'operationToken,' \
  'callbackURL: webhookURL' \
  'webhookID = try await client.registerWebhook(publicURL: webhookURL)' \
  'let disposition = await client.registrationFailureDisposition(for: error)' \
  'if disposition == .definitivelyRejected {' \
  'try resolveRegistrationOutcome(operationToken)' \
  'try recordAcceptedWebhookID(' \
  'resolvingRegistrationToken: operationToken.uuidString' \
  'try await cleanupKnownWebhooks(excluding: webhookID)'; do
  printf '%s\n' "$TUNNEL_REGISTRATION_BODY" | rg -Fq "$invariant" \
    || fail "Multi-ID Manus webhook registration invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_REGISTRATION_BODY" \
  'try beginRegistrationOutcomeTracking(' \
  'webhookID = try await client.registerWebhook(publicURL: webhookURL)' \
  "Manus registration recovery identity must be persisted before provider I/O"
require_fixed_order \
  "$TUNNEL_REGISTRATION_BODY" \
  'webhookID = try await client.registerWebhook(publicURL: webhookURL)' \
  'try recordAcceptedWebhookID(' \
  "Every accepted Manus webhook ID must enter the atomic recovery envelope immediately"
require_fixed_order \
  "$TUNNEL_REGISTRATION_BODY" \
  'try recordAcceptedWebhookID(' \
  'try await cleanupKnownWebhooks(excluding: webhookID)' \
  "A replacement webhook must persist and resolve its accepted attempt before older cleanup"
[[ "$(printf '%s\n' "$TUNNEL_REGISTRATION_BODY" \
  | rg -Fc 'try resolveRegistrationOutcome(operationToken)')" -eq 1 ]] \
  || fail "Only a definitive registration rejection may separately resolve an attempt"

TUNNEL_REGISTRATION_DISPOSITION="$(
  extract_braced_region \
    "$TUNNEL_MANAGER" \
    'nonisolated func registrationFailureDisposition('
)"
for invariant in \
  'case ManusError.unauthorized,' \
  'ManusError.invalidURL:' \
  'where [400, 401, 403, 404, 405, 410, 422].contains(statusCode)' \
  'return .definitivelyRejected' \
  'default:' \
  'return .outcomeUnknown'; do
  printf '%s\n' "$TUNNEL_REGISTRATION_DISPOSITION" | rg -Fq "$invariant" \
    || fail "Manus registration failure-disposition invariant missing: $invariant"
done
if printf '%s\n' "$TUNNEL_REGISTRATION_DISPOSITION" \
    | rg -n '409|429|rateLimited'; then
  fail "Manus conflict and rate-limit registration failures must remain outcome-unknown"
fi

TUNNEL_BEGIN_REGISTRATION_TRACKING="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func beginRegistrationOutcomeTracking'
)"
for invariant in \
  'let callbackURLSHA256 = Self.callbackURLSHA256(callbackURL)' \
  'let tokenString = token.uuidString' \
  'version: UnresolvedWebhookRegistrationAttempt.schemaVersion' \
  'callbackURLSHA256: callbackURLSHA256' \
  'startedAtUnixSeconds:' \
  'discoveredWebhookIDs: []' \
  'try commitWebhookRecoveryState {' \
  'unresolvedRegistrationTokens.insert(tokenString)' \
  'unresolvedRegistrationAttempts[tokenString] = attempt'; do
  printf '%s\n' "$TUNNEL_BEGIN_REGISTRATION_TRACKING" | rg -Fq "$invariant" \
    || fail "Durable Manus registration recovery identity missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_BEGIN_REGISTRATION_TRACKING" \
  'let attempt = UnresolvedWebhookRegistrationAttempt(' \
  'try commitWebhookRecoveryState {' \
  "Manus registration identity must be complete before the atomic recovery commit"

for invariant in \
  'private struct UnresolvedWebhookRegistrationAttempt:' \
  'static let schemaVersion = 1' \
  'let token: String' \
  'let callbackURLSHA256: String' \
  'let startedAtUnixSeconds: Int64' \
  'let discoveredWebhookIDs: [String]' \
  'private struct WebhookRecoveryStateEnvelope: Codable, Equatable, Sendable' \
  'let knownWebhookIDs: [String]' \
  'let unresolvedRegistrationTokens: [String]' \
  'let unresolvedRegistrationAttempts:'; do
  rg -Fq "$invariant" "$TUNNEL_MANAGER" \
    || fail "Versioned Manus recovery-envelope invariant missing: $invariant"
done

TUNNEL_COMMIT_RECOVERY_STATE="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func commitWebhookRecoveryState'
)"
for invariant in \
  'guard !unresolvedRegistrationAttemptStateIsCorrupt else {' \
  'let previousKnownWebhookIDs = knownWebhookIDs' \
  'let previousTokens = unresolvedRegistrationTokens' \
  'let previousAttempts = unresolvedRegistrationAttempts' \
  'mutation()' \
  'Self.validateWebhookRecoveryState(' \
  'persistWebhookRecoveryStateWithReadback()' \
  'knownWebhookIDs = previousKnownWebhookIDs' \
  'unresolvedRegistrationTokens = previousTokens' \
  'unresolvedRegistrationAttempts = previousAttempts' \
  'unresolvedRegistrationAttemptStateIsCorrupt = true' \
  'WebhookCleanupInvariantError.registrationAttemptPersistenceFailed'; do
  printf '%s\n' "$TUNNEL_COMMIT_RECOVERY_STATE" | rg -Fq "$invariant" \
    || fail "Atomic Manus recovery-envelope commit invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_COMMIT_RECOVERY_STATE" \
  'mutation()' \
  'Self.validateWebhookRecoveryState(' \
  "Manus recovery mutation must be validated before persistence"

TUNNEL_PERSIST_RECOVERY_STATE="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func persistWebhookRecoveryStateWithReadback'
)"
for invariant in \
  'let envelope = WebhookRecoveryStateEnvelope(' \
  'preferences.set(data, forKey: Self.webhookRecoveryStatePreferenceKey)' \
  'guard preferences.synchronize() else { return false }' \
  'let restored = Self.decodeWebhookRecoveryStateEnvelope(rawReadback)' \
  'restored.knownWebhookIDs == knownWebhookIDs' \
  'restored.unresolvedRegistrationTokens' \
  'restored.unresolvedRegistrationAttempts' \
  'persistLegacyRecoveryMirrors(to: preferences)'; do
  printf '%s\n' "$TUNNEL_PERSIST_RECOVERY_STATE" | rg -Fq "$invariant" \
    || fail "Flushed Manus recovery-envelope readback invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_PERSIST_RECOVERY_STATE" \
  'preferences.set(data, forKey: Self.webhookRecoveryStatePreferenceKey)' \
  'guard preferences.synchronize() else { return false }' \
  "Manus recovery envelope must be set before its persistent-domain flush"
require_fixed_order \
  "$TUNNEL_PERSIST_RECOVERY_STATE" \
  'guard preferences.synchronize() else { return false }' \
  'let restored = Self.decodeWebhookRecoveryStateEnvelope(rawReadback)' \
  "Manus recovery envelope must flush before decode/readback"
require_fixed_order \
  "$TUNNEL_PERSIST_RECOVERY_STATE" \
  'let restored = Self.decodeWebhookRecoveryStateEnvelope(rawReadback)' \
  'persistLegacyRecoveryMirrors(to: preferences)' \
  "Compatibility mirrors must be written only after authoritative envelope readback"

for invariant in \
  'if let envelopeObject = preferences.object(' \
  'forKey: webhookRecoveryStatePreferenceKey' \
  'let state = decodeWebhookRecoveryStateEnvelope(data)' \
  'return ([], [], [:], true)' \
  'preferences.object(forKey: webhookIDsPreferenceKey)' \
  'preferences.object(' \
  'forKey: unresolvedRegistrationAttemptsPreferenceKey'; do
  rg -Fq "$invariant" "$TUNNEL_MANAGER" \
    || fail "Authoritative-envelope/legacy-migration invariant missing: $invariant"
done
for invariant in \
  'knownWebhookIDs.count <= maximumKnownWebhookCount' \
  'Set(knownWebhookIDs).count == knownWebhookIDs.count' \
  'unresolvedRegistrationTokens.count' \
  '<= maximumRegistrationAttemptCount' \
  'attempt.callbackURLSHA256.count == 64' \
  'attempt.startedAtUnixSeconds >= 0' \
  'Set(attempt.discoveredWebhookIDs).count' \
  'knownIDs.contains(id)' \
  'discoveredIDs.insert(id).inserted'; do
  rg -Fq "$invariant" "$TUNNEL_MANAGER" \
    || fail "Bounded Manus recovery-envelope validation missing: $invariant"
done

TUNNEL_RECONCILE_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func reconcileUnresolvedRegistrationOutcomes'
)"
for invariant in \
  'guard !unresolvedRegistrationAttemptStateIsCorrupt else { return }' \
  'guard activeTransport == nil else { return }' \
  '!$0.discoveredWebhookIDs.isEmpty' \
  'try await deleteKnownWebhook(webhookID)' \
  '$0.discoveredWebhookIDs.isEmpty' \
  'webhooks = try await listWebhooksForReconciliation()' \
  'attemptsByCallbackDigest[attempt.callbackURLSHA256]?.count' \
  '== 1 else {' \
  'attempt.startedAtUnixSeconds' \
  'Self.registrationTimestampToleranceSeconds' \
  'webhook.status == .active' \
  'webhook.createdAt >= earliestCreatedAt' \
  'webhook.createdAt <= latestCreatedAt' \
  'Self.callbackURLSHA256(webhook.url)' \
  '== attempt.callbackURLSHA256' \
  'guard !matches.isEmpty else { continue }' \
  'try bindDiscoveredWebhookIDs(' \
  'matches.map(\.id)' \
  'try await deleteKnownWebhook(webhook.id)'; do
  printf '%s\n' "$TUNNEL_RECONCILE_BODY" | rg -Fq "$invariant" \
    || fail "Conservative Manus webhook.list reconciliation invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_RECONCILE_BODY" \
  'try bindDiscoveredWebhookIDs(' \
  'try await deleteKnownWebhook(webhook.id)' \
  "Discovered Manus IDs must enter the envelope before provider delete"

TUNNEL_LIST_RECONCILIATION="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func listWebhooksForReconciliation'
)"
for invariant in \
  'if let existing = webhookListingOperation' \
  'try await client.listWebhooks()' \
  'webhookListingOperation = created' \
  'let webhooks = try await operation.task.value' \
  'clearWebhookListingOperation(ifMatching: operation.token)'; do
  printf '%s\n' "$TUNNEL_LIST_RECONCILIATION" | rg -Fq "$invariant" \
    || fail "Single-flight Manus webhook.list invariant missing: $invariant"
done

TUNNEL_BIND_DISCOVERED_IDS="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func bindDiscoveredWebhookIDs'
)"
for invariant in \
  'guard !ids.isEmpty' \
  'Set(ids).count == ids.count' \
  'attempt.discoveredWebhookIDs.isEmpty' \
  'alreadyOwnedIDs.isDisjoint(with: ids)' \
  'try commitWebhookRecoveryState {' \
  'knownWebhookIDs.append(id)' \
  'discoveredWebhookIDs: ids'; do
  printf '%s\n' "$TUNNEL_BIND_DISCOVERED_IDS" | rg -Fq "$invariant" \
    || fail "Atomic Manus discovered-ID binding invariant missing: $invariant"
done

TUNNEL_CLEAR_KNOWN_ID="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func clearKnownWebhookID'
)"
for invariant in \
  'let owningTokens = unresolvedRegistrationAttempts.values' \
  'try commitWebhookRecoveryState {' \
  'knownWebhookIDs.removeAll { $0 == id }' \
  'let remainingIDs = attempt.discoveredWebhookIDs.filter' \
  'if remainingIDs.isEmpty {' \
  'unresolvedRegistrationAttempts[token] = nil' \
  'unresolvedRegistrationTokens.remove(token)' \
  'discoveredWebhookIDs: remainingIDs'; do
  printf '%s\n' "$TUNNEL_CLEAR_KNOWN_ID" | rg -Fq "$invariant" \
    || fail "Transactional Manus discovered-ID retirement invariant missing: $invariant"
done

TUNNEL_PROCESS_START_BODY="$TUNNEL_REGISTRATION_BODY"
for invariant in \
  'var process: (any TunnelProcessProtocol)?' \
  'var processStopRequested: Bool'; do
  rg -Fq "$invariant" "$TUNNEL_MANAGER" \
    || fail "Joinable launch-process ownership missing: $invariant"
done
for invariant in \
  'let process = processFactory()' \
  'attachProcess(process, toLaunch: operationToken)' \
  'publicURL = try await process.start()' \
  'await stopLaunchProcess(operationToken)'; do
  printf '%s\n' "$TUNNEL_PROCESS_START_BODY" | rg -Fq "$invariant" \
    || fail "Launch-process fail-closed invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_PROCESS_START_BODY" \
  'attachProcess(process, toLaunch: operationToken)' \
  'publicURL = try await process.start()' \
  "Tunnel launch must publish process ownership before start can suspend"

TUNNEL_STOP_LAUNCH_PROCESS_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func stopLaunchProcess'
)"
for invariant in \
  '!operation.processStopRequested' \
  'let process = operation.process else { return }' \
  'operation.processStopRequested = true' \
  'webhookLaunchOperations[token] = operation' \
  'await process.stop()'; do
  printf '%s\n' "$TUNNEL_STOP_LAUNCH_PROCESS_BODY" | rg -Fq "$invariant" \
    || fail "Single-stop launch-process invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_STOP_LAUNCH_PROCESS_BODY" \
  'webhookLaunchOperations[token] = operation' \
  'await process.stop()' \
  "Launch-process stop ownership must be recorded before stop can suspend"

TUNNEL_CANCEL_LAUNCHES_BODY="$(
  extract_braced_region \
    "$TUNNEL_MANAGER" \
    'private func cancelLaunchOperationsAndStopProcesses()'
)"
for invariant in \
  'let launches = Array(webhookLaunchOperations.values)' \
  'operation.task.cancel()' \
  'await stopLaunchProcess(operation.token)' \
  'return launches'; do
  printf '%s\n' "$TUNNEL_CANCEL_LAUNCHES_BODY" | rg -Fq "$invariant" \
    || fail "Retained launch cancellation invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_CANCEL_LAUNCHES_BODY" \
  'operation.task.cancel()' \
  'await stopLaunchProcess(operation.token)' \
  "Launch cancellation must signal tasks before stopping every actor-owned process"

TUNNEL_RETIRE_HEARTBEAT_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func retireCurrentHeartbeat()'
)"
for invariant in \
  'guard let operation = heartbeatOperation else { return }' \
  'heartbeatOperation = nil' \
  'retiringHeartbeatOperations[operation.token] = operation' \
  'operation.task.cancel()'; do
  printf '%s\n' "$TUNNEL_RETIRE_HEARTBEAT_BODY" | rg -Fq "$invariant" \
    || fail "Retained heartbeat retirement invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_RETIRE_HEARTBEAT_BODY" \
  'retiringHeartbeatOperations[operation.token] = operation' \
  'operation.task.cancel()' \
  "Heartbeat ownership must move to the retiring ledger before cancellation"

TUNNEL_JOIN_HEARTBEATS_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func joinRetiringHeartbeats()'
)"
for invariant in \
  'let operations = Array(retiringHeartbeatOperations.values)' \
  'await operation.task.value' \
  'retiringHeartbeatOperations[operation.token]?.token == operation.token' \
  'retiringHeartbeatOperations[operation.token] = nil'; do
  printf '%s\n' "$TUNNEL_JOIN_HEARTBEATS_BODY" | rg -Fq "$invariant" \
    || fail "Strict retiring-heartbeat join invariant missing: $invariant"
done

TUNNEL_CANCEL_AND_JOIN_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func cancelLaunchesAndJoinHeartbeat('
)"
for invariant in \
  'retireCurrentHeartbeat()' \
  'let launches = await cancelLaunchOperationsAndStopProcesses()' \
  'await joinRetiringHeartbeats()' \
  'while let operation = lifecycleCallbackOperations.values.first(' \
  'where: { $0.token != callbackToken }' \
  'operation.task.cancel()' \
  'await operation.task.value' \
  'lifecycleCallbackOperations[operation.token]?.token == operation.token' \
  'lifecycleCallbackOperations[operation.token] = nil'; do
  printf '%s\n' "$TUNNEL_CANCEL_AND_JOIN_BODY" | rg -Fq "$invariant" \
    || fail "Heartbeat/callback strict-join invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_CANCEL_AND_JOIN_BODY" \
  'retireCurrentHeartbeat()' \
  'let launches = await cancelLaunchOperationsAndStopProcesses()' \
  "Heartbeat must be retired before its cancellation-unaware launch is interrupted"
require_fixed_order \
  "$TUNNEL_CANCEL_AND_JOIN_BODY" \
  'let launches = await cancelLaunchOperationsAndStopProcesses()' \
  'await joinRetiringHeartbeats()' \
  "Heartbeat-owned launches must be interrupted before strict heartbeat join"
require_fixed_order \
  "$TUNNEL_CANCEL_AND_JOIN_BODY" \
  'await joinRetiringHeartbeats()' \
  'while let operation = lifecycleCallbackOperations.values.first(' \
  "Lifecycle callbacks must be drained only after every retiring heartbeat exits"

TUNNEL_SCHEDULE_CALLBACK_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func scheduleLifecycleCallback('
)"
for invariant in \
  'await self.lifecycleCallbackMayStart(token)' \
  'await Self.$lifecycleCallbackToken.withValue(token)' \
  'await callback()' \
  'await self.finishLifecycleCallback(token)' \
  'let operation = LifecycleCallbackOperation(token: token, task: task)' \
  'lifecycleCallbackOperations[token] = operation'; do
  printf '%s\n' "$TUNNEL_SCHEDULE_CALLBACK_BODY" | rg -Fq "$invariant" \
    || fail "Retained lifecycle-callback ownership invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_SCHEDULE_CALLBACK_BODY" \
  'let operation = LifecycleCallbackOperation(token: token, task: task)' \
  'lifecycleCallbackOperations[token] = operation' \
  "Lifecycle callback handle must be retained in the actor-owned ledger"

TUNNEL_HEARTBEAT_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func runHeartbeat(token: UUID)'
)"
for invariant in \
  'let callbackOperation = callback.map(scheduleLifecycleCallback)' \
  'finishHeartbeat(token)'; do
  printf '%s\n' "$TUNNEL_HEARTBEAT_BODY" | rg -Fq "$invariant" \
    || fail "Heartbeat callback handoff invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_HEARTBEAT_BODY" \
  'let callbackOperation = callback.map(scheduleLifecycleCallback)' \
  'finishHeartbeat(token)' \
  "Heartbeat must retain its callback before releasing heartbeat ownership"

TUNNEL_JOIN_CALLBACKS_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func joinLifecycleCallbacks()'
)"
for invariant in \
  'while let operation = lifecycleCallbackOperations.values.first' \
  'await operation.task.value' \
  'lifecycleCallbackOperations[operation.token]?.token == operation.token' \
  'lifecycleCallbackOperations[operation.token] = nil'; do
  printf '%s\n' "$TUNNEL_JOIN_CALLBACKS_BODY" | rg -Fq "$invariant" \
    || fail "Strict lifecycle-callback join invariant missing: $invariant"
done

TUNNEL_DELETE_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func deleteKnownWebhook'
)"
for invariant in \
  'recordKnownWebhookID(id)' \
  'if let existing = webhookDeletionOperations[id]' \
  'operation = existing' \
  'webhookDeletionAttemptSequence &+= 1' \
  'latestWebhookDeletionAttemptByID[id] = webhookDeletionAttemptSequence' \
  'try await client.deleteWebhook(id: id)' \
  'webhookDeletionOperations[id] = created' \
  'try await awaitWebhookDeletionOperation(operation)'; do
  printf '%s\n' "$TUNNEL_DELETE_BODY" | rg -Fq "$invariant" \
    || fail "Shared Manus webhook deletion invariant missing: $invariant"
done
require_fixed_order \
  "$TUNNEL_DELETE_BODY" \
  'latestWebhookDeletionAttemptByID[id] = webhookDeletionAttemptSequence' \
  'try await client.deleteWebhook(id: id)' \
  "A new per-ID deletion attempt must be recorded before provider I/O"
require_fixed_order \
  "$TUNNEL_DELETE_BODY" \
  'webhookDeletionOperations[id] = created' \
  'try await awaitWebhookDeletionOperation(operation)' \
  "Keyed deletion ownership must be published before any lifecycle caller awaits it"

TUNNEL_AWAIT_DELETE_BODY="$(
  extract_braced_region "$TUNNEL_MANAGER" 'private func awaitWebhookDeletionOperation'
)"
for invariant in \
  'try await operation.task.value' \
  'webhookDeletionOperations[operation.webhookID]?.token == operation.token' \
  'webhookDeletionOperations[operation.webhookID] = nil' \
  'clearKnownWebhookID(operation.webhookID)' \
  'throw TunnelError.webhookCleanupFailed(underlying: error)'; do
  printf '%s\n' "$TUNNEL_AWAIT_DELETE_BODY" | rg -Fq "$invariant" \
    || fail "Joined Manus webhook deletion completion invariant missing: $invariant"
done
[[ "$(printf '%s\n' "$TUNNEL_AWAIT_DELETE_BODY" \
  | rg -Fc 'webhookDeletionOperations[operation.webhookID]?.token == operation.token')" -eq 2 ]] \
  || fail "Both success and failure must retire only the exact joined deletion token"
require_fixed_order \
  "$TUNNEL_AWAIT_DELETE_BODY" \
  'try await operation.task.value' \
  'clearKnownWebhookID(operation.webhookID)' \
  "Persisted webhook IDs may clear only after confirmed provider deletion"
[[ "$(rg -Fc 'try await client.deleteWebhook(id: id)' "$TUNNEL_MANAGER")" -eq 1 ]] \
  || fail "Every lifecycle branch must share the single keyed webhook deletion path"
[[ "$(rg -Fc 'clearKnownWebhookID(operation.webhookID)' "$TUNNEL_MANAGER")" -eq 1 ]] \
  || fail "Webhook cleanup capability must clear only in the confirmed deletion path"

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
  'testStoredWebhookCleanupFailureBlocksReplacementAndRetainsID' \
  'testCleanupOnlyManagerDeletesPersistedIDsWithoutOpeningRealtime' \
  'testStopRetainsFailedDeletionAndNextStartCleansBeforeRegistering' \
  'testHeartbeatDeleteFailureBlocksReplacementAndRetainsID' \
  'testRegistrationFailureStopsUnregisteredProcessAndRollsBackServer' \
  'testWakeFailureIsReturnedAndCannotLeaveProcessOnlyRealtime' \
  'testSuccessfulWakeRestoresOnlyAfterWebhookRegistration' \
  'testHeartbeatRegistrationFailureSignalsPollingOnlyAndStopsReplacement' \
  'testSuccessfulPollCannotPromotePollingOnlyModeToConnected' \
  'testStopDuringRegistrationDeletesLateWebhookAndLeavesNoTransport' \
  'testLateRegistrationFailedDeletionRemainsRetryableAfterSupersession' \
  'testJoinedCleanupFailureDoesNotSuppressOtherPersistedIDs' \
  'testStopJoinsInFlightStoredDeletionBeforeCredentialRelease' \
  'testStopFailsClosedWhenConcurrentCleanupFailureLeavesLedgerID' \
  'testConcurrentStopsShareSuccessfulCredentialReleaseOperation' \
  'testConcurrentStopsShareFailureAndLaterStopRetriesLedger' \
  'testStopStrictlyJoinsHeartbeatBlockedInServerReadiness' \
  'testSuspendJoinsHeartbeatBlockedInProcessCheckBeforeWakePromotesReplacement' \
  'testStopJoinsHeartbeatBlockedAfterClearingActiveBeforeLedgerCleanup' \
  'testBlockedRegistrationStopIsImmediateFailClosedAndLateIDIsCompensated' \
  'testConflictAndRateLimitRegistrationFailuresRemainPersistedUnknown' \
  'testExternalStopJoinsBlockedCallbackWhoseRecursiveStopSeesSingleFlight' \
  'testCallbackOwnedStopLetsExternalWaiterJoinCallbackWithoutCycle' \
  'testSuccessorStartWaitsForRetiringCallbackBeforePromotingNewTransport' \
  'testCallbackOwnedFailedStopStillJoinsCallbackBeforeExternalErrorReturns' \
  'testUnknownRegistrationBlocksOverlapUntilLateIDIsCompensated' \
  'testRestartReconcilesOnlyExactCallbackAndClearsDurableAttempt' \
  'testRestartPersistsEveryExactMatchBeforeDeletingAnyOfThem' \
  'testRestartDoesNotAttributeInactiveExactCallback' \
  'testRestartKeepsAttemptWhenAuthoritativeListIsEmpty' \
  'testRestartKeepsAttemptWhenWebhookListFails' \
  'testRestartRejectsExactCallbackCreatedBeforeAttemptWindow' \
  'testRestartRejectsExactCallbackCreatedAfterAttemptWindow' \
  'testRestartCleansKnownIDThenReconcilesUnknownRegistration' \
  'testTwoUnknownAttemptsWithSameCallbackDigestDeleteNothing' \
  'testWrongTypeLegacyRecoveryStateFailsClosed' \
  'testWrongTypeRecoveryEnvelopeFailsClosedAndIgnoresLegacyMirrors' \
  'testRestartRetriesBoundDiscoveredIDWithoutListingAgain' \
  'testLegacyTokenOnlyMarkerStaysFailClosedWithoutAccountDeletion' \
  'testStopBlockedInListRejectsSuccessorStartAndWake' \
  'testOverlappingRestartReconciliationSharesListAndDeleteOperations' \
  'testPostReconciliationDrainJoinsReplacementDeletionTokenForPreviouslyAttemptedID'; do
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
  'private var pollingOperation: PollingOperation?' \
  'private var retiringPollingOperations: \[UInt64: Task<Void, Never>\]' \
  'private var nextOperationToken: UInt64' \
  'retireCurrentPollingOperation\(\)' \
  'pollingOperationDidFinish\(token: token\)'; do
  rg -q "$invariant" "$POLLING_FALLBACK" \
    || fail "Manus polling lifecycle invariant missing: $invariant"
done
if rg -n 'nonisolated\(unsafe\)' "$POLLING_FALLBACK"; then
  fail "PollingFallback must not restore unsafe shared task state"
fi
POLLING_STOP_BODY="$(
  extract_braced_region "$POLLING_FALLBACK" 'func stop() async {'
)"
for invariant in \
  'lifecycleGeneration &+= 1' \
  'retireCurrentPollingOperation()' \
  'let tasks = Array(retiringPollingOperations.values)' \
  'tasks.forEach { $0.cancel() }' \
  'for task in tasks {' \
  'await task.value'; do
  printf '%s\n' "$POLLING_STOP_BODY" | rg -Fq "$invariant" \
    || fail "Joinable PollingFallback stop invariant missing: $invariant"
done
require_fixed_order \
  "$POLLING_STOP_BODY" \
  'retireCurrentPollingOperation()' \
  'let tasks = Array(retiringPollingOperations.values)' \
  "PollingFallback stop must retire current ownership before snapshotting every superseded poll"
require_fixed_order \
  "$POLLING_STOP_BODY" \
  'tasks.forEach { $0.cancel() }' \
  'await task.value' \
  "PollingFallback stop must cancel and then join every current and superseded poll"

POLLING_RETIRE_BODY="$(
  extract_braced_region "$POLLING_FALLBACK" 'private func retireCurrentPollingOperation() {'
)"
for invariant in \
  'operation.task.cancel()' \
  'retiringPollingOperations[operation.token] = operation.task' \
  'pollingOperation = nil'; do
  printf '%s\n' "$POLLING_RETIRE_BODY" | rg -Fq "$invariant" \
    || fail "Tokenized retiring poll ownership missing: $invariant"
done
POLLING_COMPLETION_BODY="$(
  extract_braced_region "$POLLING_FALLBACK" 'private func pollingOperationDidFinish(token: UInt64) {'
)"
for invariant in \
  'pollingOperation?.token == token' \
  'retiringPollingOperations.removeValue(forKey: token)'; do
  printf '%s\n' "$POLLING_COMPLETION_BODY" | rg -Fq "$invariant" \
    || fail "Exact-token poll completion ownership missing: $invariant"
done
POLLING_START_BODY="$(
  extract_braced_region "$POLLING_FALLBACK" 'func start('
)"
for invariant in \
  'retireCurrentPollingOperation()' \
  'let token = nextOperationToken' \
  'pollingOperationDidFinish(token: token)' \
  'pollingOperation = PollingOperation(token: token, task: task)'; do
  printf '%s\n' "$POLLING_START_BODY" | rg -Fq "$invariant" \
    || fail "Polling restart retirement invariant missing: $invariant"
done
require_fixed_order \
  "$POLLING_START_BODY" \
  'retireCurrentPollingOperation()' \
  'pollingOperation = PollingOperation(token: token, task: task)' \
  "Polling start must retire the superseded operation before publishing its successor"

LOCAL_HOOK_STOP_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'public func stop() async {'
)"
for invariant in \
  '@TaskLocal static var identity: LocalHookDeliveryDrainIdentity?' \
  'await stop(excluding: LocalHookDeliveryDrainContext.identity)' \
  'private struct LifecycleOperation' \
  'let gracefulShutdownControl: LocalHookServeShutdownControl?' \
  'private struct EventDeliveryLifecycle' \
  'private var serverOperation: LifecycleOperation?' \
  'private var readinessOperation: LifecycleOperation?' \
  'private var eventDelivery: EventDeliveryLifecycle?' \
  'private var retiringServerOperations: [UInt64: LifecycleOperation]' \
  'private var retiringReadinessOperations: [UInt64: Task<Void, Never>]' \
  'private var retiringEventDeliveryOperations: [UInt64: Task<Void, Never>]' \
  'private var nextOperationToken: UInt64'; do
  rg -Fq "$invariant" "$LOCAL_HOOK_SERVER" \
    || fail "Tokenized LocalHookServer lifecycle ownership missing: $invariant"
done

LOCAL_HOOK_START_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'public func start('
)"
for invariant in \
  'retireCurrentServerOperation()' \
  'retireCurrentReadinessOperation()' \
  'launchServeLoop(epoch: epoch)'; do
  printf '%s\n' "$LOCAL_HOOK_START_BODY" | rg -Fq "$invariant" \
    || fail "LocalHookServer start retirement invariant missing: $invariant"
done
LOCAL_HOOK_RESTART_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'public func restart() {'
)"
for invariant in \
  'retireCurrentServerOperation()' \
  'retireCurrentReadinessOperation()' \
  'launchServeLoop(epoch: epoch)'; do
  printf '%s\n' "$LOCAL_HOOK_RESTART_BODY" | rg -Fq "$invariant" \
    || fail "LocalHookServer restart retirement invariant missing: $invariant"
done
for invariant in \
  'let callerServerToken = LocalHookDeliveryDrainContext.identity?.ownerServerToken' \
  'retireCurrentEventDelivery()' \
  'retireCurrentServerOperation()' \
  'retireCurrentReadinessOperation()' \
  'let serverTasks = retiringServerOperations.sorted { $0.key < $1.key }' \
  'let readinessTasks = Array(retiringReadinessOperations.values)' \
  'let eventDeliveryTasks = retiringEventDeliveryOperations.sorted { $0.key < $1.key }' \
  'operation.requestStop()' \
  'readinessTasks.forEach { $0.cancel() }' \
  'onEvent = nil' \
  'onActionRequest = nil' \
  'for task in readinessTasks {' \
  'for (token, task) in eventDeliveryTasks where token != callerServerToken {' \
  'for (token, operation) in serverTasks where token != callerServerToken {' \
  'await operation.task.value'; do
  printf '%s\n' "$LOCAL_HOOK_STOP_BODY" | rg -Fq "$invariant" \
    || fail "Joinable LocalHookServer stop invariant missing: $invariant"
done
require_fixed_order \
  "$LOCAL_HOOK_STOP_BODY" \
  'retireCurrentEventDelivery()' \
  'let eventDeliveryTasks = retiringEventDeliveryOperations.sorted' \
  "LocalHookServer stop must retain current delivery ownership before snapshotting every delivery"
require_fixed_order \
  "$LOCAL_HOOK_STOP_BODY" \
  'retireCurrentServerOperation()' \
  'let serverTasks = retiringServerOperations.sorted' \
  "LocalHookServer stop must retire current serve ownership before snapshotting all serve tasks"
require_fixed_order \
  "$LOCAL_HOOK_STOP_BODY" \
  'retireCurrentReadinessOperation()' \
  'let readinessTasks = Array(retiringReadinessOperations.values)' \
  "LocalHookServer stop must retire current readiness ownership before snapshotting all probes"
require_fixed_order \
  "$LOCAL_HOOK_STOP_BODY" \
  'readinessTasks.forEach { $0.cancel() }' \
  'for task in readinessTasks {' \
  "LocalHookServer stop must cancel before joining all readiness operations"
require_fixed_order \
  "$LOCAL_HOOK_STOP_BODY" \
  'for task in readinessTasks {' \
  'for (token, task) in eventDeliveryTasks where token != callerServerToken {' \
  "LocalHookServer stop must join readiness before non-self event delivery"
require_fixed_order \
  "$LOCAL_HOOK_STOP_BODY" \
  'for (token, task) in eventDeliveryTasks where token != callerServerToken {' \
  'for (token, operation) in serverTasks where token != callerServerToken {' \
  "LocalHookServer stop must join non-self delivery before its serve generation"

for invariant in \
  'retireCurrentServerOperation(cancel: false)' \
  'retiringServerOperations[operation.token] = operation' \
  'retiringReadinessOperations[operation.token] = operation.task' \
  'retiringEventDeliveryOperations[current.token] = task' \
  'serverOperationDidFinish(token: serverToken)' \
  'readinessOperationDidFinish(token: readinessOperationToken)' \
  'retiringServerOperations.removeValue(forKey: token)' \
  'retiringReadinessOperations.removeValue(forKey: token)' \
  'readinessOperation?.token == token'; do
  rg -Fq "$invariant" "$LOCAL_HOOK_SERVER" \
    || fail "Current/retiring LocalHookServer token invariant missing: $invariant"
done

LOCAL_HOOK_DELIVERY_STOP_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'fileprivate func stop('
)"
for invariant in \
  'isAcceptingEvents = false' \
  'let queuedEntries = states.values.flatMap(\.queue)' \
  'states = [:]' \
  'entry.completion?.resume(returning: false)' \
  'for operation in currentDrainOperations.values {' \
  'operation.task.cancel()' \
  'retiringDrainOperations[operation.identity.token] = operation.task' \
  'currentDrainOperations = [:]' \
  'callerIdentity?.deliveryID == deliveryID' \
  'let operations = retiringDrainOperations.sorted { $0.key < $1.key }' \
  'for (token, task) in operations where token != callerToken {' \
  'await task.value'; do
  printf '%s\n' "$LOCAL_HOOK_DELIVERY_STOP_BODY" | rg -Fq "$invariant" \
    || fail "Strict Local Hook event-delivery stop invariant missing: $invariant"
done
require_fixed_order \
  "$LOCAL_HOOK_DELIVERY_STOP_BODY" \
  'states = [:]' \
  'entry.completion?.resume(returning: false)' \
  "Local Hook delivery stop must clear queued ownership before failing action barriers neutral"
require_fixed_order \
  "$LOCAL_HOOK_DELIVERY_STOP_BODY" \
  'retiringDrainOperations[operation.identity.token] = operation.task' \
  'currentDrainOperations = [:]' \
  "Local Hook drains must enter retiring ownership before current handles are cleared"
require_fixed_order \
  "$LOCAL_HOOK_DELIVERY_STOP_BODY" \
  'operation.task.cancel()' \
  'await task.value' \
  "Local Hook delivery stop must cancel and join every non-self drain"

LOCAL_HOOK_RETIRE_DELIVERY_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'private func retireCurrentEventDelivery('
)"
for invariant in \
  'eventDelivery = nil' \
  'await current.delivery.stop(excluding: nil)' \
  'await self?.eventDeliveryOperationDidFinish(token: current.token)' \
  'retiringEventDeliveryOperations[current.token] = task'; do
  printf '%s\n' "$LOCAL_HOOK_RETIRE_DELIVERY_BODY" | rg -Fq "$invariant" \
    || fail "Retained Local Hook delivery lifecycle invariant missing: $invariant"
done
require_fixed_order \
  "$LOCAL_HOOK_RETIRE_DELIVERY_BODY" \
  'eventDelivery = nil' \
  'retiringEventDeliveryOperations[current.token] = task' \
  "Local Hook delivery must leave the current slot before publishing retiring ownership"

LOCAL_HOOK_REQUEST_STOP_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'func requestStop() {'
)"
for invariant in \
  'if let gracefulShutdownControl {' \
  'if gracefulShutdownControl.requestShutdown() {' \
  'task.cancel()'; do
  printf '%s\n' "$LOCAL_HOOK_REQUEST_STOP_BODY" | rg -Fq "$invariant" \
    || fail "Graceful Local Hook serve-stop invariant missing: $invariant"
done

LOCAL_HOOK_LAUNCH_SERVE_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'private func launchServeLoop('
)"
for invariant in \
  'retireCurrentEventDelivery(ifMatching: replacingServerToken)' \
  'retireCurrentEventDelivery()' \
  'retireCurrentServerOperation()' \
  'let gracefulShutdownControl = serveOperationOverride == nil' \
  '? LocalHookServeShutdownControl()' \
  'ownerServerToken: serverToken' \
  'gracefulShutdownControl: gracefulShutdownControl!' \
  'gracefulShutdownControl: gracefulShutdownControl'; do
  printf '%s\n' "$LOCAL_HOOK_LAUNCH_SERVE_BODY" | rg -Fq "$invariant" \
    || fail "Production Local Hook graceful-shutdown ownership missing: $invariant"
done

LOCAL_HOOK_SERVE_BODY="$(
  extract_braced_region "$LOCAL_HOOK_SERVER" 'private static func serve('
)"
for invariant in \
  'let serviceGroup = ServiceGroup(' \
  'gracefulShutdownControl.install(serviceGroup)' \
  'try await serviceGroup.run()' \
  'gracefulShutdownControl.serviceGroupDidFinish()'; do
  printf '%s\n' "$LOCAL_HOOK_SERVE_BODY" | rg -Fq "$invariant" \
    || fail "Graceful Hummingbird shutdown invariant missing: $invariant"
done
require_fixed_order \
  "$LOCAL_HOOK_SERVE_BODY" \
  'gracefulShutdownControl.install(serviceGroup)' \
  'try await serviceGroup.run()' \
  "Hummingbird graceful shutdown control must be installed before serving"
for invariant in \
  'private var shutdownTask: Task<Void, Never>?' \
  'shutdownTask = Task {' \
  'await serviceGroup.triggerGracefulShutdown()'; do
  rg -Fq "$invariant" "$LOCAL_HOOK_SERVER" \
    || fail "Retained Hummingbird shutdown trigger missing: $invariant"
done

for regression in \
  'testDeliveryStopCancelsAndJoinsCancellationUnawareCurrentDrain' \
  'testListenerStopJoinsRetiringDeliveryFromSupersededGeneration' \
  'testDeliveryStopFromOwnCallbackDoesNotSelfJoin' \
  'testHTTPActionCallbackInternalStopSelfExcludesAndGracefullyReleasesListener' \
  'testHTTPActionCallbackExternalStopStrictlyJoinsSelfExcludedGeneration'; do
  rg -q "$regression" "$LOCAL_ACTION_TESTS" \
    || fail "Local Hook strict-join/self-stop regression missing: $regression"
done

WEBHOOK_SERVER_STOP_BODY="$(
  extract_braced_region "$SERVER_FILE" 'public func stop() async {'
)"
for invariant in \
  'let task = serverTask' \
  'task?.cancel()' \
  'serverTask = nil' \
  'readinessToken = nil' \
  'await task?.value'; do
  printf '%s\n' "$WEBHOOK_SERVER_STOP_BODY" | rg -Fq "$invariant" \
    || fail "Joinable WebhookServer stop invariant missing: $invariant"
done
require_fixed_order \
  "$WEBHOOK_SERVER_STOP_BODY" \
  'task?.cancel()' \
  'await task?.value' \
  "WebhookServer stop must join its serve loop after cancellation"
for invariant in \
  'ingestManusWebhookEvent' \
  'applyManusPollingSnapshot' \
  'handleManusPollingUnauthorized' \
  'serviceGeneration == manusServiceGeneration'; do
  rg -q "$invariant" "$TASK_STORE" \
    || fail "TaskStore stale-callback invariant missing: $invariant"
done
for regression in \
  'testStopJoinsCancellationUnawareConnectorAndSuppressesLateSnapshot' \
  'testStopJoinsCurrentAndSupersededCancellationUnawarePolls' \
  'testRestartInvalidatesOlderInFlightPoll' \
  'testNetworkEdgesAreCoalescedAndUnauthorizedStopsPolling'; do
  rg -q "$regression" "$POLLING_FALLBACK_TESTS" \
    || fail "Manus polling lifecycle regression missing: $regression"
done
for regression in \
  'testStopJoinsServeLoopSoPortCanBeReboundImmediately' \
  'testStopJoinsCurrentAndSupersededServeAndReadinessOperations' \
  'testServerStopJoinsServeLoopSoPortCanBeReboundImmediately'; do
  rg -q "$regression" "$LOCAL_HOOK_HEALTH_TESTS" "$WEBHOOK_AUTH_TESTS" \
    || fail "Joinable listener-stop regression missing: $regression"
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
  'webhookPreferencesSuiteName: String? = nil' \
  'webhookPreferencesSuiteName: "app.devisland.Island"' \
  'server: CleanupOnlyWebhookServer()' \
  'preferences: TunnelPreferencesHandle(webhookPreferences)' \
  'ManusCredentialRemovalPolicy.cleanupPendingReason' \
  'Remote callback cleanup pending; retry disconnect'; do
  rg -Fq "$invariant" "$TASK_STORE" \
    || fail "Credential-backed Manus cleanup owner invariant missing: $invariant"
done
if rg -n -F 'webhookPreferencesSuiteName: "app.devisland.Island"' IslandCoreTests; then
  fail "Ordinary tests must not attach a Manus cleanup manager to the shipping preferences ledger"
fi

MANUS_START_SERVICES_BODY="$(
  extract_braced_region "$TASK_STORE" 'private func startServices('
)"
for invariant in \
  'let webhookPreferences = manusDependencies.webhookPreferencesSuiteName' \
  'server: CleanupOnlyWebhookServer()' \
  'if ManusRealtimeTrust.liveV2AcceptanceComplete'; do
  printf '%s\n' "$MANUS_START_SERVICES_BODY" | rg -Fq "$invariant" \
    || fail "Polling-only Manus cleanup ownership invariant missing: $invariant"
done
require_fixed_order \
  "$MANUS_START_SERVICES_BODY" \
  'server: CleanupOnlyWebhookServer()' \
  'if ManusRealtimeTrust.liveV2AcceptanceComplete' \
  "A credential-backed cleanup owner must exist even while realtime remains disabled"

CONFIGURE_API_KEY_BODY="$(
  extract_braced_region "$TASK_STORE" 'public func configureAPIKey'
)"
for invariant in \
  'if let removal = manusCredentialRemovalOperation' \
  'try await awaitManusCredentialRemoval(removal)' \
  'if let existingTunnel = tunnelManager' \
  'try await existingTunnel.stop()' \
  'pollingOnlyReason = ManusCredentialRemovalPolicy.cleanupPendingReason' \
  'apiKeyStatus = previousKeyStatus' \
  'try manusDependencies.saveAPIKey(key)'; do
  printf '%s\n' "$CONFIGURE_API_KEY_BODY" | rg -Fq "$invariant" \
    || fail "Replacement-key cleanup transaction invariant missing: $invariant"
done
require_fixed_order \
  "$CONFIGURE_API_KEY_BODY" \
  'try await awaitManusCredentialRemoval(removal)' \
  'manusConfigurationGeneration &+= 1' \
  "A new key configuration must join an in-flight Disconnect before changing generation"
require_fixed_order \
  "$CONFIGURE_API_KEY_BODY" \
  'try await existingTunnel.stop()' \
  'try manusDependencies.saveAPIKey(key)' \
  "An existing Manus webhook must be cleaned before a replacement key is persisted"
for invariant in \
  'let retiredServices = detachManusServices()' \
  'setTasks(tasks.filter { $0.source != "manus" })' \
  'connectionStatus = .disconnected' \
  'await retiredServices.poller?.stop()' \
  'let persistedKey = try manusDependencies.loadAPIKey()' \
  'apiKeyStatus = persistedKey == nil ? .notConfigured : .valid' \
  'apiKeyStatus = previousKeyStatus'; do
  printf '%s\n' "$CONFIGURE_API_KEY_BODY" | rg -Fq "$invariant" \
    || fail "Replacement-key save-failure recovery invariant missing: $invariant"
done
require_fixed_order \
  "$CONFIGURE_API_KEY_BODY" \
  'let retiredServices = detachManusServices()' \
  'try manusDependencies.saveAPIKey(key)' \
  "Old Manus services must be detached before replacement persistence can fail"
require_fixed_order \
  "$CONFIGURE_API_KEY_BODY" \
  'await retiredServices.poller?.stop()' \
  'try manusDependencies.saveAPIKey(key)' \
  "The retired Manus poller must stop before replacement persistence"
require_fixed_order \
  "$CONFIGURE_API_KEY_BODY" \
  'try manusDependencies.saveAPIKey(key)' \
  'let persistedKey = try manusDependencies.loadAPIKey()' \
  "A failed replacement save must read back the Keychain source of truth"

CLEAR_API_KEY_BODY="$(
  extract_braced_region "$TASK_STORE" 'public func clearAPIKey() async throws'
)"
for invariant in \
  'if let removal = manusCredentialRemovalOperation' \
  'try await awaitManusCredentialRemoval(removal)' \
  'await self.manusDependencies.awaitCredentialRemovalPermission()' \
  'guard !self.shutdownRequested else { throw CancellationError() }' \
  'try await self.performClearAPIKey()' \
  'manusCredentialRemovalOperation = removal'; do
  printf '%s\n' "$CLEAR_API_KEY_BODY" | rg -Fq "$invariant" \
    || fail "Shared Manus credential-removal transaction invariant missing: $invariant"
done
require_fixed_order \
  "$CLEAR_API_KEY_BODY" \
  'await self.manusDependencies.awaitCredentialRemovalPermission()' \
  'guard !self.shutdownRequested else { throw CancellationError() }' \
  "A registered but queued Disconnect must observe terminal shutdown before cleanup begins"

PERFORM_CLEAR_API_KEY_BODY="$(
  extract_braced_region "$TASK_STORE" 'private func performClearAPIKey'
)"
for invariant in \
  'let services = detachManusServices()' \
  'try await services.tunnel?.stop()' \
  'tunnelManager = services.tunnel' \
  'apiKeyStatus = previousKeyStatus' \
  'ManusCredentialRemovalPolicy.cleanupPendingReason' \
  'try manusDependencies.deleteAPIKey()' \
  'apiKeyStatus = .notConfigured'; do
  printf '%s\n' "$PERFORM_CLEAR_API_KEY_BODY" | rg -Fq "$invariant" \
    || fail "Delete-before-credential-release invariant missing: $invariant"
done
if printf '%s\n' "$PERFORM_CLEAR_API_KEY_BODY" \
  | rg -Fq 'try? await services.tunnel?.stop()'; then
  fail "Disconnect must not swallow remote webhook cleanup failure before Keychain deletion"
fi
require_fixed_order \
  "$PERFORM_CLEAR_API_KEY_BODY" \
  'try await services.tunnel?.stop()' \
  'try manusDependencies.deleteAPIKey()' \
  "Remote webhook cleanup must finish before the Manus credential is released"
require_fixed_order \
  "$PERFORM_CLEAR_API_KEY_BODY" \
  'try manusDependencies.deleteAPIKey()' \
  'apiKeyStatus = .notConfigured' \
  "TaskStore must publish Not Configured only after Keychain deletion succeeds"
[[ "$(rg -Fc 'try manusDependencies.deleteAPIKey()' "$TASK_STORE")" -eq 1 ]] \
  || fail "TaskStore must release the Manus credential through one reviewed post-cleanup path"

for file in \
  "$APP_TERMINATION_COORDINATOR" \
  "$APP_TERMINATION_TESTS"; do
  test -s "$file" || fail "Normal-Quit termination artifact missing: $file"
done
for invariant in \
  'public enum TaskStoreShutdownResult: Equatable, Sendable' \
  'case completed' \
  'case cleanupPending' \
  'private var shutdownOperation: ShutdownOperation?' \
  'private var shutdownRequested = false' \
  'private var bootstrapTask: Task<Void, Never>?' \
  'private var localHookStartTask: Task<Void, Never>?' \
  'public func shutdown() async -> TaskStoreShutdownResult'; do
  rg -Fq "$invariant" "$TASK_STORE" \
    || fail "Awaited TaskStore shutdown ownership invariant missing: $invariant"
done

TASK_STORE_SHUTDOWN_BODY="$(
  extract_braced_region "$TASK_STORE" 'public func shutdown() async -> TaskStoreShutdownResult'
)"
for invariant in \
  'if let shutdownOperation' \
  'return await shutdownOperation.task.value' \
  'shutdownRequested = true' \
  'cancelAllActionRequests()' \
  'manusConfigurationGeneration &+= 1' \
  'systemPowerGeneration &+= 1' \
  'let credentialRemoval = manusCredentialRemovalOperation' \
  'let sleepSuspension = manusSleepSuspension' \
  'let manusServices = detachManusServices()' \
  'let serverStart = localHookStartTask' \
  'let bootstrap = bootstrapTask' \
  'localHookServer = nil' \
  'localHookStartTask = nil' \
  'bootstrapTask = nil' \
  'localConnectors = [:]' \
  'bootstrap?.cancel()' \
  'try await credentialRemoval.task.value' \
  'await sleepSuspension?.task.value' \
  'await manusServices.poller?.stop()' \
  'try await manusServices.tunnel?.stop()' \
  'await serverStart?.value' \
  'await server?.stop()' \
  'await bootstrap?.value' \
  'return cleanupPending ? .cleanupPending : .completed' \
  'shutdownOperation = ShutdownOperation(task: task)' \
  'return await task.value'; do
  printf '%s\n' "$TASK_STORE_SHUTDOWN_BODY" | rg -Fq "$invariant" \
    || fail "Awaited TaskStore shutdown transaction missing: $invariant"
done
if printf '%s\n' "$TASK_STORE_SHUTDOWN_BODY" | rg -n 'Task\.detached|deleteAPIKey'; then
  fail "Normal Quit must neither detach cleanup nor release the Manus credential"
fi
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'shutdownRequested = true' \
  'let credentialRemoval = manusCredentialRemovalOperation' \
  "TaskStore shutdown must publish terminal state before capturing owned work"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'cancelAllActionRequests()' \
  'let task = Task<TaskStoreShutdownResult, Never>' \
  "TaskStore shutdown must resolve action continuations before its first cleanup task"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'let credentialRemoval = manusCredentialRemovalOperation' \
  'let manusServices = detachManusServices()' \
  "TaskStore shutdown must capture in-flight Disconnect before detaching current Manus services"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'try await credentialRemoval.task.value' \
  'await sleepSuspension?.task.value' \
  "TaskStore shutdown must join in-flight Disconnect before the sleep barrier"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'await sleepSuspension?.task.value' \
  'await manusServices.poller?.stop()' \
  "TaskStore shutdown must join sleep suspension before stopping Manus services"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'await manusServices.poller?.stop()' \
  'try await manusServices.tunnel?.stop()' \
  "TaskStore shutdown must join the poller before the tunnel"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'try await manusServices.tunnel?.stop()' \
  'await serverStart?.value' \
  "TaskStore shutdown must settle Manus cleanup before the local-listener start hop"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'await serverStart?.value' \
  'await server?.stop()' \
  "TaskStore shutdown must join listener startup before stopping the listener"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'await server?.stop()' \
  'await bootstrap?.value' \
  "TaskStore shutdown must join the retained bootstrap after every captured service stop"
require_fixed_order \
  "$TASK_STORE_SHUTDOWN_BODY" \
  'shutdownOperation = ShutdownOperation(task: task)' \
  'return await task.value' \
  "TaskStore must publish single-flight shutdown ownership before the caller awaits it"

TASK_STORE_BOOTSTRAP_BODY="$(
  extract_braced_region "$TASK_STORE" 'private func bootstrap() async {'
)"
for invariant in \
  'await manusDependencies.awaitBootstrapPermission()' \
  'try await store.open()' \
  '_ = await refreshStoredTaskHistory()' \
  'try await client.listTasks()' \
  'try await startServices(client: client)'; do
  printf '%s\n' "$TASK_STORE_BOOTSTRAP_BODY" | rg -Fq "$invariant" \
    || fail "Retained TaskStore bootstrap boundary missing: $invariant"
done
[[ "$(printf '%s\n' "$TASK_STORE_BOOTSTRAP_BODY" \
  | rg -Fc 'guard !shutdownRequested else { return }')" -ge 10 ]] \
  || fail "TaskStore bootstrap must re-check terminal state across every storage/provider suspension"
for invariant in \
  'guard !shutdownRequested else { throw CancellationError() }' \
  'guard !shutdownRequested, let server = localHookServer else { return }' \
  'guard !shutdownRequested else { return }'; do
  rg -Fq "$invariant" "$TASK_STORE" \
    || fail "Post-shutdown service-resurrection guard missing: $invariant"
done

for invariant in \
  'public enum AppTerminationMode: Equatable, Sendable' \
  'case owner' \
  'case yieldedDuplicate' \
  'case performanceQA' \
  'case hermeticLaunchSmoke' \
  'public enum AppTerminationDecision: Equatable, Sendable' \
  'case terminateNow' \
  'case terminateLater' \
  'public static let hardTimeoutNanoseconds: UInt64 = 2_000_000_000' \
  'private var terminationToken: UUID?' \
  'private var pendingReply: Reply?'; do
  rg -Fq "$invariant" "$APP_TERMINATION_COORDINATOR" \
    || fail "Tokenized AppKit termination invariant missing: $invariant"
done
if rg -n 'with(Task|ThrowingTask)Group' "$APP_TERMINATION_COORDINATOR"; then
  fail "The two-second Quit deadline must not wait for an unresponsive task-group child"
fi

TERMINATION_POLICY_BODY="$(
  extract_braced_region "$APP_TERMINATION_COORDINATOR" 'public static func decision('
)"
for invariant in \
  'case .owner:' \
  'return .terminateLater' \
  'case .yieldedDuplicate, .performanceQA, .hermeticLaunchSmoke:' \
  'return .terminateNow'; do
  printf '%s\n' "$TERMINATION_POLICY_BODY" | rg -Fq "$invariant" \
    || fail "AppKit termination-mode policy missing: $invariant"
done

TERMINATION_REQUEST_BODY="$(
  extract_braced_region "$APP_TERMINATION_COORDINATOR" 'public func requestTermination('
)"
for invariant in \
  'let decision = AppTerminationPolicy.decision(for: mode)' \
  'guard decision == .terminateLater else { return decision }' \
  'guard terminationToken == nil else {' \
  'let token = UUID()' \
  'terminationToken = token' \
  'pendingReply = reply' \
  'cleanupLauncher {' \
  'await cleanup()' \
  'self?.finish(token: token)' \
  'timeoutScheduler(timeoutNanoseconds)' \
  'return .terminateLater'; do
  printf '%s\n' "$TERMINATION_REQUEST_BODY" | rg -Fq "$invariant" \
    || fail "Tokenized finish-once termination request missing: $invariant"
done
require_fixed_order \
  "$TERMINATION_REQUEST_BODY" \
  'guard decision == .terminateLater else { return decision }' \
  'let token = UUID()' \
  "Termination bypasses must return before allocating cleanup ownership"
require_fixed_order \
  "$TERMINATION_REQUEST_BODY" \
  'terminationToken = token' \
  'cleanupLauncher {' \
  "Owner termination must publish its token before launching cleanup"

TERMINATION_FINISH_BODY="$(
  extract_braced_region "$APP_TERMINATION_COORDINATOR" 'private func finish(token: UUID) {'
)"
for invariant in \
  'guard terminationToken == token,' \
  'let reply = pendingReply else {' \
  'pendingReply = nil' \
  'reply()'; do
  printf '%s\n' "$TERMINATION_FINISH_BODY" | rg -Fq "$invariant" \
    || fail "Finish-once AppKit termination invariant missing: $invariant"
done
require_fixed_order \
  "$TERMINATION_FINISH_BODY" \
  'pendingReply = nil' \
  'reply()' \
  "Termination must consume the reply before calling AppKit"

APP_SHOULD_TERMINATE_BODY="$(
  extract_braced_region "$APP_ENTRY" 'func applicationShouldTerminate('
)"
for invariant in \
  'mode = .yieldedDuplicate' \
  'mode = .hermeticLaunchSmoke' \
  'mode = .owner' \
  'terminationCoordinator.requestTermination(' \
  '_ = await TaskStore.shared.shutdown()' \
  'sender.reply(toApplicationShouldTerminate: true)' \
  'return .terminateNow' \
  'return .terminateLater'; do
  printf '%s\n' "$APP_SHOULD_TERMINATE_BODY" | rg -Fq "$invariant" \
    || fail "AppDelegate normal-Quit integration missing: $invariant"
done
APP_WILL_TERMINATE_BODY="$(
  extract_braced_region "$APP_ENTRY" 'func applicationWillTerminate('
)"
if printf '%s\n' "$APP_WILL_TERMINATE_BODY" | rg -n 'TaskStore|shutdown\('; then
  fail "applicationWillTerminate must not launch a second TaskStore shutdown"
fi

LOCAL_HOOK_RETRY_BODY="$(
  extract_braced_region "$TASK_STORE" 'public func retryLocalHookService() {'
)"
for invariant in \
  'guard !shutdownRequested, let server = localHookServer else { return }' \
  'let precedingLifecycle = localHookStartTask' \
  'localHookStartTask = Task' \
  'await precedingLifecycle?.value' \
  '!self.shutdownRequested' \
  'self.localHookServer === server' \
  'await self.restartLocalHookServer(server)'; do
  printf '%s\n' "$LOCAL_HOOK_RETRY_BODY" | rg -Fq "$invariant" \
    || fail "Joinable local-listener retry invariant missing: $invariant"
done
require_fixed_order \
  "$LOCAL_HOOK_RETRY_BODY" \
  'localHookStartTask = Task' \
  'await precedingLifecycle?.value' \
  "Local-listener retries must be retained before joining prior lifecycle work"

for regression in \
  'testShippingHardTimeoutIsTwoSeconds' \
  'testCleanupCompletionRepliesBeforeHardTimeout' \
  'testHardTimeoutRepliesWhileCleanupIsStillPending' \
  'testCompletionAndTimeoutRaceCanReplyOnlyOnceInEitherOrder' \
  'testRepeatedOwnerRequestSharesTheFirstCleanupFlight' \
  'testAllThreeBypassModesTerminateNowInPurePolicy' \
  'testBypassModesScheduleNoCleanupTimeoutOrReply'; do
  rg -q "$regression" "$APP_TERMINATION_TESTS" \
    || fail "AppKit termination regression missing: $regression"
done
for regression in \
  'testShutdownWaitsForBlockedTunnelAndConcurrentCallersShareStop' \
  'testCancellingShutdownCallerDoesNotCancelSharedOperation' \
  'testShutdownJoinsBlockedBootstrapWithoutResurrectingServices' \
  'testShutdownSupersedesRegisteredDisconnectBeforeCleanupBodyStarts' \
  'testShutdownJoinsQueuedLocalRetryAndPreventsRestartAfterStop' \
  'testShutdownCleanupFailureRetainsCredentialAndMemoizesPendingResult' \
  'testShutdownJoinsInFlightDisconnectWithoutDeletingCredential' \
  'testShutdownMapsInFlightDisconnectCleanupFailureToPending' \
  'testShutdownJoinsSleepSuspensionBeforeStoppingTunnel'; do
  rg -q "$regression" "$MANUS_LIFECYCLE_TESTS" \
    || fail "TaskStore normal-Quit regression missing: $regression"
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
  'testCleanupFailureRetainsCredentialAndManagerForDisconnectRetry' \
  'testReplacementKeyCannotOverwriteCredentialBeforeOldWebhookCleanup' \
  'testReplacementSaveFailureRetiresOldServicesAndRetryCanConfigure' \
  'testReplacementSaveFailureWithoutPersistedCredentialAllowsDisconnect' \
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

for file in "$SINGLE_INSTANCE_GATE" "$SINGLE_INSTANCE_TESTS"; do
  test -s "$file" || fail "Trusted single-instance artifact missing: $file"
done
rg -Fq 'AppSingleInstanceGate.activateExistingInstanceIfNeeded()' "$APP_ENTRY" \
  || fail "Shipping App does not invoke the trusted single-instance gate"
rg -Fq 'Settings {' "$APP_ENTRY" \
  || fail "Shipping App is missing its inert Settings command scene"
rg -Fq 'EmptyView()' "$APP_ENTRY" \
  || fail "Shipping Settings command scene is not inert before launch arbitration"
if rg -Fq 'SettingsView()' "$APP_ENTRY"; then
  fail "Shipping root Scene must not construct TaskStore-backed SettingsView before launch arbitration"
fi
for invariant in \
  'maximumCandidateCount = 32' \
  'SecCodeCopyGuestWithAttributes' \
  'SecCodeCheckValidity' \
  'SecCodeCopyStaticCode' \
  'SecCodeCopySigningInformation' \
  'kSecCodeInfoIdentifier' \
  'identifier == expectedIdentifier' \
  'kSecCodeInfoFlags' \
  'SecCodeSignatureFlags' \
  'signatureFlags.contains(.adhoc)' \
  'anchor apple generic and identifier' \
  'SecRequirementCreateWithString' \
  'kSecCodeInfoTeamIdentifier' \
  'kSecCodeInfoUnique' \
  'case (.teamSigned, .hashBound), (.hashBound, .teamSigned)' \
  'identity.isTrustedPeer(of: currentCodeIdentity)' \
  'revalidatedIdentity == winner.codeIdentity'; do
  rg -Fq -- "$invariant" "$SINGLE_INSTANCE_GATE" \
    || fail "Trusted single-instance invariant missing: $invariant"
done
if rg -n 'executableURL|bundleURL|localizedName|launchDate|ProcessInfo\.processInfo\.environment|CommandLine\.arguments|Logger\(|os_log|NSLog|print\(' \
  "$SINGLE_INSTANCE_GATE"; then
  fail "Single-instance identity must not inspect candidate paths/process content or log code identity"
fi
for regression in \
  'testSameTeamCanTrustDifferentReleaseHashes' \
  'testDifferentTeamsCannotArbitrate' \
  'testAdHocCopiesRequireTheSameNonemptyCDHash' \
  'testTeamAndAdHocIdentitiesNeverMix' \
  'testBundleIdentifierMustMatchExactly' \
  'testDuplicateUnorderedCandidatesResolveEachEligiblePIDAtMostOnce' \
  'testCandidateFloodFailsOpenWithoutResolvingIdentity' \
  'testTrustedWinnerIsRevalidatedThenActivatedExactlyOnce' \
  'testActivationFailureKeepsCurrentInstanceRunning' \
  'testIdentityDriftBeforeActivationFailsOpen' \
  'testCandidateDisappearingBeforeActivationFailsOpen' \
  'testSecurityResolverRejectsInvalidProcessIdentifiers' \
  'testSigningClassifierRequiresExplicitAdHocFlagForHashBinding' \
  'testSigningClassifierRequiresAppleAnchoredTeamSignature' \
  'testSigningClassifierRejectsMixedOrMalformedIdentity' \
  'testSigningClassifierRejectsMissingIdentityFields' \
  'testSameTeamIdentityDriftStillFailsRevalidation'; do
  rg -Fq -- "$regression" "$SINGLE_INSTANCE_TESTS" \
    || fail "Trusted single-instance regression missing: $regression"
done

./scripts/ci/verify-localizations.sh
./scripts/ci/verify-legal-data-flows.sh
./scripts/ci/verify-ci-diagnostics.sh
./scripts/ci/verify-manus-live-acceptance-evidence.sh
./scripts/ci/verify-codex-live-approval-evidence.sh
./scripts/ci/verify-codex-live-decision-evidence.sh
./scripts/ci/verify-system-accessibility-evidence.sh
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
