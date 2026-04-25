import SwiftUI

/// Shape of the collapsed Notch Bar — ONE connected outline that protrudes
/// `bottomOverhang` below the hardware notch, with a rectangular cutout at
/// top center matching the notch dimensions.
///
/// Drawn as `outerShape.subtracting(notchCutout)` so the bottom corners get
/// continuous-curvature rounding (Apple squircle) while the cutout edges
/// stay sharp. The S-curve at the cutout's bottom corners is layered in
/// Task 2 with the panel.
struct NotchBarShape: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var cornerRadius: CGFloat = NotchMetrics.cornerRadius

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

        let cutoutX = (rect.width - notchWidth) / 2
        let cutoutRect = CGRect(
            x: cutoutX,
            y: 0,
            width: notchWidth,
            height: notchHeight
        )
        let cutout = Path(cutoutRect)

        return outer.subtracting(cutout)
    }
}

#if PREVIEWS
#Preview("Notch shape — overhang + cutout") {
    VStack(spacing: 24) {
        NotchBarShape(notchWidth: 200, notchHeight: 32)
            .fill(Palette.notchBlack)
            .frame(width: 380, height: 39)  // 32 notch + 7 overhang

        // With a wider notch (16" class)
        NotchBarShape(notchWidth: 220, notchHeight: 38)
            .fill(Palette.notchBlack)
            .frame(width: 400, height: 45)
    }
    .padding(40)
    .background(Color.gray.opacity(0.2))
}
#endif
