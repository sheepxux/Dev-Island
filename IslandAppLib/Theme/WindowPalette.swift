import AppKit
import IslandCore
import SwiftUI

extension Palette {
    /// Settings, Welcome, History and every other conventional window.
    ///
    /// The product has two layers that mirror the app icon: the island is the
    /// black terminal tile and reads from the dark end of `Sand`; windows are
    /// the warm off-white base and read from the light end. A window is one
    /// flat sheet of that base. Raised paper appears only where content is
    /// grouped, and amber appears only where something asks for the user.
    enum Window {
        // Ground
        /// The window itself.
        static let canvas = Sand.s50.color
        /// Sidebars and sunken wells, one step deeper than the canvas.
        static let canvasDeep = Sand.s100.color
        /// Raised paper for grouped content.
        static let surface = Sand.s0.color
        /// Text fields and other editable wells.
        static let field = Sand.s0.color

        // Ink
        static let ink = Sand.s900.color
        /// The primary capsule under the pointer.
        static let inkHover = Sand.s850.color
        /// The primary capsule while pressed.
        static let inkSoft = Sand.s800.color
        static let onInk = Sand.s50.color
        static let textSecondary = adaptive(standard: Sand.s700, increased: Sand.s800)
        static let textTertiary = adaptive(standard: Sand.s600, increased: Sand.s700)
        /// Placeholders and disabled labels only — never information.
        static let textPlaceholder = Sand.s500.color

        // Rules and interaction washes. Alpha on a light ground so one token
        // recedes over canvas, paper and the attention wash alike.
        static let hairline = adaptive(standard: Sand.s900.opacity(0.09), increased: Sand.s900.opacity(0.22))
        static let hairlineStrong = adaptive(standard: Sand.s900.opacity(0.15), increased: Sand.s900.opacity(0.32))
        /// Row separators, drawn one physical pixel tall by `WindowDivider`,
        /// so the alpha sits a step above the 0.75pt `hairline`.
        static let divider = adaptive(standard: Sand.s900.opacity(0.13), increased: Sand.s900.opacity(0.30))
        /// The first layer of raised paper's shadow stack: the edge.
        static let ring = adaptive(standard: Sand.s900.opacity(0.07), increased: Sand.s900.opacity(0.24))
        static let hover = Sand.s900.opacity(0.045).color
        static let pressed = Sand.s900.opacity(0.08).color
        /// Shadow ink for objects lifted off the light ground (the Welcome
        /// coaching card); callers set the opacity per layer.
        static let shadow = Sand.s1000.color
        /// The Welcome stage (`WelcomeTutorialCanvas`): a light, see-through
        /// wash from the menu bar's lower edge to the bottom of the screen, so
        /// the user's desktop ghosts through (2026-09-24, replacing the 0.96
        /// sheet and its bloom). Opaque under Reduce Transparency. No text
        /// ever sits on it; every string lives on the card's opaque `canvas`.
        /// Tune alpha only, never the stops: s150/s200 read grey, not light.
        static let stage = translucent(standard: Sand.s50, alpha: 0.70)
        static let stageDeep = translucent(standard: Sand.s100, alpha: 0.78)
        /// The dark ground behind whatever the tour points at
        /// (`WelcomeTutorialCanvas` plate and stem): the expanded panel, or a
        /// shelf hanging from the band under an in-band target. Read from the
        /// island's end of the ramp, three steps above the panel (s950, with
        /// `islandBorder`) so the black island sits on it rather than melting
        /// into it (judged live 2026-09-24: on s850 the collapsed island and
        /// its shelf read as one blob). Nearly opaque so the pulse's contrast
        /// never depends on the desktop and no text ghosts through; opaque
        /// under Reduce Transparency; one step darker under Increase
        /// Contrast. Never text.
        static let stagePlate = translucent(
            standard: Sand.s800,
            increased: Sand.s850,
            alpha: 0.97,
            increasedAlpha: 1.0
        )
        /// The light pulse travelling the stem toward the card
        /// (`WelcomeTutorialCanvas`). A mark, never text: over 10:1 on
        /// `stagePlate` whatever the desktop, higher under Increase Contrast.
        static let stageSignal = Sand.s50.color

        // Signals on the light ground
        static let attention = Signal.attentionFill.color
        static let attentionText = Signal.attentionOnLight.color
        static let attentionWash = Signal.attentionWash.color
        static let attentionHair = Signal.attentionOnLight.opacity(0.32).color
        static let destructive = Signal.failureOnLight.color
        /// Running work is neutral; its motion carries the meaning.
        static let stateRunning = Sand.s700.color
        static let stateCompleted = Signal.successOnLight.color
        static let stateWaiting = Signal.attentionOnLight.color
        static let stateFailed = Signal.failureOnLight.color

