import XCTest
@testable import IslandAppLib
import IslandCore

final class ManusConnectionStatusPresentationTests: XCTestCase {
    func testConfiguredStatesDistinguishVerifiedRealtimePollingAndFailure() {
        XCTAssertEqual(
            message(.connected),
            "Verified realtime + polling fallback"
        )
        XCTAssertEqual(
            message(.degraded(reason: ManusRealtimeTrust.pollingOnlyReason)),
            "Polling only — checking every minute"
        )
        XCTAssertEqual(
            message(.degraded(reason: "provider response /Users/customer/private")),
            "Connection unavailable — reconnect to retry"
        )
        XCTAssertEqual(
            message(.degraded(reason: ManusCredentialRemovalPolicy.cleanupPendingReason)),
            "Remote callback cleanup pending — retry Disconnect"
        )
    }

    func testUnknownDegradedReasonNeverReachesTheUser() {
        let secret = "sk-private-provider-reason /Users/customer/Secret"
        let rendered = message(.degraded(reason: secret))

        XCTAssertFalse(rendered.contains(secret))
        XCTAssertFalse(rendered.contains("sk-private"))
        XCTAssertFalse(rendered.contains("/Users/customer"))
    }

    func testPollingFallbackIsFullyLocalized() {
        XCTAssertEqual(
            ManusConnectionStatusPresentation.message(
                apiKeyStatus: .valid,
                connectionStatus: .degraded(
                    reason: ManusRealtimeTrust.pollingOnlyReason
                ),
                language: .simplifiedChinese
            ),
            "仅轮询 — 每分钟检查一次"
        )
        XCTAssertEqual(
            ManusConnectionStatusPresentation.message(
                apiKeyStatus: .valid,
                connectionStatus: .degraded(
                    reason: ManusCredentialRemovalPolicy.cleanupPendingReason
                ),
                language: .simplifiedChinese
            ),
            "远端回调清理待完成 — 请再次断开"
        )
    }

    func testCredentialStatesRemainActionable() {
        XCTAssertEqual(
            ManusConnectionStatusPresentation.message(
                apiKeyStatus: .invalid,
                connectionStatus: .disconnected,
                language: .english
            ),
            "Stored key is invalid"
        )
        XCTAssertEqual(
            ManusConnectionStatusPresentation.message(
                apiKeyStatus: .notConfigured,
                connectionStatus: .disconnected,
                language: .english
            ),
            "Not connected — paste an API key below"
        )
    }

    private func message(_ status: ConnectionStatus) -> String {
        ManusConnectionStatusPresentation.message(
            apiKeyStatus: .valid,
            connectionStatus: status,
            language: .english
        )
    }
}
