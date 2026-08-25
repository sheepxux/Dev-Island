import SwiftUI
import IslandCore

/// Product color roles. The product uses warm, ink-like neutrals rather than
/// blue-purple "AI" gradients. State colors are deliberately muted and are
/// reserved for actual task state; they are not decorative accents.
enum Palette {
    // Surfaces
    static let notchBlack   = Color(hex: 0x000000)
    static let islandTop    = Color(hex: 0x10100E)

    // Type + rules
    static let warmWhite     = Color(hex: 0xE8E3D9)
    static let textSecondary = Color(hex: 0x9B978E)
    static let textTertiary  = Color(hex: 0x817D74)
    static let hairline      = warmWhite.opacity(0.085)

    // Welcome Tour
    static let tourCanvas   = Color(hex: 0x0A0A09)
    static let tourPanel    = Color(hex: 0x10100E)
    static let tourAccent   = Color(hex: 0xD2C3AA)

    // States
    static let stateIdle      = Color(hex: 0x77736A)
    static let stateRunning   = Color(hex: 0x45C2FF)
    static let stateWaiting   = Color(hex: 0xFFB84F)
    static let stateCompleted = Color(hex: 0x64D88C)
    static let stateFailed    = Color(hex: 0xFF6A61)
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
