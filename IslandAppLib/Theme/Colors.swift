import AppKit
import SwiftUI
import IslandCore

/// One product-wide interpretation of macOS Increase Contrast.
///
/// Dev Island deliberately uses near-black surfaces and very quiet rules in
/// the standard appearance. Those custom colors do not become stronger just
/// because macOS switches to a high-contrast appearance, so the palette must
/// provide that second state explicitly. Keeping the values here prevents
/// each screen from inventing a different "high contrast" gray.
enum InterfaceContrastPolicy {
    enum Role: CaseIterable {
        case secondaryText
        case tertiaryText
        case hairline
        case islandBorder
        case idleState
    }

    struct Tone: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(hex: UInt32, alpha: Double = 1) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
            self.alpha = alpha
        }

        var nsColor: NSColor {
            NSColor(
                srgbRed: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
        }
    }

    static func isIncreased(_ contrast: ColorSchemeContrast) -> Bool {
        contrast == .increased
    }

    /// System state for custom palette colors. AppKit normalizes the legacy
    /// high-contrast appearance names back to Aqua on current macOS, so
    /// `NSAppearance.name` is not a trustworthy signal here.
    static var systemPrefersIncreasedContrast: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment[
            "DEV_ISLAND_FORCE_INCREASED_CONTRAST"
        ] == "1" {
            return true
        }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static func usesIncreasedContrast(_ contrast: ColorSchemeContrast) -> Bool {
        isIncreased(contrast) || systemPrefersIncreasedContrast
    }

    static func tone(for role: Role, increased: Bool) -> Tone {
        switch (role, increased) {
        case (.secondaryText, false): return Tone(hex: 0xA19F9A)
        case (.secondaryText, true):  return Tone(hex: 0xDEDCD6)
        case (.tertiaryText, false):  return Tone(hex: 0x7F7D78)
        case (.tertiaryText, true):   return Tone(hex: 0xB9B6B0)
        case (.hairline, false):      return Tone(hex: 0xECEBE7, alpha: 0.085)
        case (.hairline, true):       return Tone(hex: 0xECEBE7, alpha: 0.24)
        case (.islandBorder, false):  return Tone(hex: 0xFFFFFF, alpha: 0.06)
        case (.islandBorder, true):   return Tone(hex: 0xFFFFFF, alpha: 0.26)
        // Idle stays quieter than every active state, but it must remain
        // legible as Dev Island's nine-point signature on a black menu bar.
        // The previous tone disappeared at compact sizes after per-point
        // field opacity was applied on Retina displays.
        case (.idleState, false):     return Tone(hex: 0x8A867E)
        case (.idleState, true):      return Tone(hex: 0xB6B1A8)
        }
    }

    static func systemColor(for role: Role) -> NSColor {
        tone(
            for: role,
            increased: systemPrefersIncreasedContrast
        ).nsColor
    }

    static func borderWidth(increased: Bool, standard: CGFloat) -> CGFloat {
        increased ? max(1, standard) : standard
    }
}

/// Product color roles. Surfaces stay nearly achromatic; state colors are the
/// only saturated ink in the product. This keeps the interface closer to a
/// precise macOS instrument than a warm editorial/"AI" landing-page palette.
enum Palette {
    private static func adaptive(_ role: InterfaceContrastPolicy.Role) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            InterfaceContrastPolicy.systemColor(for: role)
        })
    }

    // Surfaces
    static let notchBlack   = Color(hex: 0x000000)
    static let islandTop    = Color(hex: 0x101010)

    // Type + rules
    static let warmWhite     = Color(hex: 0xECEBE7)
    static let textSecondary = adaptive(.secondaryText)
    // 4.59:1 against the raised surface (#111111). Keep required compact
    // metadata at this base token; lower-opacity uses are decorative only.
    static let textTertiary  = adaptive(.tertiaryText)
    static let hairline      = adaptive(.hairline)
    static let islandBorder  = adaptive(.islandBorder)

    // Welcome Tour
    static let tourCanvas   = Color(hex: 0x0A0A0A)
    static let tourPanel    = Color(hex: 0x111111)
    static let tourAccent   = Color(hex: 0xC8C6C0)

    // States
    static let stateIdle      = adaptive(.idleState)
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
/// Attention-first presentation priority:
/// `Waiting > Failed > Completed > Running > Idle`
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

    static func derive(
        from tasks: [AgentTask],
        now: Date = .now
    ) -> BarState {
        let status = TaskPresentationPolicy.primaryTask(
            in: tasks,
            now: now
        )?.status
        return derive(fromPrimaryStatus: status)
    }

    /// Map an already selected attention-first session without sorting its
    /// collection again. Root-island rendering uses this after constructing a
    /// single `IslandPresentationSnapshot`; generic callers can keep using
    /// `derive(from:now:)` when their input ordering is unknown.
    static func derive(fromPrimaryStatus status: TaskStatus?) -> BarState {
        switch status {
        case .running?:   return .running
        case .waiting?:   return .waiting
        case .completed?: return .completed
        case .failed?:    return .failed
        case nil:         return .idle
        }
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
