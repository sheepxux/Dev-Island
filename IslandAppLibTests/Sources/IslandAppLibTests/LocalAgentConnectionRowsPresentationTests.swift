import XCTest
import IslandCore
@testable import IslandAppLib

final class LocalAgentConnectionRowsPresentationTests: XCTestCase {
    func testEveryDiagnosticStateLandsInExactlyOneGroupWithOneAction() {
        XCTAssertEqual(LocalAgentRowPresentation.group(for: .connected), .connected)
        XCTAssertEqual(LocalAgentRowPresentation.group(for: .configured), .needsAttention)
        XCTAssertEqual(LocalAgentRowPresentation.group(for: .updateRequired), .needsAttention)
        XCTAssertEqual(LocalAgentRowPresentation.group(for: .disconnected), .notConnected)
        XCTAssertNil(LocalAgentRowPresentation.group(for: nil), "unknown rows do not jump between groups")

        XCTAssertEqual(LocalAgentRowPresentation.action(for: .connected), .expand)
        XCTAssertEqual(LocalAgentRowPresentation.action(for: .configured), .authorize)
        XCTAssertEqual(LocalAgentRowPresentation.action(for: .updateRequired), .update)
        XCTAssertEqual(LocalAgentRowPresentation.action(for: .disconnected), .connect)
    }

    func testGroupsKeepRegistryOrderInsideAndReadingOrderBetween() {
        let all = LocalAgentRegistry.all
        let states: [String: LocalAgentHookConnectionState] = Dictionary(
            uniqueKeysWithValues: all.enumerated().map { index, descriptor in
                let state: LocalAgentHookConnectionState
                switch index % 4 {
                case 0: state = .disconnected
                case 1: state = .connected
                case 2: state = .updateRequired
                default: state = .configured
                }
                return (descriptor.source, state)
            }
        )
        let grouped = LocalAgentRowPresentation.grouped(all, states: states)

        XCTAssertEqual(grouped.map(\.group), [.needsAttention, .connected, .notConnected, .preview])
        for entry in grouped {
            let sources = entry.descriptors.map(\.source)
            let registryOrder = all.map(\.source).filter(sources.contains)
            XCTAssertEqual(sources, registryOrder, "\(String(describing: entry.group))")
        }
        XCTAssertEqual(grouped.flatMap(\.descriptors).count, all.count, "no row is lost or duplicated")
    }

    func testIncompleteSnapshotKeepsPreviewSeparateWhileStableRowsLoad() {
        let all = LocalAgentRegistry.all
        let partial = [all[0].source: LocalAgentHookConnectionState.connected]
        let grouped = LocalAgentRowPresentation.grouped(all, states: partial)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertNil(grouped[0].group)
        XCTAssertEqual(grouped[0].descriptors.map(\.source), all.filter { $0.releaseStage == .stable }.map(\.source))
        XCTAssertEqual(grouped[1].group, .preview)
        XCTAssertTrue(grouped[1].descriptors.allSatisfy { $0.releaseStage == .preview })
    }

    func testStatusLinesDescribeInstalledCapabilityWithoutLeakingTrustInternals() {
        let codex = LocalAgentDescriptor.codex
        let claude = LocalAgentDescriptor.claudeCode
        for language in [DevIslandLanguage.english, .simplifiedChinese] {
            for state in [LocalAgentHookConnectionState.connected, .configured, .updateRequired, .disconnected] {
                let line = LocalAgentRowPresentation.statusLine(state: state, descriptor: codex, language: language)
                XCTAssertFalse(line.isEmpty)
                XCTAssertFalse(line.lowercased().contains("hash"), line)
                XCTAssertFalse(line.contains("trusted_hash"), line)
            }
        }
        let english = LocalAgentRowPresentation.statusLine(state: .connected, descriptor: claude, language: .english)
        let chinese = LocalAgentRowPresentation.statusLine(state: .connected, descriptor: claude, language: .simplifiedChinese)
        XCTAssertNotEqual(english, chinese)
        XCTAssertEqual(english, "Task and approval access configured")
        XCTAssertEqual(
            LocalAgentRowPresentation.statusLine(state: nil, descriptor: claude, language: .english),
            "Checking…"
        )
    }

    func testSessionOnlyConnectorDoesNotPromiseApprovalSupportDuringSetup() {
        let cursor = LocalAgentRegistry.all.first { $0.source == "cursor" }!
        for state in [LocalAgentHookConnectionState.disconnected, .updateRequired, .connected] {
            let copy = LocalAgentRowPresentation.statusLine(state: state, descriptor: cursor, language: .english)
            XCTAssertFalse(copy.lowercased().contains("approval"), copy)
        }
    }

    func testPreviewScopeRemainsExplicitBeforeAndAfterSetup() {
        let preview = LocalAgentRegistry.all.first { $0.releaseStage == .preview }!
        for state in [LocalAgentHookConnectionState.disconnected, .configured, .updateRequired, .connected] {
            let copy = LocalAgentRowPresentation.statusLine(state: state, descriptor: preview, language: .english)
            XCTAssertTrue(copy.lowercased().contains("simulat"), copy)
        }
    }

    func testSummaryListsOnlyNonZeroCountsInReadingOrder() {
        XCTAssertEqual(
            LocalAgentRowPresentation.summary(connected: 4, needsAttention: 1, notConnected: 3, language: .english),
            "4 set up · 1 need action · 3 not connected"
        )
        XCTAssertEqual(
            LocalAgentRowPresentation.summary(connected: 0, needsAttention: 0, notConnected: 2, language: .english),
            "2 not connected"
        )
        XCTAssertEqual(
            LocalAgentRowPresentation.summary(connected: 4, needsAttention: 1, notConnected: 3, language: .simplifiedChinese),
            "4 个已配置 · 1 个需要处理 · 3 个未连接"
        )
        XCTAssertEqual(
            LocalAgentRowPresentation.summary(connected: 0, needsAttention: 0, notConnected: 0, language: .english),
            "Checking local Agents…"
        )
    }

    func testPreviewSetupDoesNotInflateUsableConnectionCount() {
        let states = Dictionary(uniqueKeysWithValues: LocalAgentRegistry.all.map { ($0.source, LocalAgentHookConnectionState.connected) })
        XCTAssertEqual(LocalAgentRowPresentation.summary(
            descriptors: LocalAgentRegistry.all, states: states, language: .english
        ), "3 set up")
        let groups = LocalAgentRowPresentation.grouped(LocalAgentRegistry.all, states: states)
        XCTAssertEqual(groups.first?.descriptors.count, 3)
        XCTAssertEqual(groups.last?.group, .preview)
        XCTAssertEqual(groups.last?.descriptors.count, 5)
    }

    func testSnapshotSummaryFoldsConfiguredAndUpdateRequiredIntoAttention() {
        let snapshot = LocalAgentHookHealthSnapshot(agents: [
            .init(source: "a", displayName: "A", state: .connected),
            .init(source: "b", displayName: "B", state: .configured),
            .init(source: "c", displayName: "C", state: .updateRequired),
            .init(source: "d", displayName: "D", state: .disconnected),
        ])
        XCTAssertEqual(
            LocalAgentRowPresentation.summary(snapshot, language: .english),
            "1 set up · 2 need action · 1 not connected"
        )
    }
}
