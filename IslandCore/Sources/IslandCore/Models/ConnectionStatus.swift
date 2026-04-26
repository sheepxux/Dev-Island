import Foundation

public enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
    case reconnecting
    case degraded(reason: String)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.connected, .connected),
             (.disconnected, .disconnected),
             (.reconnecting, .reconnecting):
            return true
        case (.degraded(let a), .degraded(let b)):
            return a == b
        default:
            return false
        }
    }
}
