import Foundation
import SQLite

actor SQLiteStore {
    static let privateDirectoryPermissions = SQLiteFileBoundary.privateDirectoryPermissions
    static let privateFilePermissions = SQLiteFileBoundary.privateFilePermissions
    static let maximumStoredTasks = 5_000
    static let maximumStoredProgressEvents = 20_000
    static let maximumStoredSourceBytes = 64
    static let maximumStoredTaskIDBytes = 256
    static let maximumStoredTitleBytes = 1_024
    static let maximumStoredPhaseBytes = 1_024
    static let maximumStoredTaskURLBytes = 16_384
    static let maximumStoredWaitingMessageBytes = 16_384
    static let maximumStoredProgressTypeBytes = 256
    static let maximumStoredProgressMessageBytes = 16_384

    struct TaskHistoryPage: Equatable, Sendable {
        let tasks: [AgentTask]
        let totalCount: Int
    }

    struct StoredRecordCounts: Equatable, Sendable {
        let tasks: Int
        let progressEvents: Int
    }

    private enum SchemaError: LocalizedError {
        case incompatible

        var errorDescription: String? {
            switch self {
            case .incompatible:
                return "The local history database has an unsupported schema."
            }
        }
    }

    private enum RecordError: LocalizedError {
        case invalidTask
        case invalidProgress

        var errorDescription: String? {
            switch self {
            case .invalidTask:
                return "The local task history record is invalid or too large."
            case .invalidProgress:
                return "The local progress history record is invalid or too large."
            }
        }
    }

    private static let schemaVersion: Int32 = 2

    private var db: Connection?
    /// Retain both no-follow descriptors for exactly as long as the SQLite
    /// connection can serve reads or writes. Releasing these at the end of
    /// `open()` would reduce a lifecycle boundary to a one-time preflight.
    private var fileBoundary: SQLiteFileBoundary.PreparedDatabase?
    /// Once a runtime identity check fails, later callers must continue to
    /// receive an unavailable result rather than mistaking a nil connection
    /// for a successful no-op.
    private var terminalBoundaryFailure: SQLiteFileBoundary.BoundaryError?
    /// Test-only injection point; production uses Application Support.
    private let databaseURL: URL?
    private let taskRetentionLimit: Int
    private let progressRetentionLimit: Int

    // Table definitions
    private let tasksTable          = Table("tasks")
    private let progressEventsTable = Table("progress_events")

    // tasks columns
    private let colId             = Expression<String>("id")
    private let colSource         = Expression<String>("source")
    private let colTitle          = Expression<String>("title")
    private let colStatus         = Expression<String>("status")
    private let colCurrentPhase   = Expression<String?>("current_phase")
    private let colCreatedAt      = Expression<Double>("created_at")
    private let colUpdatedAt      = Expression<Double>("updated_at")
    private let colTaskURL        = Expression<String>("task_url")
    private let colWaitingMessage = Expression<String?>("waiting_message")

    // progress_events columns
    private let colEventId        = Expression<Int64>("id")
    private let colTaskSource     = Expression<String>("task_source")
    private let colTaskId         = Expression<String>("task_id")
    private let colType           = Expression<String>("type")
    private let colMessage        = Expression<String>("message")
    private let colRecordedAt     = Expression<Double>("recorded_at")

    init(
        databaseURL: URL? = nil,
        taskRetentionLimit: Int = SQLiteStore.maximumStoredTasks,
        progressRetentionLimit: Int = SQLiteStore.maximumStoredProgressEvents
    ) {
        precondition(taskRetentionLimit > 0)
        precondition(progressRetentionLimit > 0)
        self.databaseURL = databaseURL
        self.taskRetentionLimit = taskRetentionLimit
        self.progressRetentionLimit = progressRetentionLimit
    }

    func open() throws {
        let requestedURL: URL
        if let databaseURL {
            requestedURL = databaseURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            requestedURL = appSupport
                .appendingPathComponent("island-app")
                .appendingPathComponent("tasks.sqlite")
        }

        let prepared = try SQLiteFileBoundary.prepare(at: requestedURL)
        // SQLite.swift does not currently expose SQLITE_OPEN_NOFOLLOW. Keep
        // both no-follow descriptors alive with the connection, and verify
        // that the paths still name those exact objects before schema work.
        let connection = try Connection(prepared.url.path)
        try SQLiteFileBoundary.verify(prepared)
        try prepareSchema(connection)
        try connection.transaction {
            try sanitizeExistingRecords(in: connection)
            try enforceRetention(in: connection)
        }
        try SQLiteFileBoundary.verify(prepared)
        try SQLiteFileBoundary.secureExistingSidecars(for: prepared)
        fileBoundary = prepared
        db = connection
        terminalBoundaryFailure = nil
        IslandLogger.storage.info("Local history database opened")
    }

    func insertOrReplace(task: AgentTask) throws {
        try performVerifiedWrite { db in
            try write(task, to: db)
            try enforceRetention(in: db)
        }
    }

    /// Persist one connector snapshot atomically. A local session therefore
    /// cannot leave a half-written cross-agent history page if the process is
    /// interrupted during a multi-row update.
    func insertOrReplace(tasks: [AgentTask]) throws {
        guard !tasks.isEmpty else { return }
        try performVerifiedWrite { db in
            for task in tasks {
                try write(task, to: db)
            }
            try enforceRetention(in: db)
        }
    }

    /// Insert a new identity or update it only when the incoming snapshot is
    /// at least as recent. Hook delivery and actor hops may interleave; an old
    /// Running write must never repaint a Completed history row.
    private func write(_ task: AgentTask, to db: Connection) throws {
        guard Self.isValidStoredTask(task) else {
            throw RecordError.invalidTask
        }
        let values: [Setter] = [
            colId             <- task.id,
            colSource         <- task.source,
            colTitle          <- task.title,
            colStatus         <- task.status.rawValue,
            colCurrentPhase   <- task.currentPhase,
            colCreatedAt      <- task.createdAt.timeIntervalSince1970,
            colUpdatedAt      <- task.updatedAt.timeIntervalSince1970,
            colTaskURL        <- task.taskURL,
            colWaitingMessage <- task.waitingMessage,
        ]
        try db.run(tasksTable.insert(or: .ignore, values))
        let currentIdentity = tasksTable.filter(
            colSource == task.source
                && colId == task.id
                && colUpdatedAt <= task.updatedAt.timeIntervalSince1970
        )
        try db.run(currentIdentity.update(values))
    }

    func insertProgressEvent(
        source: String,
        taskId: String,
        type: String,
        message: String
    ) throws {
        guard Self.isValidSource(source),
              Self.isValidIdentifier(taskId),
              Self.isBoundedText(
                  type,
                  maximumUTF8Bytes: Self.maximumStoredProgressTypeBytes,
                  allowsEmpty: false
              ),
              Self.isBoundedText(
                  message,
                  maximumUTF8Bytes: Self.maximumStoredProgressMessageBytes,
                  allowsEmpty: true
              ) else {
            throw RecordError.invalidProgress
        }
        try performVerifiedWrite { db in
            let insert = progressEventsTable.insert(
                colTaskSource <- source,
                colTaskId     <- taskId,
                colType       <- type,
                colMessage    <- message,
                colRecordedAt <- Date.now.timeIntervalSince1970
            )
            try db.run(insert)
            try enforceRetention(in: db)
        }
    }

    /// Read-only, bounded history page. Persisted rows never flow back into
    /// TaskStore.tasks, so an old Waiting row cannot steal attention from a
    /// live session after relaunch.
    func loadTaskHistory(limit: Int) throws -> TaskHistoryPage {
        let safeLimit = min(max(limit, 1), 500)
        return try performVerifiedRead { db in
            // Filter by SQLite storage class and byte length before
            // SQLite.swift materializes a String. An externally modified or
            // legacy row can therefore never allocate unbounded UI content.
            let boundedRows = tasksTable.filter(
                Expression<Bool>(literal: Self.boundedTaskRowSQLPredicate)
            )
            let query = boundedRows.order(colUpdatedAt.desc).limit(safeLimit)
            var tasks: [AgentTask] = []
            tasks.reserveCapacity(safeLimit)

            for row in try db.prepare(query) {
                let id = row[colId]
                let source = row[colSource]
                let createdAt = row[colCreatedAt]
                let updatedAt = row[colUpdatedAt]
                guard createdAt.isFinite,
                      updatedAt.isFinite,
                      let status = TaskStatus(rawValue: row[colStatus]) else {
                    continue
                }
                let task = AgentTask(
                    id: id,
                    source: source,
                    title: row[colTitle],
                    status: status,
                    currentPhase: row[colCurrentPhase],
                    createdAt: Date(timeIntervalSince1970: createdAt),
                    updatedAt: Date(timeIntervalSince1970: updatedAt),
                    taskURL: row[colTaskURL],
                    waitingMessage: row[colWaitingMessage]
                )
                guard Self.isValidStoredTask(task) else { continue }
                tasks.append(task)
            }

            return TaskHistoryPage(
                tasks: tasks,
                totalCount: try db.scalar(boundedRows.count)
            )
        } ?? TaskHistoryPage(tasks: [], totalCount: 0)
    }

    struct DailyActivityAggregate: Equatable, Sendable {
        let sessionCount: Int
        let activeSeconds: TimeInterval
    }

    /// Content-free aggregate over sessions that started inside
    /// `[dayStart, dayEnd)`: how many, and how long each stayed active
    /// (`updated_at - created_at`, clamped at zero). Only the two timestamp
    /// columns are materialized; no title, ID, or URL leaves the actor.
    func dailyActivity(dayStart: Date, dayEnd: Date) throws -> DailyActivityAggregate {
        let start = dayStart.timeIntervalSince1970
        let end = dayEnd.timeIntervalSince1970
        guard start.isFinite, end.isFinite, end > start else {
            return DailyActivityAggregate(sessionCount: 0, activeSeconds: 0)
        }
        return try performVerifiedRead { db in
            let rows = tasksTable
                .select(colCreatedAt, colUpdatedAt)
                .filter(Expression<Bool>(literal: Self.boundedTaskRowSQLPredicate))
                .filter(colCreatedAt >= start && colCreatedAt < end)
            var sessionCount = 0
            var activeSeconds: TimeInterval = 0
            for row in try db.prepare(rows) {
                let createdAt = row[colCreatedAt]
                let updatedAt = row[colUpdatedAt]
                guard createdAt.isFinite, updatedAt.isFinite else { continue }
                sessionCount += 1
                activeSeconds += max(0, updatedAt - createdAt)
            }
            return DailyActivityAggregate(
                sessionCount: sessionCount,
                activeSeconds: activeSeconds
            )
        } ?? DailyActivityAggregate(sessionCount: 0, activeSeconds: 0)
    }

    /// Remove every persisted task and progress row in one transaction while
    /// keeping the database open for subsequent live snapshots. The in-memory
    /// TaskStore is intentionally untouched, so clearing history never makes
    /// an active Running/Waiting session disappear from the island.
    func clearStoredHistory() throws {
        try performVerifiedWrite { db in
            try db.run(progressEventsTable.delete())
            try db.run(tasksTable.delete())
        }
        IslandLogger.storage.info("Cleared stored task and progress history")
    }

    /// Low-cardinality test/maintenance query. No record content leaves the
    /// storage actor.
    func storedRecordCounts() throws -> StoredRecordCounts {
        try performVerifiedRead { db in
            StoredRecordCounts(
                tasks: try db.scalar(tasksTable.count),
                progressEvents: try db.scalar(progressEventsTable.count)
            )
        } ?? StoredRecordCounts(tasks: 0, progressEvents: 0)
    }

    /// Every operation reuses the retained directory/database anchors. Unsafe
    /// runtime replacement disables only persistence; TaskStore's live local
    /// sessions and loopback listener remain independent.
    private func verifiedContext() throws -> (
        connection: Connection,
        boundary: SQLiteFileBoundary.PreparedDatabase
    )? {
        if let terminalBoundaryFailure { throw terminalBoundaryFailure }
        guard let db else { return nil }
        guard let fileBoundary else {
            self.db = nil
            throw SQLiteFileBoundary.BoundaryError.unsafeDatabase
        }
        do {
            // Check sidecars before SQLite can start a read/write transaction;
            // an attacker-supplied journal path must never reach SQLite first.
            try SQLiteFileBoundary.secureExistingSidecars(for: fileBoundary)
            return (db, fileBoundary)
        } catch {
            disablePersistenceIfBoundaryFailure(error)
            throw error
        }
    }

    private func performVerifiedWrite(
        _ operation: (Connection) throws -> Void
    ) throws {
        guard let context = try verifiedContext() else { return }
        do {
            try context.connection.transaction {
                try operation(context.connection)
                // A replacement detected before commit rolls back the whole
                // user-visible mutation, including Clear History.
                try SQLiteFileBoundary.secureExistingSidecars(for: context.boundary)
            }
            try SQLiteFileBoundary.secureExistingSidecars(for: context.boundary)
        } catch {
            disablePersistenceIfBoundaryFailure(error)
            throw error
        }
    }

    private func performVerifiedRead<Value>(
        _ operation: (Connection) throws -> Value
    ) throws -> Value? {
        guard let context = try verifiedContext() else { return nil }
        do {
            let value = try operation(context.connection)
            // Do not return materialized rows if the path identity changed
            // during the query.
            try SQLiteFileBoundary.secureExistingSidecars(for: context.boundary)
            return value
        } catch {
            disablePersistenceIfBoundaryFailure(error)
            throw error
        }
    }

    private func disablePersistenceIfBoundaryFailure(_ error: Error) {
        guard let boundaryError = error as? SQLiteFileBoundary.BoundaryError else { return }
        terminalBoundaryFailure = boundaryError
        db = nil
        fileBoundary = nil
        IslandLogger.storage.error("Local history file boundary became unavailable")
    }

    /// A current schema is not evidence that every stored value is safe.
    /// Perform the potentially full-table byte/type scan once when opening;
    /// normal writes use the O(1) Swift validator above, while history reads
    /// retain their own SQL-side filter against modification after open.
    private func sanitizeExistingRecords(in db: Connection) throws {
        // Existing or externally modified databases are not trusted merely
        // because their schema is current. SQLite byte-length predicates keep
        // oversized text from crossing into Swift memory during maintenance.
        try db.run("""
            DELETE FROM "tasks"
            WHERE NOT (
                \(Self.boundedTaskRowSQLPredicate)
            )
            """)

        try db.run("""
            DELETE FROM "progress_events"
            WHERE NOT (
                \(Self.boundedProgressRowSQLPredicate)
            )
            """)
    }

    /// Keep privacy-sensitive local history finite. The live island never
    /// reads these rows back into `TaskStore.tasks`, so pruning the oldest
    /// persisted row cannot interrupt an active session. Deterministic ties
    /// make the retained set reproducible across launches and architectures.
    private func enforceRetention(in db: Connection) throws {
        try db.run("""
            DELETE FROM "tasks"
            WHERE rowid IN (
                SELECT rowid
                FROM "tasks"
                ORDER BY "updated_at" DESC,
                         "created_at" DESC,
                         "source" ASC,
                         "id" ASC
                LIMIT -1 OFFSET \(taskRetentionLimit)
            )
            """)

        // A task eviction must not leave its private progress text orphaned.
        try db.run("""
            DELETE FROM "progress_events"
            WHERE NOT EXISTS (
                SELECT 1
                FROM "tasks"
                WHERE "tasks"."source" = "progress_events"."task_source"
                  AND "tasks"."id" = "progress_events"."task_id"
            )
            """)

        try db.run("""
            DELETE FROM "progress_events"
            WHERE rowid IN (
                SELECT rowid
                FROM "progress_events"
                ORDER BY "recorded_at" DESC, "id" DESC
                LIMIT -1 OFFSET \(progressRetentionLimit)
            )
            """)
    }

    private static var boundedTaskRowSQLPredicate: String {
        """
        typeof("id") = 'text'
        AND length(CAST("id" AS BLOB)) BETWEEN 1 AND \(maximumStoredTaskIDBytes)
        AND typeof("source") = 'text'
        AND length(CAST("source" AS BLOB)) BETWEEN 1 AND \(maximumStoredSourceBytes)
        AND "source" NOT GLOB '*[^a-z0-9-]*'
        AND typeof("title") = 'text'
        AND length(CAST("title" AS BLOB)) BETWEEN 1 AND \(maximumStoredTitleBytes)
        AND typeof("status") = 'text'
        AND "status" IN ('running', 'waiting', 'completed', 'failed')
        AND (
            "current_phase" IS NULL
            OR (
                typeof("current_phase") = 'text'
                AND length(CAST("current_phase" AS BLOB)) <= \(maximumStoredPhaseBytes)
            )
        )
        AND typeof("created_at") IN ('real', 'integer')
        AND typeof("updated_at") IN ('real', 'integer')
        AND typeof("task_url") = 'text'
        AND length(CAST("task_url" AS BLOB)) <= \(maximumStoredTaskURLBytes)
        AND (
            "waiting_message" IS NULL
            OR (
                typeof("waiting_message") = 'text'
                AND length(CAST("waiting_message" AS BLOB)) <= \(maximumStoredWaitingMessageBytes)
            )
        )
        """
    }

    private static var boundedProgressRowSQLPredicate: String {
        """
        typeof("task_source") = 'text'
        AND length(CAST("task_source" AS BLOB)) BETWEEN 1 AND \(maximumStoredSourceBytes)
        AND "task_source" NOT GLOB '*[^a-z0-9-]*'
        AND typeof("task_id") = 'text'
        AND length(CAST("task_id" AS BLOB)) BETWEEN 1 AND \(maximumStoredTaskIDBytes)
        AND typeof("type") = 'text'
        AND length(CAST("type" AS BLOB)) BETWEEN 1 AND \(maximumStoredProgressTypeBytes)
        AND typeof("message") = 'text'
        AND length(CAST("message" AS BLOB)) <= \(maximumStoredProgressMessageBytes)
        AND typeof("recorded_at") IN ('real', 'integer')
        """
    }

    private static func isValidStoredTask(_ task: AgentTask) -> Bool {
        isValidSource(task.source)
            && isValidIdentifier(task.id)
            && isBoundedText(
                task.title,
                maximumUTF8Bytes: maximumStoredTitleBytes,
                allowsEmpty: false
            )
            && (task.currentPhase.map {
                    isBoundedText(
                        $0,
                        maximumUTF8Bytes: maximumStoredPhaseBytes,
                        allowsEmpty: true
                    )
                } ?? true)
            && task.createdAt.timeIntervalSince1970.isFinite
            && task.updatedAt.timeIntervalSince1970.isFinite
            && isBoundedControlFreeText(
                task.taskURL,
                maximumUTF8Bytes: maximumStoredTaskURLBytes,
                allowsEmpty: true
            )
            && (task.waitingMessage.map {
                    isBoundedText(
                        $0,
                        maximumUTF8Bytes: maximumStoredWaitingMessageBytes,
                        allowsEmpty: true
                    )
                } ?? true)
    }

    private static func isValidSource(_ value: String) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty
            && bytes.count <= maximumStoredSourceBytes
            && bytes.allSatisfy {
                ($0 >= 0x61 && $0 <= 0x7a)
                    || ($0 >= 0x30 && $0 <= 0x39)
                    || $0 == 0x2d
            }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed
            && isBoundedControlFreeText(
                value,
                maximumUTF8Bytes: maximumStoredTaskIDBytes,
                allowsEmpty: false
            )
    }

    private static func isBoundedControlFreeText(
        _ value: String,
        maximumUTF8Bytes: Int,
        allowsEmpty: Bool
    ) -> Bool {
        isBoundedText(
            value,
            maximumUTF8Bytes: maximumUTF8Bytes,
            allowsEmpty: allowsEmpty
        ) && value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func isBoundedText(
        _ value: String,
        maximumUTF8Bytes: Int,
        allowsEmpty: Bool
    ) -> Bool {
        let count = value.utf8.count
        return (allowsEmpty || count > 0) && count <= maximumUTF8Bytes
    }

    private func prepareSchema(_ db: Connection) throws {
        let objectDefinitions = try db.schema.objectDefinitions(type: .table)
        let tableNames = Set(objectDefinitions.map(\.name))
        let hasTasks = tableNames.contains("tasks")
        let hasProgressEvents = tableNames.contains("progress_events")

        if !hasTasks && !hasProgressEvents {
            try createCurrentTables(in: db)
        } else if hasTasks && hasProgressEvents {
            if try isCurrentSchema(db) {
                // Already current. Still recreate non-authoritative indexes
                // in case a repair tool removed one.
            } else if try isLegacySchema(db) {
                try migrateLegacySchema(in: db)
            } else {
                throw SchemaError.incompatible
            }
        } else {
            // Never guess around a partial or foreign schema. Keeping the
            // original bytes intact is safer than a destructive best effort.
            throw SchemaError.incompatible
        }

        try createIndexesIfNeeded(in: db)
        try db.run("PRAGMA user_version = \(Self.schemaVersion)")
    }

    private func createCurrentTables(in db: Connection) throws {
        try db.run(createTasksTable(tasksTable, ifNotExists: false))
        try db.run(createProgressEventsTable(progressEventsTable, ifNotExists: false))
    }

    private func createTasksTable(_ table: Table, ifNotExists: Bool) -> String {
        table.create(ifNotExists: ifNotExists) { t in
            t.column(colId)
            t.column(colSource)
            t.column(colTitle)
            t.column(colStatus)
            t.column(colCurrentPhase)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
            t.column(colTaskURL)
            t.column(colWaitingMessage)
            t.primaryKey(colSource, colId)
        }
    }

    private func createProgressEventsTable(
        _ table: Table,
        ifNotExists: Bool
    ) -> String {
        table.create(ifNotExists: ifNotExists) { t in
            t.column(colEventId, primaryKey: .autoincrement)
            t.column(colTaskSource)
            t.column(colTaskId)
            t.column(colType)
            t.column(colMessage)
            t.column(colRecordedAt)
        }
    }

    private func createIndexesIfNeeded(in db: Connection) throws {
        try db.run(tasksTable.createIndex(colUpdatedAt, ifNotExists: true))
        try db.run(progressEventsTable.createIndex(
            colTaskSource,
            colTaskId,
            colRecordedAt,
            ifNotExists: true
        ))
    }

    private func isCurrentSchema(_ db: Connection) throws -> Bool {
        let taskPrimaryKey = try db.schema.indexDefinitions(table: "tasks")
            .first(where: { $0.origin == .primaryKey })?
            .columns
        let progressColumns = Set(
            try db.schema.columnDefinitions(table: "progress_events").map(\.name)
        )
        return taskPrimaryKey == ["source", "id"]
            && progressColumns.contains("task_source")
    }

    private func isLegacySchema(_ db: Connection) throws -> Bool {
        let taskPrimaryKey = try db.schema.indexDefinitions(table: "tasks")
            .first(where: { $0.origin == .primaryKey })?
            .columns
        let progressColumns = Set(
            try db.schema.columnDefinitions(table: "progress_events").map(\.name)
        )
        return taskPrimaryKey == ["id"]
            && !progressColumns.contains("task_source")
    }

    /// v0.3 stored only Manus rows and keyed tasks by the vendor-local `id`.
    /// Migrate both tables in one transaction, preserving every legacy byte
    /// while introducing the product-wide `(source, id)` identity.
    private func migrateLegacySchema(in db: Connection) throws {
        let migratedTasks = Table("dev_island_tasks_v2")
        let migratedProgress = Table("dev_island_progress_events_v2")

        try db.transaction {
            try db.run(createTasksTable(migratedTasks, ifNotExists: false))
            try db.run(createProgressEventsTable(migratedProgress, ifNotExists: false))
            try db.run("""
                INSERT INTO "dev_island_tasks_v2"
                    ("id", "source", "title", "status", "current_phase",
                     "created_at", "updated_at", "task_url", "waiting_message")
                SELECT "id", "source", "title", "status", "current_phase",
                       "created_at", "updated_at", "task_url", "waiting_message"
                FROM "tasks"
                """)
            try db.run("""
                INSERT INTO "dev_island_progress_events_v2"
                    ("id", "task_source", "task_id", "type", "message", "recorded_at")
                SELECT p."id", COALESCE(NULLIF(t."source", ''), 'manus'),
                       p."task_id", p."type", p."message", p."recorded_at"
                FROM "progress_events" AS p
                LEFT JOIN "tasks" AS t ON t."id" = p."task_id"
                """)
            try db.run(progressEventsTable.drop())
            try db.run(tasksTable.drop())
            try db.run(migratedTasks.rename(tasksTable))
            try db.run(migratedProgress.rename(progressEventsTable))
        }
    }
}
