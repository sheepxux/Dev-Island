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
    var isEnabled = true

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering && isEnabled {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursor(isEnabled: enabled))
    }
}

/// Press feedback for panel buttons: a quick, subtle scale-down while the
/// mouse button is held. `.plain` (used before) gives zero visual response
/// to a press, which reads as "did that register?".
struct PressableButtonStyle: ButtonStyle {
    /// Full-size surfaces barely move; icon buttons can opt into a slightly
    /// stronger response without making rows visibly "bounce".
    var pressedScale: CGFloat = 0.997

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: pressedScale,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.press
                ),
                value: configuration.isPressed
            )
    }
}

/// A low-noise outlined capsule for compact island surfaces. The empty panel
/// uses it so the next step reads as interactive without turning a quiet
/// state into a promotion.
struct IslandQuietActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandQuietActionButtonBody(configuration: configuration)
    }
}

private struct IslandQuietActionButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let capsule = Capsule()
        configuration.label
            .font(Typo.islandControl)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                capsule
                    .fill(Palette.warmWhite.opacity(configuration.isPressed ? 0.10 : (isHovering ? 0.07 : 0.035)))
                    .overlay { capsule.strokeBorder(Palette.hairline, lineWidth: 0.75) }
            }
            .contentShape(capsule)
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: 0.96,
                    reduceMotion: reduceMotion
                )
            )
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.hoverHighlight),
                value: isHovering
            )
            .onHover { isHovering = isEnabled && $0 }
            .pointingHandCursor(enabled: isEnabled)
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.textTertiary }
        return isHovering || configuration.isPressed ? Palette.warmWhite : Palette.textSecondary
    }
}

/// Icon-only island controls (history, settings). The glyph stays small; the
/// hit area is a 28pt circle, the macOS size for a toolbar control.
struct IslandIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandIconButtonBody(configuration: configuration)
    }
}

private struct IslandIconButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovering || configuration.isPressed ? Palette.warmWhite : Palette.textSecondary)
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(Palette.warmWhite.opacity(configuration.isPressed ? 0.10 : (isHovering ? 0.06 : 0)))
            }
            .contentShape(Circle())
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: 0.96,
                    reduceMotion: reduceMotion
                )
            )
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.hoverHighlight),
                value: isHovering
            )
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}

/// Pure interaction policy shared by button styles and covered without
/// relying on a rendered SwiftUI frame. Reduced Motion preserves immediate
/// opacity/color acknowledgement while removing press-scale geometry.
enum InteractionFeedbackPolicy {
    static func pressScale(
        isPressed: Bool,
        pressedScale: CGFloat,
        reduceMotion: Bool
    ) -> CGFloat {
        guard isPressed, Motion.allowsSpatialFeedback(reduceMotion) else {
            return 1
        }
        return pressedScale
    }
}
