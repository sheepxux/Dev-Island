import Foundation

/// A provider-authored rate-limit window surfaced from local, read-only data.
/// Dev Island never invents a quota or derives one from task counts.
public struct AgentUsageWindow: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case primary
        case secondary
    }

    public let kind: Kind
    public let usedPercent: Double
    public let durationMinutes: Int
    public let resetsAt: Date?

    public var id: Kind { kind }

    public init?(
        kind: Kind,
        usedPercent: Double,
        durationMinutes: Int,
        resetsAt: Date?
    ) {
        guard usedPercent.isFinite,
              (0...100).contains(usedPercent),
              (1...(60 * 24 * 366)).contains(durationMinutes) else {
            return nil
        }
        self.kind = kind
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }
}

/// A deliberately content-free usage snapshot. It contains only numeric
/// provider limits and timestamps; no prompt, response, path, ID or key can
/// cross this model boundary into the UI or diagnostics.
public struct AgentUsageSnapshot: Equatable, Sendable {
    public enum Provider: String, Codable, Sendable {
        case codex
    }

    public let provider: Provider
    public let observedAt: Date
    public let windows: [AgentUsageWindow]

    public init?(
        provider: Provider,
        observedAt: Date,
        windows: [AgentUsageWindow]
    ) {
        guard observedAt.timeIntervalSince1970.isFinite,
              !windows.isEmpty,
              Set(windows.map(\.kind)).count == windows.count else {
            return nil
        }
        self.provider = provider
        self.observedAt = observedAt
        self.windows = windows
    }

    public func isStale(
        at now: Date = .now,
        maximumAge: TimeInterval = 15 * 60
    ) -> Bool {
        guard maximumAge.isFinite, maximumAge >= 0 else { return true }
        return now.timeIntervalSince(observedAt) > maximumAge
    }
}
