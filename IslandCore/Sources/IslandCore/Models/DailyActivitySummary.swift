import Foundation

/// Content-free "what happened today" numbers derived from local history.
///
/// `sessionCount` and `activeSeconds` come from the persisted task rows whose
/// session started inside the calendar day; `approvalCount` comes from the
/// day-bucketed decision counter. Nothing here identifies a session, project,
/// prompt, or tool.
public struct DailyActivitySummary: Equatable, Sendable {
    public let dayStart: Date
    public let sessionCount: Int
    public let activeSeconds: TimeInterval
    public let approvalCount: Int

    public init(
        dayStart: Date,
        sessionCount: Int,
        activeSeconds: TimeInterval,
        approvalCount: Int
    ) {
        self.dayStart = dayStart
        self.sessionCount = max(0, sessionCount)
        self.activeSeconds = activeSeconds.isFinite ? max(0, activeSeconds) : 0
        self.approvalCount = max(0, approvalCount)
    }

    public var isEmpty: Bool {
        sessionCount == 0 && approvalCount == 0
    }

    /// Half-open local calendar-day window that contains `date`.
    public static func dayWindow(
        containing date: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}

/// Counts the user's Allow decisions for the current local day in
/// `UserDefaults`. The bucket resets itself the first time it is touched on a
/// new day, so the stored state is at most one timestamp and one small
/// integer, never a decision history.
public struct DailyDecisionCounter: Sendable {
    public static let dayStartKey = "island.activity.approvalDayStart"
    public static let approvalCountKey = "island.activity.approvalCount"
    /// Guards against a corrupted or hostile preference file inflating the
    /// number shown in the interface.
    public static let maximumCount = 100_000

    private let defaults: UserDefaults
    private let calendar: Calendar

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Approvals recorded for the local day containing `now`.
    public func approvalCount(at now: Date = .now) -> Int {
        let window = DailyActivitySummary.dayWindow(containing: now, calendar: calendar)
        let storedStart = defaults.double(forKey: Self.dayStartKey)
        guard storedStart.isFinite,
              storedStart == window.start.timeIntervalSince1970 else { return 0 }
        return min(max(0, defaults.integer(forKey: Self.approvalCountKey)), Self.maximumCount)
    }

    /// Record one approval, rolling the bucket over when the day has changed.
    @discardableResult
    public func recordApproval(at now: Date = .now) -> Int {
        let window = DailyActivitySummary.dayWindow(containing: now, calendar: calendar)
        let current = approvalCount(at: now)
        let next = min(current + 1, Self.maximumCount)
        defaults.set(window.start.timeIntervalSince1970, forKey: Self.dayStartKey)
        defaults.set(next, forKey: Self.approvalCountKey)
        return next
    }

    /// Forget the counter, for Clear History.
    public func reset() {
        defaults.removeObject(forKey: Self.dayStartKey)
        defaults.removeObject(forKey: Self.approvalCountKey)
    }
}
