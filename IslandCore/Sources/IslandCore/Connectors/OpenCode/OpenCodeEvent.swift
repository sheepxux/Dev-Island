import Foundation

/// Privacy-minimal envelope emitted by Dev Island's OpenCode plugin.
///
/// This is intentionally not the vendor Event union. The plugin allowlists
/// low-frequency lifecycle fields before loopback transit, so user content and
/// forward-extensible metadata cannot accidentally enter task state or logs.
public struct OpenCodeEvent: Decodable, Sendable {
    public static let currentSchemaVersion = 1

    public enum Kind: String, Decodable, Sendable {
        case sessionCreated = "session.created"
        case sessionStatus = "session.status"
        case sessionIdle = "session.idle"
        case sessionDeleted = "session.deleted"
        case sessionError = "session.error"
        case permissionUpdated = "permission.updated"
        case permissionReplied = "permission.replied"
    }

    public let schemaVersion: Int
    public let event: Kind
    public let sessionId: String
    public let cwd: String?
    public let status: String?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        event: Kind,
        sessionId: String,
        cwd: String? = nil,
        status: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.status = status
    }
}
