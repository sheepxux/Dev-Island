import XCTest
@testable import IslandCore

final class TaskIdentityTests: XCTestCase {
    func testIdentityIncludesSource() {
        let codex = task(source: "codex")
        let cursor = task(source: "cursor")

        XCTAssertNotEqual(codex.identity, cursor.identity)
        XCTAssertEqual(Set([codex.identity, cursor.identity]).count, 2)
    }

    @MainActor
    func testStoreResolvesSameSessionIDBySource() {
        let codex = task(source: "codex")
        let cursor = task(source: "cursor")
        let store = TaskStore.mock(tasks: [codex, cursor])

        XCTAssertEqual(store.task(with: codex.identity)?.source, "codex")
        XCTAssertEqual(store.task(with: cursor.identity)?.source, "cursor")
    }

    private func task(source: String) -> AgentTask {
        AgentTask(
            id: "shared-session-id",
            source: source,
            title: source,
            status: .running,
            createdAt: .now,
            updatedAt: .now,
            taskURL: "file:///tmp/\(source)"
        )
    }
}
