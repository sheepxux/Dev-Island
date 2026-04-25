import SwiftUI
import IslandCore

/// Design token colors. See `docs/design-tokens` (mirror of CLAUDE_CLIENT.md §5).
enum Palette {
    // Surfaces
    static let notchBlack   = Color(hex: 0x000000)
    static let capsuleBlack = Color(hex: 0x0A0A0A)
    static let cardBg       = Color(hex: 0x141414)
    static let cardHover    = Color(hex: 0x1A1A1A)
    static let divider      = Color.white.opacity(0.06)

    // States
    static let stateIdle      = Color(hex: 0x4A4A4A)
    static let stateRunning   = Color(hex: 0x5B9EFA)
    static let stateWaiting   = Color(hex: 0xF5A623)
    static let stateCompleted = Color(hex: 0x3ECF8E)
    static let stateFailed    = Color(hex: 0xE5484D)
}

extension TaskStatus {
    /// Per-state token color.
    var color: Color {
        switch self {
        case .running:   return Palette.stateRunning
        case .waiting:   return Palette.stateWaiting
        case .completed: return Palette.stateCompleted
        case .failed:    return Palette.stateFailed
        }
    }
}

/// Bar/dot state — derived from `TaskStore.tasks` highest priority, plus an
/// `idle` value used when no tasks exist.
///
/// Priority (per CLAUDE_CLIENT.md §4):
/// `Waiting > Failed > Running > Completed > Idle`
enum BarState: Equatable {
    case idle
    case running
    case waiting
    case completed
    case failed

    var color: Color {
        switch self {
        case .idle:      return Palette.stateIdle
        case .running:   return Palette.stateRunning
        case .waiting:   return Palette.stateWaiting
        case .completed: return Palette.stateCompleted
        case .failed:    return Palette.stateFailed
        }
    }

    static func derive(from tasks: [AgentTask]) -> BarState {
        if tasks.contains(where: { $0.status == .waiting })   { return .waiting }
        if tasks.contains(where: { $0.status == .failed })    { return .failed }
        if tasks.contains(where: { $0.status == .running })   { return .running }
        if tasks.contains(where: { $0.status == .completed }) { return .completed }
        return .idle
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }
}
