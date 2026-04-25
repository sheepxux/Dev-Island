import SwiftUI

/// Outline of the expanded panel.
///
/// - Top edge: flat (flush with screen top), continuous with the bar's
///   flush-top design.
/// - Bottom corners: continuous-curvature (squircle) rounded.
/// - Optional notch cutout at top center for notched displays. The S-curve
///   refinement lands in a follow-up commit; first cut uses a sharp
///   rectangular cutout that the bar's same dimensions match.
struct NotchPanelShape: Shape {
    /// 0 ⇒ no cutout (synthetic-notch / no-notch mode).
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    var cornerRadius: CGFloat = NotchMetrics.panelCornerRadius

    func path(in rect: CGRect) -> Path {
        let outer = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        ).path(in: rect)

        guard notchWidth > 0, notchHeight > 0 else { return outer }

        let cutoutX = (rect.width - notchWidth) / 2
        let cutoutRect = CGRect(
            x: cutoutX,
            y: 0,
            width: notchWidth,
            height: notchHeight
        )
        return outer.subtracting(Path(cutoutRect))
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
