import XCTest
@testable import IslandAppLib

final class LocalAgentInstallationPresentationTests: XCTestCase {
    func testInitialRefreshResolvesCheckingState() {
        var state = LocalAgentInstallationOperationState()
        let id = UUID()

        XCTAssertEqual(state.installationState, .checking)
        XCTAssertEqual(state.beginRefresh(id: id), id)
        XCTAssertTrue(state.isBusy)
        XCTAssertFalse(state.isApplyingChange)

        XCTAssertTrue(state.accept(.updateRequired, for: id))
        XCTAssertEqual(state.installationState, .updateRequired)
        XCTAssertFalse(state.isBusy)
    }

    func testNewRefreshRejectsLateOlderResult() {
        var state = LocalAgentInstallationOperationState(
            installationState: .current
        )
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(state.beginRefresh(id: first), first)
        XCTAssertEqual(state.beginRefresh(id: second), second)
        XCTAssertFalse(state.accept(.absent, for: first))
        XCTAssertEqual(state.installationState, .current)
        XCTAssertTrue(state.accept(.updateRequired, for: second))
        XCTAssertEqual(state.installationState, .updateRequired)
    }

    func testMutationIsExclusiveAndOwnsCompletion() {
        var state = LocalAgentInstallationOperationState(
            installationState: .updateRequired
        )
        let mutation = UUID()

        XCTAssertEqual(state.beginMutation(.update, id: mutation), mutation)
        XCTAssertTrue(state.isApplyingChange)
        XCTAssertEqual(state.activeMutation, .update)
        XCTAssertNil(state.beginRefresh(id: UUID()))
        XCTAssertNil(state.beginMutation(.disable, id: UUID()))
        XCTAssertTrue(state.accept(.current, for: mutation))
        XCTAssertEqual(state.installationState, .current)
        XCTAssertFalse(state.isBusy)
    }

    func testInvalidationRejectsLateMutationResult() {
        var state = LocalAgentInstallationOperationState(
            installationState: .absent
        )
        let mutation = UUID()

        XCTAssertEqual(state.beginMutation(.enable, id: mutation), mutation)
        state.invalidate()

        XCTAssertFalse(state.accept(.current, for: mutation))
        XCTAssertEqual(state.installationState, .absent)
        XCTAssertFalse(state.isBusy)
    }

    func testOperationsDeclareExpectedStateAndProgressCopy() {
        XCTAssertEqual(LocalAgentConfigurationOperation.enable.expectedState, .current)
        XCTAssertEqual(LocalAgentConfigurationOperation.update.expectedState, .current)
        XCTAssertEqual(LocalAgentConfigurationOperation.disable.expectedState, .absent)
        XCTAssertEqual(LocalAgentConfigurationOperation.enable.progressLocalizationKey, "Enabling…")
        XCTAssertEqual(LocalAgentConfigurationOperation.update.progressLocalizationKey, "Updating…")
        XCTAssertEqual(LocalAgentConfigurationOperation.disable.progressLocalizationKey, "Disabling…")
    }

    @MainActor
    func testConfigurationExecutorLeavesTheMainThread() async {
        XCTAssertTrue(Thread.isMainThread)

        let workerRanOnMainThread = await LocalAgentConfigurationExecutor.run(
            priority: .userInitiated
        ) {
            Thread.isMainThread
        }

        XCTAssertFalse(workerRanOnMainThread)
        XCTAssertTrue(Thread.isMainThread)
    }
}
