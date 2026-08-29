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

/// A low-noise outlined action for compact island surfaces.
///
/// It is deliberately smaller and darker than the Welcome Tour CTA: the
/// empty panel should make the next step unmistakably interactive without
/// turning a quiet state into a promotional card.
struct IslandQuietActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        IslandQuietActionButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
        )
    }
}

private struct IslandQuietActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let reduceMotion: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(
                Palette.warmWhite.opacity(
                    configuration.isPressed ? 0.62 : (isHovering ? 0.90 : 0.76)
                )
            )
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        Palette.warmWhite.opacity(
                            configuration.isPressed ? 0.055 : (isHovering ? 0.070 : 0.035)
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                Palette.warmWhite.opacity(isHovering ? 0.16 : 0.095),
                                lineWidth: 0.75
                            )
                    }
            }
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (configuration.isPressed ? 0.985 : (isHovering ? 1.008 : 1))
            )
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Rectangle())
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hover
                ),
                value: isHovering
            )
            .onHover { isHovering = isEnabled && $0 }
            .pointingHandCursor(enabled: isEnabled)
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

/// Primary action used by the Welcome Tour. The warm paper fill is deliberately
/// neutral: brand color belongs to small identifying details, not every CTA.
struct TourPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        TourPrimaryButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
        )
    }
}

private struct TourPrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let reduceMotion: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(Typo.controlLabel)
            .foregroundStyle(Palette.tourCanvas.opacity(isEnabled ? 1 : 0.55))
            .frame(width: 142, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .scaleEffect(reduceMotion ? 1 : scale)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hover
                ),
                value: isHovering
            )
            .contentShape(Rectangle())
            .onHover { isHovering = isEnabled && $0 }
            .pointingHandCursor(enabled: isEnabled)
    }

    private var background: Color {
        if configuration.isPressed { return Palette.warmWhite.opacity(0.78) }
        return isHovering ? Color.white.opacity(0.98) : Palette.warmWhite
    }

    private var scale: CGFloat {
        if configuration.isPressed { return 0.995 }
        return isHovering && isEnabled ? 1.005 : 1
    }
}

struct TourSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        TourSecondaryButtonBody(
            configuration: configuration,
            reduceMotion: reduceMotion
        )
    }
}

private struct TourSecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let reduceMotion: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(Typo.controlLabel)
            .foregroundStyle(
                Palette.warmWhite.opacity(
                    configuration.isPressed ? 0.5 : (isHovering ? 0.86 : 0.72)
                )
            )
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        Palette.warmWhite.opacity(
                            configuration.isPressed ? 0.04 : (isHovering ? 0.055 : 0.025)
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                Palette.warmWhite.opacity(isHovering ? 0.15 : 0.085),
                                lineWidth: 0.75
                            )
                    )
            )
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (configuration.isPressed ? 0.995 : (isHovering ? 1.003 : 1))
            )
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hover
                ),
                value: isHovering
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}
