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

        /// The 8-bit sRGB value an OKLCH token renders as.
        init(_ color: OKLCH, alpha: Double = 1) {
            self.init(hex: color.hex, alpha: alpha)
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

    /// Island roles read from the dark end of `Sand`, the same ramp the
    /// windows read from the light end. Quiet text stays at WCAG AA on the
    /// island ground or better; hierarchy comes from the lightness steps
    /// between roles, and Increase Contrast moves every role one step
    /// brighter (rules gain alpha instead).
    static func tone(for role: Role, increased: Bool) -> Tone {
        switch (role, increased) {
        case (.secondaryText, false): return Tone(Sand.s200)
        case (.secondaryText, true):  return Tone(Sand.s100)
        case (.tertiaryText, false):  return Tone(Sand.s300)
        case (.tertiaryText, true):   return Tone(Sand.s200)
        case (.hairline, false):      return Tone(Sand.s50, alpha: 0.10)
        case (.hairline, true):       return Tone(Sand.s50, alpha: 0.24)
        case (.islandBorder, false):  return Tone(Sand.s50, alpha: 0.08)
        case (.islandBorder, true):   return Tone(Sand.s50, alpha: 0.26)
        // Idle stays quieter than every active state, but it must remain
        // legible as Dev Island's nine-point signature on a black menu bar.
        case (.idleState, false):     return Tone(Sand.s400)
        case (.idleState, true):      return Tone(Sand.s300)
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

/// Island color roles. The island is the app icon's black terminal tile, so
/// it reads from the dark end of `Sand`; windows read from the light end
/// (`Palette.Window`).
///
/// State colors encode urgency, not category. A session that needs you is
/// the most vivid thing in the menu bar, a failure is next, a finished
/// response is barely tinted, and running work carries no hue at all — the
/// orbiting dots are the signal, so the amber of a waiting request never
/// has to compete with a screen full of busy sessions.
enum Palette {
    private static func adaptive(_ role: InterfaceContrastPolicy.Role) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            InterfaceContrastPolicy.systemColor(for: role)
        })
    }

    // Surfaces
    /// Matches the hardware notch exactly; the silhouette must be seamless.
    static let notchBlack   = Color(hex: 0x000000)
    static let islandTop    = Sand.s950.color

    // Type + rules
    static let warmWhite     = Sand.s50.color
    static let textSecondary = adaptive(.secondaryText)
    static let textTertiary  = adaptive(.tertiaryText)
    static let hairline      = adaptive(.hairline)
    static let islandBorder  = adaptive(.islandBorder)

    // Welcome Tour stage: the island sample and terminal lines keep the
    // island's own ground.
    static let tourCanvas       = Sand.s1000.color
    static let tourCanvasRaised = Sand.s950.color
    static let tourPanel        = Sand.s950.color
    static let tourPanelRaised  = Sand.s900.color
    static let tourAccent       = Sand.s200.color

    // States
    static let stateIdle      = adaptive(.idleState)
    static let stateRunning   = Sand.s50.color
    static let stateWaiting   = Signal.attentionOnDark.color
    static let stateCompleted = Signal.successOnDark.color
    static let stateFailed    = Signal.failureOnDark.color
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
