import Foundation
import SQLite

actor SQLiteStore {
    private var db: Connection?

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
    private let colTaskId         = Expression<String>("task_id")
    private let colType           = Expression<String>("type")
    private let colMessage        = Expression<String>("message")
    private let colRecordedAt     = Expression<Double>("recorded_at")

    func open() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("island-app")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("tasks.sqlite").path
        let connection = try Connection(path)
        try createTablesIfNeeded(connection)
        db = connection
        IslandLogger.storage.info("SQLite opened at \(path)")
    }

    func insertOrReplace(task: AgentTask) throws {
        guard let db else { return }
        let insert = tasksTable.insert(or: .replace,
            colId             <- task.id,
            colSource         <- task.source,
            colTitle          <- task.title,
            colStatus         <- task.status.rawValue,
            colCurrentPhase   <- task.currentPhase,
            colCreatedAt      <- task.createdAt.timeIntervalSince1970,
            colUpdatedAt      <- task.updatedAt.timeIntervalSince1970,
            colTaskURL        <- task.taskURL,
            colWaitingMessage <- task.waitingMessage
        )
        try db.run(insert)
    }

    func insertProgressEvent(taskId: String, type: String, message: String) throws {
        guard let db else { return }
        let insert = progressEventsTable.insert(
            colTaskId     <- taskId,
            colType       <- type,
            colMessage    <- message,
            colRecordedAt <- Date.now.timeIntervalSince1970
        )
        try db.run(insert)
    }

    private func createTablesIfNeeded(_ db: Connection) throws {
        try db.run(tasksTable.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: true)
            t.column(colSource)
            t.column(colTitle)
            t.column(colStatus)
            t.column(colCurrentPhase)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
            t.column(colTaskURL)
            t.column(colWaitingMessage)
        })
        try db.run(progressEventsTable.create(ifNotExists: true) { t in
            t.column(colEventId, primaryKey: .autoincrement)
            t.column(colTaskId)
            t.column(colType)
            t.column(colMessage)
            t.column(colRecordedAt)
        })
    }
}
