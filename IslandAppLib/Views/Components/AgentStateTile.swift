import IslandCore
import SwiftUI

/// The island's nine-point signature as each row's leading mark. The tile
/// fill says which group the Agent is in; the dots say how alive it is.
struct AgentStateTile: View {
    let state: LocalAgentHookConnectionState?
    var isBusy = false
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * Palette.Window.Radius.tile / 28, style: .continuous)
                .fill(fill)
            if showsOutline {
                RoundedRectangle(cornerRadius: size * Palette.Window.Radius.tile / 28, style: .continuous)
                    .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
            }
            AnimatedDotMatrixMark(
                color: dotColor,
                size: size * 0.5,
                motion: motion,
                pattern: pattern,
                intensity: intensity,
                isAnimated: isAnimated && !reduceMotion
            )
            .frame(width: size * 0.64, height: size * 0.64)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var effectiveState: LocalAgentHookConnectionState? { isBusy ? nil : state }

    private var fill: Color {
        switch effectiveState {
        case .connected?: return Palette.Window.ink
        case .configured?, .updateRequired?: return Palette.Window.attention
        case .disconnected?, nil: return Palette.Window.canvasDeep
        }
    }

    private var showsOutline: Bool {
        switch effectiveState {
        case .connected?, .configured?, .updateRequired?: return false
        case .disconnected?, nil: return true
        }
    }

    private var dotColor: Color {
        switch effectiveState {
        case .connected?: return Palette.Window.onInk
        case .configured?, .updateRequired?: return Palette.Window.ink
        case .disconnected?: return Palette.Window.textTertiary
        case nil: return Palette.Window.textSecondary
        }
    }

    private var pattern: DotMatrixMark.Pattern {
        switch effectiveState {
        case .connected?: return .plus
        case .configured?, .updateRequired?: return .ring
        case .disconnected?: return .field
        case nil: return .orbit
        }
    }

    private var motion: DotMatrixMark.MotionStyle {
        switch effectiveState {
        case .configured?, .updateRequired?: return .attention
        case nil: return .orbiting
        case .connected?, .disconnected?: return .still
        }
    }

    private var intensity: Double {
        switch effectiveState {
        case .connected?, .configured?, .updateRequired?: return 1
        case .disconnected?: return 0.9
        case nil: return 0.96
        }
    }

    private var isAnimated: Bool {
        switch effectiveState {
        case .configured?, .updateRequired?, nil: return true
        case .connected?, .disconnected?: return false
        }
    }
}

