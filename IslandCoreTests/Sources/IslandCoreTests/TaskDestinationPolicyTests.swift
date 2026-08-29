import Foundation
import XCTest
@testable import IslandCore

final class TaskDestinationPolicyTests: XCTestCase {
    func testManusDestinationAcceptsOnlyExactReviewedTaskRoute() {
        let task = makeTask(
            id: "task_ABC-123",
            source: "manus",
            url: "https://manus.im/app/task_ABC-123"
        )

        XCTAssertEqual(
            TaskDestinationPolicy.destination(for: task)?.absoluteString,
            "https://manus.im/app/task_ABC-123"
        )
    }

    func testManusDestinationRejectsUntrustedSchemesOriginsAndRouteSyntax() {
        let rejected = [
            "file:///tmp/project",
            "javascript:alert(1)",
            "dev-island://task/task_ABC-123",
            "http://manus.im/app/task_ABC-123",
            "https://evil.example/app/task_ABC-123",
            "https://user@manus.im/app/task_ABC-123",
            "https://manus.im:443/app/task_ABC-123",
            "https://manus.im/app/another-task",
            "https://manus.im/app/task_ABC-123?next=https://evil.example",
            "https://manus.im/app/task_ABC-123#fragment",
            "https://manus.im/app/task%5FABC-123",
            "https://manus.im/app/task_ABC-123/",
        ]

        for url in rejected {
            let task = makeTask(id: "task_ABC-123", source: "manus", url: url)
            XCTAssertNil(TaskDestinationPolicy.destination(for: task), url)
        }
    }

    func testLocalDestinationAcceptsExistingOrdinaryDirectoryOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-destination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let task = makeTask(id: "local", source: "codex", url: root.absoluteString)
        XCTAssertEqual(
            TaskDestinationPolicy.destination(for: task)?.standardizedFileURL,
            root.standardizedFileURL
        )
    }

    func testLocalDestinationRejectsFilesBundlesRemoteHostsAndMissingPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-destination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("run.command")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("echo unsafe".utf8)))
        let app = root.appendingPathComponent("Untrusted.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)

        let rejected = [
            file.absoluteString,
            app.absoluteString,
            root.appendingPathComponent("missing", isDirectory: true).absoluteString,
            "file://remote.example/tmp/project",
            "https://example.invalid/project",
            "dev-island://project",
        ]
        for url in rejected {
            let task = makeTask(id: "local", source: "codex", url: url)
            XCTAssertNil(TaskDestinationPolicy.destination(for: task), url)
        }
    }

    @MainActor
    func testTaskStoreNeverCallsOpenerForRejectedOrAmbiguousDestinations() {
        let unsafe = makeTask(id: "shared", source: "manus", url: "https://evil.example/app/shared")
        let second = makeTask(id: "shared", source: "codex", url: "file:///path/that/does/not/exist")
        var opened: [URL] = []
        let store = TaskStore.destinationTestStore(tasks: [unsafe, second]) { url in
            opened.append(url)
            return true
        }

        store.openTask(unsafe)
        store.openTaskInBrowser(source: "manus", id: "shared")
        store.openTaskInBrowser(id: "shared")

        XCTAssertTrue(opened.isEmpty)
    }

    @MainActor
    func testTaskStoreCallsOpenerOnceForValidatedManusDestination() {
        let task = makeTask(id: "task_1", source: "manus", url: "https://manus.im/app/task_1")
        var opened: [URL] = []
        let store = TaskStore.destinationTestStore(tasks: [task]) { url in
            opened.append(url)
            return true
        }

        store.openTaskInBrowser(source: "manus", id: "task_1")

        XCTAssertEqual(opened.map(\.absoluteString), ["https://manus.im/app/task_1"])
    }

    private func makeTask(id: String, source: String, url: String) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: "Task",
            status: .running,
            createdAt: .now,
            updatedAt: .now,
            taskURL: url
        )
    }
}
