import AppKit
import SwiftUI

extension Palette {
    /// Settings and other conventional windows.
    ///
    /// The product has two layers that mirror the app icon: the island is the
    /// black inner tile and stays on `Palette`'s near-black tokens; windows are
    /// the warm off-white outer tile. Everything here is ink on that tile. The
    /// only chroma is the attention amber shared with the island's waiting
    /// state; destructive actions get a text color, never a filled button.
    enum Window {
        // Ground
        static let canvas        = Color(hex: 0xEFEBE2)
        static let canvasDeep    = Color(hex: 0xE4DFD3)
        static let canvasLight   = Color(hex: 0xF7F4EE)

        // Ink
        static let ink           = Color(hex: 0x141414)
        static let inkSoft       = Color(hex: 0x2A2925)
        static let onInk         = Color(hex: 0xF1EEE6)
        static let textSecondary = adaptive(standard: 0x5F5C55, increased: 0x45433D)
        static let textTertiary  = adaptive(standard: 0x656158, increased: 0x4F4B44)

        // Rules and glass
        static let hairline       = adaptive(standard: 0x141414, increased: 0x141414, alpha: 0.08, increasedAlpha: 0.22)
        static let hairlineStrong = adaptive(standard: 0x141414, increased: 0x141414, alpha: 0.16, increasedAlpha: 0.34)
        static let glass          = Color.white.opacity(0.58)
        static let glassDeep      = Color.white.opacity(0.40)
        static let glassHighlight = Color.white.opacity(0.75)
        static let field          = Color.white.opacity(0.70)
        static let hover          = Color(hex: 0x141414).opacity(0.04)
        static let pressed        = Color(hex: 0x141414).opacity(0.08)
        static let selected       = Color(hex: 0x141414).opacity(0.06)

        // Semantic ink on the beige ground (deeper than the island's neon
        // states, which were tuned for black).
        static let attention      = Color(hex: 0xE29A2E)
        static let attentionText  = Color(hex: 0x8F570E)
        static let attentionTint  = Color(hex: 0xE29A2E).opacity(0.14)
        static let attentionHair  = Color(hex: 0xE29A2E).opacity(0.45)
        static let destructive    = Color(hex: 0xA0421E)
        static let stateRunning   = Color(hex: 0x185FA5)
        static let stateCompleted = Color(hex: 0x3B6D11)
        static let stateWaiting   = Color(hex: 0x8F570E)
        static let stateFailed    = Color(hex: 0xA32D2D)

        /// Corner radii nest concentrically: window 22, pane 18, group 14,
        /// tile 8, control capsule.
        enum Radius {
            static let pane: CGFloat = 18
            static let group: CGFloat = 14
            static let inset: CGFloat = 11
            static let tile: CGFloat = 8
        }

        /// Increased Contrast darkens quiet ink instead of brightening it,
        /// because the ground is light. Same system switch as the island.
        private static func adaptive(
            standard: UInt32,
            increased: UInt32,
            alpha: Double = 1,
            increasedAlpha: Double? = nil
        ) -> Color {
            Color(nsColor: NSColor(name: nil) { _ in
                let strong = InterfaceContrastPolicy.systemPrefersIncreasedContrast
                return InterfaceContrastPolicy.Tone(
                    hex: strong ? increased : standard,
                    alpha: strong ? (increasedAlpha ?? alpha) : alpha
                ).nsColor
            })
        }
    }
}

/// Relative luminance and contrast helpers for the window palette, exposed so
/// tests can pin the ink/ground ratios the design relies on.
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

    /// The hex values behind the tokens above, kept next to them so the test
    /// and the palette cannot drift apart silently.
    static let canvas: UInt32 = 0xEFEBE2
    static let canvasDeep: UInt32 = 0xE4DFD3
    static let ink: UInt32 = 0x141414
    static let onInk: UInt32 = 0xF1EEE6
    static let textSecondary: UInt32 = 0x5F5C55
    static let textSecondaryIncreased: UInt32 = 0x45433D
    static let textTertiary: UInt32 = 0x656158
    static let attentionText: UInt32 = 0x8F570E
    static let destructive: UInt32 = 0xA0421E
    static let stateRunning: UInt32 = 0x185FA5
    static let stateCompleted: UInt32 = 0x3B6D11
    static let stateFailed: UInt32 = 0xA32D2D
}

extension BarState {
    /// The same five states as `color`, deepened for the beige window ground
    /// where the island's neon values would wash out.
    var windowColor: Color {
        switch self {
        case .idle:      return Palette.Window.textTertiary
        case .running:   return Palette.Window.stateRunning
        case .waiting:   return Palette.Window.attention
        case .completed: return Palette.Window.stateCompleted
        case .failed:    return Palette.Window.stateFailed
        }
    }
}
