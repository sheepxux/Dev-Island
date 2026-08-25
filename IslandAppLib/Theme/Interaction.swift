import SwiftUI
import AppKit

// Shared interaction affordances for elements inside the island window.

/// Hover-driven pointing-hand cursor for interactive panel elements.
///
/// Uses `NSCursor.set()` rather than the push/pop stack: our borderless,
/// non-key window doesn't participate in AppKit's cursor-rect machinery,
/// so a push whose matching pop is skipped (click morphs the hierarchy
/// before un-hover fires) permanently corrupts the stack. `set()` is
/// idempotent and self-healing — the window's mouse-tracking poll resets
/// the cursor at every silhouette boundary crossing anyway.
struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

/// Press feedback for panel buttons: a quick, subtle scale-down while the
/// mouse button is held. `.plain` (used before) gives zero visual response
/// to a press, which reads as "did that register?".
struct PressableButtonStyle: ButtonStyle {
    /// Full-size surfaces barely move; icon buttons can opt into a slightly
    /// stronger response without making rows visibly "bounce".
    var pressedScale: CGFloat = 0.997

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Primary action used by the Welcome Tour. The warm paper fill is deliberately
/// neutral: brand color belongs to small identifying details, not every CTA.
struct TourPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.controlLabel)
            .foregroundStyle(Palette.tourCanvas.opacity(isEnabled ? 1 : 0.55))
            .frame(width: 142, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.warmWhite.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct TourSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.controlLabel)
            .foregroundStyle(Palette.warmWhite.opacity(configuration.isPressed ? 0.5 : 0.72))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.warmWhite.opacity(configuration.isPressed ? 0.04 : 0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