        /// Radii are chosen per layer and derived where layers nest
        /// (inner = outer − padding): pane 18 around a 10pt inset, groups 14,
        /// inset wells 10, tiles 8, controls are capsules.
        enum Radius {
            static let pane: CGFloat = 18
            static let group: CGFloat = 14
            static let inset: CGFloat = 10
            static let tile: CGFloat = 8
        }

        /// Increased Contrast darkens quiet ink on a light ground instead of
        /// brightening it. Same system switch as the island.
        private static func adaptive(standard: OKLCH, increased: OKLCH) -> Color {
            Color(nsColor: NSColor(name: nil) { _ in
                InterfaceContrastPolicy.systemPrefersIncreasedContrast
                    ? increased.nsColor
                    : standard.nsColor
            })
        }

        /// See-through stage surfaces. Reduce Transparency is the system
        /// switch that governs translucent surfaces, so it makes them opaque;
        /// Increase Contrast moves lightness one step, as `adaptive` does.
        private static func translucent(
            standard: OKLCH,
            increased: OKLCH? = nil,
            alpha: Double,
            increasedAlpha: Double? = nil
        ) -> Color {
            Color(nsColor: NSColor(name: nil) { _ in
                let increasedContrast = InterfaceContrastPolicy.systemPrefersIncreasedContrast
                let base = increasedContrast ? (increased ?? standard) : standard
                let resolvedAlpha: Double
                if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    resolvedAlpha = 1
                } else {
                    resolvedAlpha = increasedContrast ? (increasedAlpha ?? alpha) : alpha
                }
                return base.opacity(resolvedAlpha).nsColor
            })
        }
    }
}

/// Relative luminance and contrast helpers for the window palette, exposed so
/// tests can pin the ink/ground ratios the design relies on. The values are
/// read from the same OKLCH declarations the palette renders, so the test and
/// the palette cannot drift apart.
enum WindowPaletteContrast {
    static func relativeLuminance(hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }

    static func ratio(_ foreground: UInt32, on background: UInt32) -> Double {
        let lighter = max(relativeLuminance(hex: foreground), relativeLuminance(hex: background))
        let darker = min(relativeLuminance(hex: foreground), relativeLuminance(hex: background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static let canvas = Sand.s50.hex
    static let canvasDeep = Sand.s100.hex
    static let surface = Sand.s0.hex
    /// The Welcome stage's opaque stops: the wash is see-through, so these
    /// are the grounds it becomes under Reduce Transparency. No text sits on
    /// them, but they stay inside the ink ratios so the sheet is never a
    /// surprise.
    static let stage = Sand.s50.hex
    static let stageDeep = Sand.s100.hex
    /// The plate the tour's pulse travels on, and the island that sits on it.
    static let stagePlate = Sand.s800.hex
    static let stagePlateIncreased = Sand.s850.hex
    static let stageSignal = Sand.s50.hex
    static let islandOnStage = Sand.s950.hex
    static let ink = Sand.s900.hex
    static let onInk = Sand.s50.hex
    static let textSecondary = Sand.s700.hex
    static let textSecondaryIncreased = Sand.s800.hex
    static let textTertiary = Sand.s600.hex
    static let attentionText = Signal.attentionOnLight.hex
    static let attentionWash = Signal.attentionWash.hex
    static let destructive = Signal.failureOnLight.hex
    static let stateRunning = Sand.s700.hex
    static let stateCompleted = Signal.successOnLight.hex
    static let stateFailed = Signal.failureOnLight.hex
}

extension TaskStatus {
    /// Status marks drawn on a light window ground (History). The island's
    /// own colors are tuned for black: its neutral running white would
    /// vanish on paper, and marks need 3:1 against their ground.
    var windowColor: Color {
        switch self {
        case .running:   return Palette.Window.stateRunning
        case .waiting:   return Palette.Window.stateWaiting
        case .completed: return Palette.Window.stateCompleted
        case .failed:    return Palette.Window.stateFailed
        }
    }
}

extension BarState {
    /// The same five states as `color`, drawn as marks on the light window
    /// ground. Waiting uses the amber ink, not the tile fill, so the dots
    /// keep 3:1 against paper.
    var windowColor: Color {
        switch self {
        case .idle:      return Palette.Window.textTertiary
        case .running:   return Palette.Window.stateRunning
        case .waiting:   return Palette.Window.stateWaiting
        case .completed: return Palette.Window.stateCompleted
        case .failed:    return Palette.Window.stateFailed
        }
    }
}
