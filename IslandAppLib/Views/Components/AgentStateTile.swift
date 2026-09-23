import IslandCore
import SwiftUI

/// Each row's leading mark. The tile fill says which group the Agent is in;
/// the vendor's brand mark says who it is (`AgentBrand`, monogram fallback);
/// the island's nine-point signature returns only while the row is busy,
/// because a logo cannot show progress. Without a `source` the dots carry
/// the state alone, as they did before the rows carried logos.
struct AgentStateTile: View {
    let state: LocalAgentHookConnectionState?
    var isBusy = false
    var size: CGFloat = 28
    /// Task source whose brand mark identifies the row.
    var source: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * Palette.Window.Radius.tile / 28, style: .continuous)
                .fill(fill)
            if showsOutline {
                RoundedRectangle(cornerRadius: size * Palette.Window.Radius.tile / 28, style: .continuous)
                    .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
            }
            if let source, !isBusy {
                AgentLogoBadge(
                    source: source,
                    size: size * 0.8,
                    ink: dotColor,
                    badge: nil
                )
            } else {
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

    /// Ink for the vendor mark and, while busy, the dots.
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
