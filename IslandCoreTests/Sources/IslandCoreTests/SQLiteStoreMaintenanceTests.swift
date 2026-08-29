import Darwin
import Foundation
import SQLite
import XCTest
@testable import IslandCore

final class SQLiteStoreMaintenanceTests: XCTestCase {

    @MainActor
    func testTaskStoreClearsPersistenceWithoutInterruptingActiveSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-live-clear-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sqlite = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))
        let active = task(id: "active", status: .waiting)

        try await sqlite.open()
        try await sqlite.insertOrReplace(task: active)
        try await sqlite.insertProgressEvent(
            source: active.source,
            taskId: active.id,
            type: "waiting",
            message: "private waiting content"
        )
        let store = TaskStore.maintenanceTestStore(sqliteStore: sqlite, tasks: [active])

        let cleared = await store.clearStoredTaskHistory()
        XCTAssertTrue(cleared)
        XCTAssertEqual(store.tasks, [active], "active in-memory session must stay visible")
        let counts = try await sqlite.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 0, progressEvents: 0))
    }

    @MainActor
    func testTaskStorePersistsLocalSnapshotsWithoutRestoringThemIntoLiveIsland() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-local-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sqlite = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))
        let liveManus = task(id: "live", status: .running)
        let finishedCodex = task(
            id: "finished",
            source: "codex",
            status: .completed
        )

        try await sqlite.open()
        let store = TaskStore.maintenanceTestStore(
            sqliteStore: sqlite,
            tasks: [liveManus]
        )
        await store.applyLocalSnapshot(source: "codex", [finishedCodex])
        let refreshed = await store.refreshStoredTaskHistory()
        XCTAssertTrue(refreshed)

        XCTAssertEqual(store.storedTaskHistory.map(\.identity), [finishedCodex.identity])
        XCTAssertEqual(store.storedTaskHistoryTotalCount, 1)
        XCTAssertEqual(store.storedTaskHistoryStatus, .available)
        XCTAssertEqual(
            Set(store.tasks.map(\.identity)),
            [liveManus.identity, finishedCodex.identity]
        )

        // Loading persistence is read-only: it must not create a second live
        // session, fire a transition, or replace the current task list.
        var transitions = 0
        store.onTaskTransition = { _ in transitions += 1 }
        let refreshedAgain = await store.refreshStoredTaskHistory()
        XCTAssertTrue(refreshedAgain)
        XCTAssertEqual(transitions, 0)
        XCTAssertEqual(store.tasks.count, 2)
    }

    func testClearStoredHistoryIsTransactionalAndKeepsDatabaseUsable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))

        try await store.open()
        try await store.insertOrReplace(task: task(id: "one", status: .completed))
        try await store.insertOrReplace(task: task(id: "two", status: .waiting))
        try await store.insertProgressEvent(
            source: "manus",
            taskId: "one",
            type: "thinking",
            message: "private progress content"
        )
        try await store.insertProgressEvent(
            source: "manus",
            taskId: "two",
            type: "tool",
            message: "another private progress event"
        )

        var counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 2, progressEvents: 2))

        try await store.clearStoredHistory()
        counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 0, progressEvents: 0))

        // Clearing rows must not require an app relaunch before persistence
        // works again.
        try await store.insertOrReplace(task: task(id: "after-clear", status: .running))
        counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 1, progressEvents: 0))
    }

    func testClearOnAnEmptyDatabaseIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-empty-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))

        try await store.open()
        try await store.clearStoredHistory()
        try await store.clearStoredHistory()

        let counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 0, progressEvents: 0))
    }

    func testHistoryKeepsSameVendorLocalIDAcrossAgentSources() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-composite-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))

        try await store.open()
        try await store.insertOrReplace(task: task(
            id: "shared-session",
            source: "claude-code",
            status: .completed
        ))
        try await store.insertOrReplace(task: task(
            id: "shared-session",
            source: "codex",
            status: .failed
        ))

        let page = try await store.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(Set(page.tasks.map(\.identity)), [
            TaskIdentity(source: "claude-code", id: "shared-session"),
            TaskIdentity(source: "codex", id: "shared-session"),
        ])
    }

    func testEphemeralTerminalJumpContextIsNeverPersisted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-private-jump-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))
        var live = task(id: "terminal", source: "codex", status: .running)
        live.jumpContext = try XCTUnwrap(SessionJumpContext(
            terminalProgram: "iTerm.app",
            tty: "ttys003",
            tmuxEnvironment: "/private/tmp/tmux-501/default,9,0",
            tmuxPane: "%2"
        ))

        try await store.open()
        try await store.insertOrReplace(task: live)
        let page = try await store.loadTaskHistory(limit: 200)

        XCTAssertEqual(page.tasks.first?.identity, live.identity)
        XCTAssertNil(page.tasks.first?.jumpContext)
    }

    func testLegacySchemaMigratesWithoutLosingRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-legacy-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")

        do {
            let legacy = try Connection(databaseURL.path)
            try legacy.run("""
                CREATE TABLE "tasks" (
                    "id" TEXT PRIMARY KEY NOT NULL,
                    "source" TEXT NOT NULL,
                    "title" TEXT NOT NULL,
                    "status" TEXT NOT NULL,
                    "current_phase" TEXT,
                    "created_at" REAL NOT NULL,
                    "updated_at" REAL NOT NULL,
                    "task_url" TEXT NOT NULL,
                    "waiting_message" TEXT
                )
                """)
            try legacy.run("""
                CREATE TABLE "progress_events" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    "task_id" TEXT NOT NULL,
                    "type" TEXT NOT NULL,
                    "message" TEXT NOT NULL,
                    "recorded_at" REAL NOT NULL
                )
                """)
            try legacy.run(
                """
                INSERT INTO "tasks"
                    ("id", "source", "title", "status", "created_at",
                     "updated_at", "task_url")
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                "legacy-session",
                "manus",
                "Legacy task",
                "completed",
                1_700_000_000.0,
                1_700_000_100.0,
                "https://manus.im/task/legacy-session"
            )
            try legacy.run(
                """
                INSERT INTO "progress_events"
                    ("task_id", "type", "message", "recorded_at")
                VALUES (?, ?, ?, ?)
                """,
                "legacy-session",
                "thinking",
                "legacy progress",
                1_700_000_050.0
            )
        }

        let store = SQLiteStore(databaseURL: databaseURL)
        try await store.open()
        var page = try await store.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.tasks.first?.identity, TaskIdentity(
            source: "manus",
            id: "legacy-session"
        ))
        let migratedCounts = try await store.storedRecordCounts()
        XCTAssertEqual(migratedCounts, .init(tasks: 1, progressEvents: 1))

        // Proves the migrated primary key is product-wide, not vendor-local.
        try await store.insertOrReplace(task: task(
            id: "legacy-session",
            source: "codex",
            status: .running
        ))
        try await store.insertProgressEvent(
            source: "codex",
            taskId: "legacy-session",
            type: "running",
            message: "new progress"
        )
        page = try await store.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.totalCount, 2)
        let finalCounts = try await store.storedRecordCounts()
        XCTAssertEqual(finalCounts, .init(tasks: 2, progressEvents: 2))
    }

    func testHistoryPageIsNewestFirstAndReportsRowsBeyondBound() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-bounded-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))

        try await store.open()
        for index in 1...3 {
            var record = task(id: "task-\(index)", status: .completed)
            record.updatedAt = Date(timeIntervalSince1970: TimeInterval(index))
            try await store.insertOrReplace(task: record)
        }

        let page = try await store.loadTaskHistory(limit: 2)
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertEqual(page.tasks.map(\.id), ["task-3", "task-2"])
    }

    func testRetentionKeepsNewestTasksAndDeletesOrphanedProgress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-history-retention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(
            databaseURL: directory.appendingPathComponent("tasks.sqlite"),
            taskRetentionLimit: 3,
            progressRetentionLimit: 10
        )

        try await store.open()
        for index in 0..<4 {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(index))
            let record = task(
                id: "task-\(index)",
                status: .completed,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try await store.insertOrReplace(task: record)
            if index == 0 {
                try await store.insertProgressEvent(
                    source: record.source,
                    taskId: record.id,
                    type: "thinking",
                    message: "private oldest progress"
                )
            }
        }

        let page = try await store.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertEqual(page.tasks.map(\.id), ["task-3", "task-2", "task-1"])
        let counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 3, progressEvents: 0))
    }

    func testProgressRetentionIsFiniteAndDeterministic() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-progress-retention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(
            databaseURL: directory.appendingPathComponent("tasks.sqlite"),
            taskRetentionLimit: 2,
            progressRetentionLimit: 3
        )
        let retainedTask = task(id: "retained", status: .running)

        try await store.open()
        try await store.insertOrReplace(task: retainedTask)
        for index in 0..<5 {
            try await store.insertProgressEvent(
                source: retainedTask.source,
                taskId: retainedTask.id,
                type: "step-\(index)",
                message: "bounded progress \(index)"
            )
        }

        let counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 1, progressEvents: 3))
    }

    func testOpeningExistingDatabaseAppliesCurrentRetentionLimits() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-open-retention-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")

        do {
            let writer = SQLiteStore(
                databaseURL: databaseURL,
                taskRetentionLimit: 10,
                progressRetentionLimit: 10
            )
            try await writer.open()
            for index in 0..<5 {
                var record = task(id: "task-\(index)", status: .completed)
                record.updatedAt = Date(timeIntervalSince1970: TimeInterval(index))
                try await writer.insertOrReplace(task: record)
            }
        }

        let reader = SQLiteStore(
            databaseURL: databaseURL,
            taskRetentionLimit: 2,
            progressRetentionLimit: 2
        )
        try await reader.open()
        let page = try await reader.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.tasks.map(\.id), ["task-4", "task-3"])
    }

    func testWriteRejectsOversizedRowsWithoutPartialBatchOrProgressMutation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-write-bounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))

        try await store.open()
        try await store.insertOrReplace(task: task(id: "existing", status: .completed))

        let validBatchRow = task(id: "rolled-back", status: .running)
        var oversized = task(id: "oversized", status: .waiting)
        oversized.title = String(
            repeating: "é",
            count: SQLiteStore.maximumStoredTitleBytes / 2 + 1
        )
        do {
            try await store.insertOrReplace(tasks: [validBatchRow, oversized])
            XCTFail("one invalid task must fail the complete snapshot transaction")
        } catch {
            // Expected. The accepted prefix must roll back with the bad row.
        }

        do {
            try await store.insertProgressEvent(
                source: "manus",
                taskId: "existing",
                type: "thinking",
                message: String(
                    repeating: "x",
                    count: SQLiteStore.maximumStoredProgressMessageBytes + 1
                )
            )
            XCTFail("oversized progress content must fail before insertion")
        } catch {
            // Expected.
        }

        let counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 1, progressEvents: 0))
        let page = try await store.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.tasks.map(\.id), ["existing"])
    }

    func testOpeningCurrentDatabasePurgesOversizedRowsAndOrphanedProgress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-existing-row-bounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let writer = SQLiteStore(databaseURL: databaseURL)

        try await writer.open()
        for id in ["bad-task", "bad-progress"] {
            try await writer.insertOrReplace(task: task(id: id, status: .completed))
            try await writer.insertProgressEvent(
                source: "manus",
                taskId: id,
                type: "thinking",
                message: "initial bounded progress"
            )
        }

        let tamper = try Connection(databaseURL.path)
        try tamper.run(
            "UPDATE \"tasks\" SET \"title\" = ? WHERE \"id\" = ?",
            String(repeating: "x", count: SQLiteStore.maximumStoredTitleBytes + 1),
            "bad-task"
        )
        try tamper.run(
            "UPDATE \"progress_events\" SET \"message\" = ? WHERE \"task_id\" = ?",
            String(
                repeating: "x",
                count: SQLiteStore.maximumStoredProgressMessageBytes + 1
            ),
            "bad-progress"
        )

        let reader = SQLiteStore(databaseURL: databaseURL)
        try await reader.open()
        let counts = try await reader.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 1, progressEvents: 0))
        let page = try await reader.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.tasks.map(\.id), ["bad-progress"])
    }

    func testHistoryReadFiltersOversizedExternalRowModifiedAfterOpen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-live-row-bounds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let store = SQLiteStore(databaseURL: databaseURL)

        try await store.open()
        try await store.insertOrReplace(task: task(id: "tampered", status: .completed))

        let tamper = try Connection(databaseURL.path)
        try tamper.run(
            "UPDATE \"tasks\" SET \"waiting_message\" = ? WHERE \"id\" = ?",
            String(
                repeating: "x",
                count: SQLiteStore.maximumStoredWaitingMessageBytes + 1
            ),
            "tampered"
        )

        // The row still exists on disk, but the bounded SQL predicate rejects
        // it before SQLite.swift materializes the oversized text in Swift.
        let counts = try await store.storedRecordCounts()
        XCTAssertEqual(counts, .init(tasks: 1, progressEvents: 0))
        let page = try await store.loadTaskHistory(limit: 200)
        XCTAssertTrue(page.tasks.isEmpty)
        XCTAssertEqual(page.totalCount, 0)
    }

    func testDatabaseLocationTightensDirectoryAndFileToOwnerOnly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-private-database-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755]
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: databaseURL.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o644]
        ))

        let store = SQLiteStore(databaseURL: databaseURL)
        try await store.open()

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: databaseURL.path
        )
        XCTAssertEqual(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            SQLiteStore.privateDirectoryPermissions
        )
        XCTAssertEqual(
            (fileAttributes[.posixPermissions] as? NSNumber)?.intValue,
            SQLiteStore.privateFilePermissions
        )
        XCTAssertEqual(directoryAttributes[.type] as? FileAttributeType, .typeDirectory)
        XCTAssertEqual(fileAttributes[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(
            (directoryAttributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            geteuid()
        )
        XCTAssertEqual(
            (fileAttributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            geteuid()
        )
    }

    func testOpenRejectsSymlinkDatabaseWithoutTouchingTarget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-database-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let target = root.appendingPathComponent("unrelated.txt")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let sentinel = Data("unrelated user content".utf8)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: databaseURL,
            withDestinationURL: target
        )

        let store = SQLiteStore(databaseURL: databaseURL)
        do {
            try await store.open()
            XCTFail("a database symlink must fail before SQLite opens its target")
        } catch {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: databaseURL.path),
            target.path
        )
    }

    func testOpenRejectsSymlinkDatabaseDirectoryWithoutCreatingTargetFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-database-directory-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let actualDirectory = root.appendingPathComponent("actual")
        let linkedDirectory = root.appendingPathComponent("linked")
        let databaseURL = linkedDirectory.appendingPathComponent("tasks.sqlite")

        try FileManager.default.createDirectory(
            at: actualDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory,
            withDestinationURL: actualDirectory
        )

        let store = SQLiteStore(databaseURL: databaseURL)
        do {
            try await store.open()
            XCTFail("the final App-owned database directory must not be a symlink")
        } catch {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: actualDirectory.appendingPathComponent("tasks.sqlite").path
        ))
    }

    func testOpenRejectsNonRegularDatabaseEntry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-database-directory-entry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")

        try FileManager.default.createDirectory(
            at: databaseURL,
            withIntermediateDirectories: true
        )
        let store = SQLiteStore(databaseURL: databaseURL)
        do {
            try await store.open()
            XCTFail("a directory at the database path must fail closed")
        } catch {
            // Expected.
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: databaseURL.path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testOpenRejectsHardLinkedDatabaseWithoutTouchingPeer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-database-hardlink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let peer = root.appendingPathComponent("peer.sqlite")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let sentinel = Data("hard-linked user content".utf8)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try sentinel.write(to: peer)
        try FileManager.default.linkItem(at: peer, to: databaseURL)

        let store = SQLiteStore(databaseURL: databaseURL)
        do {
            try await store.open()
            XCTFail("a multiply linked database could alias another user file")
        } catch {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: peer), sentinel)
        XCTAssertEqual(try Data(contentsOf: databaseURL), sentinel)
    }

    func testOpenRejectsSymlinkSQLiteSidecarBeforeSchemaMutation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-sidecar-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let sidecarURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let target = root.appendingPathComponent("unrelated-wal-target")
        let sentinel = Data("sidecar target must remain unchanged".utf8)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: databaseURL.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ))
        try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: sidecarURL,
            withDestinationURL: target
        )

        let store = SQLiteStore(databaseURL: databaseURL)
        do {
            try await store.open()
            XCTFail("unsafe SQLite sidecars must fail before database access")
        } catch {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size]
                as? NSNumber)?.intValue,
            0
        )
    }

    func testPreparedBoundaryRejectsReplacedDirectoryEvenWhenDatabaseInodeReturns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-directory-anchor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let movedDirectory = root.appendingPathComponent("moved")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: databaseURL.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ))
        let prepared = try SQLiteFileBoundary.prepare(at: databaseURL)

        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.moveItem(
            at: movedDirectory.appendingPathComponent("tasks.sqlite"),
            to: databaseURL
        )

        // The database path names the original inode again. Only the retained
        // directory identity distinguishes this replacement from the folder
        // that was reviewed before SQLite access.
        XCTAssertThrowsError(try SQLiteFileBoundary.verify(prepared))
    }

    func testSidecarHardeningDoesNotTouchAReplacedDirectoryEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-sidecar-anchor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let movedDirectory = root.appendingPathComponent("moved")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let sidecarURL = URL(fileURLWithPath: databaseURL.path + "-wal")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let prepared = try SQLiteFileBoundary.prepare(at: databaseURL)

        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.moveItem(
            at: movedDirectory.appendingPathComponent("tasks.sqlite"),
            to: databaseURL
        )
        XCTAssertTrue(FileManager.default.createFile(
            atPath: sidecarURL.path,
            contents: Data("unrelated sidecar entry".utf8),
            attributes: [.posixPermissions: 0o644]
        ))

        XCTAssertThrowsError(try SQLiteFileBoundary.secureExistingSidecars(for: prepared))
        let attributes = try FileManager.default.attributesOfItem(atPath: sidecarURL.path)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o644
        )
    }

    func testRuntimeDirectoryReplacementRejectsWriteWhenDatabaseInodeReturns() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-runtime-write-anchor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let movedDirectory = root.appendingPathComponent("moved")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let store = SQLiteStore(databaseURL: databaseURL)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await store.open()
        try replaceDirectoryKeepingDatabase(
            directory: directory,
            movedDirectory: movedDirectory,
            databaseURL: databaseURL
        )

        do {
            try await store.insertOrReplace(task: task(id: "must-not-write", status: .running))
            XCTFail("a runtime directory replacement must disable persistence")
        } catch {
            // Expected.
        }

        let inspection = try Connection(databaseURL.path)
        XCTAssertEqual(try inspection.scalar(Table("tasks").count), 0)

        do {
            _ = try await store.storedRecordCounts()
            XCTFail("a disabled store must not report a successful empty result")
        } catch {
            // Expected: TaskStore can keep presenting history as unavailable.
        }
    }

    func testRuntimeDirectoryReplacementRollsBackClearHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-runtime-clear-anchor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let movedDirectory = root.appendingPathComponent("moved")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let store = SQLiteStore(databaseURL: databaseURL)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await store.open()
        try await store.insertOrReplace(task: task(id: "preserved", status: .completed))
        try replaceDirectoryKeepingDatabase(
            directory: directory,
            movedDirectory: movedDirectory,
            databaseURL: databaseURL
        )

        do {
            try await store.clearStoredHistory()
            XCTFail("Clear History must not run through a replaced directory")
        } catch {
            // Expected.
        }

        let inspection = try Connection(databaseURL.path)
        XCTAssertEqual(try inspection.scalar(Table("tasks").count), 1)
    }

    func testRuntimeDirectoryReplacementRejectsMaterializedHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-runtime-read-anchor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let movedDirectory = root.appendingPathComponent("moved")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let store = SQLiteStore(databaseURL: databaseURL)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await store.open()
        try await store.insertOrReplace(task: task(id: "private-row", status: .completed))
        try replaceDirectoryKeepingDatabase(
            directory: directory,
            movedDirectory: movedDirectory,
            databaseURL: databaseURL
        )

        do {
            _ = try await store.loadTaskHistory(limit: 200)
            XCTFail("history must not return rows after its directory identity changes")
        } catch {
            // Expected.
        }
    }

    func testRuntimeSidecarSymlinkIsRejectedBeforeWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-runtime-sidecar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owned")
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")
        let journalURL = URL(fileURLWithPath: databaseURL.path + "-journal")
        let target = root.appendingPathComponent("unrelated-journal-target")
        let sentinel = Data("runtime sidecar target must stay unchanged".utf8)
        let store = SQLiteStore(databaseURL: databaseURL)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await store.open()
        try sentinel.write(to: target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        try FileManager.default.createSymbolicLink(
            at: journalURL,
            withDestinationURL: target
        )

        do {
            try await store.insertOrReplace(task: task(id: "must-not-write", status: .running))
            XCTFail("a sidecar symlink added after open must fail before SQLite writes")
        } catch {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: target), sentinel)

        try FileManager.default.removeItem(at: journalURL)
        let inspection = try Connection(databaseURL.path)
        XCTAssertEqual(try inspection.scalar(Table("tasks").count), 0)
    }

    func testOlderSnapshotCannotRegressPersistedTerminalState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-monotonic-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))
        var newest = task(id: "session", source: "codex", status: .completed)
        newest.updatedAt = Date(timeIntervalSince1970: 200)
        var stale = task(id: "session", source: "codex", status: .running)
        stale.updatedAt = Date(timeIntervalSince1970: 100)

        try await store.open()
        try await store.insertOrReplace(task: newest)
        try await store.insertOrReplace(task: stale)

        let page = try await store.loadTaskHistory(limit: 200)
        XCTAssertEqual(page.tasks.first?.status, .completed)
        XCTAssertEqual(page.tasks.first?.updatedAt, newest.updatedAt)
    }

    func testPartialUnknownSchemaFailsWithoutRewritingUserRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-partial-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("tasks.sqlite")

        do {
            let partial = try Connection(databaseURL.path)
            try partial.run("CREATE TABLE \"tasks\" (\"id\" TEXT PRIMARY KEY NOT NULL, \"sentinel\" TEXT NOT NULL)")
            try partial.run("INSERT INTO \"tasks\" (\"id\", \"sentinel\") VALUES (?, ?)", "keep", "original")
        }

        let store = SQLiteStore(databaseURL: databaseURL)
        do {
            try await store.open()
            XCTFail("partial foreign schema must fail closed")
        } catch {
            // Expected. Re-open independently to prove no migration table or
            // destructive rewrite was attempted.
        }

        let check = try Connection(databaseURL.path)
        let sentinel = try check.scalar("SELECT \"sentinel\" FROM \"tasks\" WHERE \"id\" = 'keep'") as? String
        XCTAssertEqual(sentinel, "original")
        XCTAssertTrue(try check.schema.objectDefinitions(name: "progress_events").isEmpty)
        XCTAssertTrue(try check.schema.objectDefinitions(name: "dev_island_tasks_v2").isEmpty)
    }

    private func task(
        id: String,
        source: String = "manus",
        status: TaskStatus,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
    ) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: "Sensitive \(id)",
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            taskURL: "https://manus.im/task/\(id)"
        )
    }

    private func replaceDirectoryKeepingDatabase(
        directory: URL,
        movedDirectory: URL,
        databaseURL: URL
    ) throws {
        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.moveItem(
            at: movedDirectory.appendingPathComponent(databaseURL.lastPathComponent),
            to: databaseURL
        )
    }
}
