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
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
