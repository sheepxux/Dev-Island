import XCTest
@testable import IslandAppLib
import IslandCore

final class AgentConnectionIndicatorPresentationTests: XCTestCase {
    func testLocalListenerIsNotMisreportedAsAllAgentsDisconnected() {
        let snapshot = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .listening,
            apiKeyStatus: .notConfigured,
            manusStatus: .disconnected,
            language: .english
        )

        XCTAssertEqual(snapshot.state, .available)
        XCTAssertEqual(snapshot.accessibilityLabel, "Agent connections")
        XCTAssertEqual(
            snapshot.accessibilityValue,
            "Local agents: Ready, Manus: Not connected"
        )
        XCTAssertEqual(snapshot.help, snapshot.accessibilityValue)
    }

    func testConfiguredButDisconnectedManusNeedsAttentionWithoutHidingLocalReadiness() {
        let snapshot = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            manusStatus: .disconnected,
            language: .english
        )

        XCTAssertEqual(snapshot.state, .needsAttention)
        XCTAssertEqual(
            snapshot.accessibilityValue,
            "Local agents: Ready, Manus: Disconnected"
        )
    }

    func testTransitioningChannelWinsOverAvailableChannel() {
        let snapshot = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            manusStatus: .reconnecting,
            language: .english
        )

        XCTAssertEqual(snapshot.state, .transitioning)
        XCTAssertEqual(
            snapshot.accessibilityValue,
            "Local agents: Ready, Manus: Reconnecting…"
        )
    }

    func testLocalLifecycleMapsToTransitionAndAttentionStates() {
        let starting = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .starting,
            apiKeyStatus: .notConfigured,
            manusStatus: .disconnected,
            language: .english
        )
        let retrying = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .retrying(attempt: 2, limit: 5),
            apiKeyStatus: .notConfigured,
            manusStatus: .disconnected,
            language: .english
        )
        let unavailable = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .unavailable,
            apiKeyStatus: .notConfigured,
            manusStatus: .disconnected,
            language: .english
        )

        XCTAssertEqual(starting.state, .transitioning)
        XCTAssertEqual(retrying.state, .transitioning)
        XCTAssertEqual(
            retrying.accessibilityValue,
            "Local agents: Reconnecting (2/5), Manus: Not connected"
        )
        XCTAssertEqual(unavailable.state, .needsAttention)
        XCTAssertEqual(
            unavailable.accessibilityValue,
            "Local agents: Offline, Manus: Not connected"
        )
    }

    func testManusCanBeTheOnlyAvailableChannel() {
        let snapshot = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .stopped,
            apiKeyStatus: .valid,
            manusStatus: .connected,
            language: .english
        )

        XCTAssertEqual(snapshot.state, .available)
        XCTAssertEqual(
            snapshot.accessibilityValue,
            "Local agents: Stopped, Manus: Connected"
        )
    }

    func testNoConfiguredChannelIsQuietlyInactive() {
        let snapshot = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .stopped,
            apiKeyStatus: .notConfigured,
            manusStatus: .disconnected,
            language: .english
        )

        XCTAssertEqual(snapshot.state, .inactive)
        XCTAssertEqual(
            snapshot.accessibilityValue,
            "Local agents: Stopped, Manus: Not connected"
        )
    }

    func testProviderReasonNeverReachesTooltipOrAccessibility() {
        let privateReason = "token=private-provider-detail"
        let snapshot = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            manusStatus: .degraded(reason: privateReason),
            language: .simplifiedChinese
        )

        XCTAssertEqual(snapshot.state, .needsAttention)
        XCTAssertEqual(snapshot.accessibilityLabel, "Agent 连接")
        XCTAssertEqual(
            snapshot.accessibilityValue,
            "本地 Agent：已就绪，Manus：仅轮询"
        )
        XCTAssertFalse(snapshot.help.contains(privateReason))
        XCTAssertFalse(snapshot.accessibilityValue.contains(privateReason))
    }
}
