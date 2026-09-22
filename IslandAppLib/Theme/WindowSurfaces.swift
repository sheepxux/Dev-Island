import SwiftUI

// MARK: - Canvas

/// The window ground: one flat sheet of the icon's warm base. Nothing is
/// painted behind content to give a material something to refract — grouped
/// content lifts off this sheet as paper instead.
struct WindowCanvas: View {
    var body: some View {
        Palette.Window.canvas
            .ignoresSafeArea()
    }
}

// MARK: - Surfaces

enum WindowSurfaceTone {
    /// Navigation floating over the window. On macOS 26 and later this is
    /// the system's Liquid Glass, the material Apple reserves for the
    /// navigation layer; earlier systems get the same shape as one flat step
    /// deeper than the canvas.
    case sidebar
    /// Grouped content lifted off the canvas as paper.
    case raised
    /// A well nested inside raised paper.
    case inset
    /// The one group that asks for something.
    case attention
}

/// One depth cue per surface. Raised paper uses a stacked shadow whose first
/// layer is a ring, so the edge composites with whatever sits behind it;
/// wells separate by tone alone and the sidebar by its material.
private struct WindowSurface: ViewModifier {
    let radius: CGFloat
    let tone: WindowSurfaceTone

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if tone == .sidebar {
            sidebar(content, in: shape)
        } else {
            content
                .background { shape.fill(fill) }
                .clipShape(shape)
                .overlay {
                    if let ring {
                        shape.strokeBorder(ring, lineWidth: 0.75)
                    }
                }
                .compositingGroup()
                .shadow(color: contact, radius: 1.5, y: 1)
                .shadow(color: ambient, radius: 6, y: 4)
        }
    }

    @ViewBuilder
    private func sidebar(_ content: Content, in shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(Sand.s100.opacity(0.55).color),
                in: shape
            )
        } else {
            content.background { shape.fill(Palette.Window.canvasDeep) }
        }
        #else
        content.background { shape.fill(Palette.Window.canvasDeep) }
        #endif
    }

    private var fill: Color {
        switch tone {
        case .sidebar:   return Palette.Window.canvasDeep
        case .raised:    return Palette.Window.surface
        case .inset:     return Palette.Window.canvas
        case .attention: return Palette.Window.attentionWash
        }
    }

    private var ring: Color? {
        switch tone {
        case .raised:    return Palette.Window.ring
        case .attention: return Palette.Window.attentionHair
        case .sidebar, .inset: return nil
        }
    }

    private var contact: Color {
        tone == .raised ? Sand.s900.opacity(0.05).color : .clear
    }

    private var ambient: Color {
        tone == .raised ? Sand.s900.opacity(0.04).color : .clear
    }
}

extension View {
    func windowSurface(radius: CGFloat, tone: WindowSurfaceTone) -> some View {
        modifier(WindowSurface(radius: radius, tone: tone))
    }
}

// MARK: - Rules

/// A separating rule one physical pixel tall: 0.5pt on Retina, 1pt on a
/// standard display. Rules separate rows; they never signal depth.
struct WindowDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Palette.Window.divider)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Every window button. One primary per view (the icon's black tile as a
/// capsule), a paper capsule for the rest, and a text-only quiet action for
/// the least important end of a row.
///
/// Destructive intent comes from the platform, `Button(role: .destructive)`,
/// and changes the ink, never the fill.
struct WindowButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case secondary
        case quiet
    }

    enum Size {
        case regular
        case large
    }

    let role: Role
    let size: Size

    init(_ role: Role, size: Size = .regular) {
        self.role = role
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        WindowButtonBody(configuration: configuration, style: self)
    }
}

extension ButtonStyle where Self == WindowButtonStyle {
    /// `.buttonStyle(.window(.secondary))`, named like the system's own
    /// `.bordered` and `.borderedProminent`.
    static func window(_ role: WindowButtonStyle.Role, size: WindowButtonStyle.Size = .regular) -> WindowButtonStyle {
        WindowButtonStyle(role, size: size)
    }
}

private struct WindowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let style: WindowButtonStyle

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isDestructive: Bool { configuration.role == .destructive }

    var body: some View {
        label
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background { background }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressedScale)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.hoverHighlight),
                value: isHovering
            )
            .onHover { isHovering = isEnabled && $0 }
            .pointingHandCursor(enabled: isEnabled)
    }

    @ViewBuilder
    private var label: some View {
        switch style.size {
        case .regular:
            configuration.label.font(style.role == .primary ? Typo.controlStrong : Typo.control)
        case .large:
            configuration.label.font(Typo.controlLarge)
        }
    }

    private var height: CGFloat {
        switch (style.role, style.size) {
        case (.quiet, _): return 28
        case (_, .regular): return 28
        case (_, .large): return 40
        }
    }

    private var horizontalPadding: CGFloat {
        switch (style.role, style.size) {
        case (.quiet, _): return 2
        case (_, .regular): return 13
        case (_, .large): return 20
        }
    }

    private var pressedScale: CGFloat {
        guard configuration.isPressed, style.role != .quiet else { return 1 }
        return InteractionFeedbackPolicy.pressScale(
            isPressed: true,
            pressedScale: 0.96,
            reduceMotion: reduceMotion
        )
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.Window.textPlaceholder }
        switch style.role {
        case .primary:
            return Palette.Window.onInk
        case .secondary, .quiet:
            if isDestructive { return Palette.Window.destructive }
            if style.role == .quiet, !isHovering, !configuration.isPressed {
                return Palette.Window.textSecondary
            }
            return Palette.Window.ink
        }
    }

    @ViewBuilder
    private var background: some View {
        let capsule = Capsule(style: .continuous)
        switch style.role {
        case .primary:
            capsule.fill(isEnabled ? primaryFill : Palette.Window.canvasDeep)
        case .secondary:
            capsule
                .fill(configuration.isPressed ? Palette.Window.canvasDeep : Palette.Window.surface)
                .overlay {
                    capsule.strokeBorder(
                        isHovering ? Palette.Window.hairlineStrong : Palette.Window.hairline,
                        lineWidth: 0.75
                    )
                }
        case .quiet:
            Color.clear
        }
    }

    private var primaryFill: Color {
        if configuration.isPressed { return Palette.Window.inkSoft }
        return isHovering ? Palette.Window.inkHover : Palette.Window.ink
    }
}
