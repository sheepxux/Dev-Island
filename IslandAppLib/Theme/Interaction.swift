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
    /// 0.98 for card-sized surfaces; icons pass something smaller-delta.
    var pressedScale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// High-contrast action used by the Welcome Tour. The fill, border and
/// shadow all react together, which makes the control feel like one solid
/// material instead of an animated label on a static rectangle.
struct TourPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.tourAccent, Palette.tourViolet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
                    )
                    .shadow(
                        color: Palette.tourAccent.opacity(configuration.isPressed ? 0.16 : 0.28),
                        radius: configuration.isPressed ? 5 : 11,
                        y: configuration.isPressed ? 1 : 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct TourSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.78))
            .padding(.horizontal, 15)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0.075))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
