import SwiftUI

/// Outline of the expanded panel — a single solid silhouette, flat top,
/// continuous-curvature bottom corners. On notched displays we deliberately
/// do NOT cut out the camera region: the physical hole hides whatever we
/// draw inside it, and overpainting the small panel wedges at the notch's
/// bottom-outer corners removes the C-shaped seams that a rectangular
/// cutout would otherwise leave against the notch's curved edge.
///
/// `notchWidth` / `notchHeight` are kept on the type for source compat;
/// they no longer affect rendering and can be removed in a follow-up.
struct NotchPanelShape: Shape {
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    var cornerRadius: CGFloat = NotchMetrics.panelCornerRadius

    /// Interpolate `cornerRadius` during `withAnimation` so the bar↔panel
    /// morph stays consistent with its frame size at every step. Without
    /// this the radius snaps to its target on the first frame — when the
    /// shape is still bar-sized (~39pt tall), a 22pt bottom radius briefly
    /// over-rounds the silhouette, leaving a visible seam at the bottom
    /// edge as the spring expands.
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        ).path(in: rect)
    }
}

#if PREVIEWS
#Preview("Panel — no notch") {
    NotchPanelShape()
        .fill(Palette.notchBlack)
        .frame(width: 380, height: 320)
        .padding(40)
        .background(Color.gray.opacity(0.2))
}

#Preview("Panel — notched") {
    NotchPanelShape(notchWidth: 200, notchHeight: 32)
        .fill(Palette.notchBlack)
        .frame(width: 420, height: 320)
        .padding(40)
        .background(Color.gray.opacity(0.2))
}
#endif
