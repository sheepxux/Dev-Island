import XCTest
@testable import IslandAppLib

final class LocalAgentConnectionsPresentationTests: XCTestCase {
    func testAgentMutationOwnsTheSurfaceUntilItsExactCompletion() throws {
        var state = LocalAgentConnectionsOperationState()
        let operationID = UUID()

        XCTAssertEqual(
            state.beginAgentMutation(
                source: "codex",
                operation: .enable,
                id: operationID
            ),
            operationID
        )
        XCTAssertTrue(state.isMutating)
        XCTAssertEqual(
            state.activeMutation,
            .agent(source: "codex", operation: .enable)
        )
        XCTAssertNil(state.beginDisconnectAll())
        XCTAssertNil(state.beginAgentMutation(source: "claude-code", operation: .disable))
        XCTAssertFalse(state.completeAgentMutation(UUID()))
        XCTAssertTrue(state.completeAgentMutation(operationID))
        XCTAssertFalse(state.isMutating)
        XCTAssertEqual(state.completionGeneration, 1)
    }

    func testDisconnectAllExcludesEveryAgentMutationAcrossPaneChanges() throws {
        var settingsOwnedState = LocalAgentConnectionsOperationState()
        let operationID = UUID()

        XCTAssertEqual(settingsOwnedState.beginDisconnectAll(id: operationID), operationID)
        XCTAssertTrue(settingsOwnedState.isDisconnectingAll)

        // A newly constructed Agent pane observes the same Settings-owned
        // value instead of initializing an idle local copy.
        let rebuiltPaneState = settingsOwnedState
        XCTAssertTrue(rebuiltPaneState.isMutating)
        XCTAssertNil(settingsOwnedState.beginAgentMutation(
            source: "codex",
            operation: .update
        ))

        XCTAssertTrue(settingsOwnedState.completeDisconnectAll(
            .disconnected(count: 2),
            for: operationID
        ))
        XCTAssertEqual(settingsOwnedState.maintenanceOutcome, .disconnected(count: 2))
        XCTAssertEqual(settingsOwnedState.completionGeneration, 1)
    }

    func testLateOrWrongKindCompletionCannotReleaseAnotherMutation() throws {
        var state = LocalAgentConnectionsOperationState()
        let operationID = UUID()
        let staleID = UUID()

        XCTAssertEqual(
            state.beginAgentMutation(
                source: "qwen-code",
                operation: .disable,
                id: operationID
            ),
            operationID
        )
        XCTAssertFalse(state.completeDisconnectAll(.failed, for: operationID))
        XCTAssertFalse(state.cancel(staleID))
        XCTAssertTrue(state.isMutating)
        XCTAssertTrue(state.completeAgentMutation(operationID))
    }

    func testBeginningANewMutationClearsStaleMaintenanceFeedback() throws {
        var state = LocalAgentConnectionsOperationState()
        let disconnectID = try XCTUnwrap(state.beginDisconnectAll())
        XCTAssertTrue(state.completeDisconnectAll(.noChanges, for: disconnectID))
        XCTAssertEqual(state.maintenanceOutcome, .noChanges)

        XCTAssertNotNil(state.beginAgentMutation(source: "codex", operation: .enable))
        XCTAssertNil(state.maintenanceOutcome)
    }
}
