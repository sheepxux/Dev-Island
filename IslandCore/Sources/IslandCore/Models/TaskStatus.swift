import Foundation

public enum TaskStatus: String, Codable, Sendable {
    case running
    case waiting
    case completed
    case failed
}
