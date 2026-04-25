import SwiftUI

/// Shape of the collapsed Notch Bar — TWO subpaths, one per side extension,
/// each with a continuous-curvature ("squircle") outer-bottom corner.
///
/// The hardware notch fills the corridor in the middle so we leave it
/// transparent. The S-curve transition into the notch lands in Task 2 with
/// the panel.
struct NotchBarShape: Shape {
    var notchWidth: CGFloat
    var cornerRadius: CGFloat = NotchMetrics.cornerRadius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sideWidth = (rect.width - notchWidth) / 2
        let r = min(cornerRadius, rect.height, sideWidth / 2)

        // Left extension — round only bottom-LEADING corner (outer side).
        let leftRect = CGRect(x: 0, y: 0, width: sideWidth, height: rect.height)
        let leftCorners = RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: r,
            bottomTrailing: 0,
            topTrailing: 0
        )
        path.addPath(UnevenRoundedRectangle(
            cornerRadii: leftCorners,
            style: .continuous
        ).path(in: leftRect))

        // Right extension — round only bottom-TRAILING corner (outer side).
        let rightRect = CGRect(
            x: rect.width - sideWidth,
            y: 0,
            width: sideWidth,
            height: rect.height
        )
        let rightCorners = RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: 0,
            bottomTrailing: r,
            topTrailing: 0
        )
        path.addPath(UnevenRoundedRectangle(
            cornerRadii: rightCorners,
            style: .continuous
        ).path(in: rightRect))

        return path
    }
}

#if PREVIEWS
#Preview("Notch shape — continuous corners") {
    VStack(spacing: 24) {
        NotchBarShape(notchWidth: NotchMetrics.defaultNotchWidth, cornerRadius: 14)
            .fill(Palette.notchBlack)
            .frame(width: NotchMetrics.defaultNotchWidth + 2 * NotchMetrics.sideExtension, height: 32)

        NotchBarShape(notchWidth: NotchMetrics.defaultNotchWidth, cornerRadius: 22)
            .fill(Palette.notchBlack)
            .frame(width: NotchMetrics.defaultNotchWidth + 2 * NotchMetrics.sideExtension, height: 38)
    }
    .padding(40)
    .background(Color.gray.opacity(0.2))
}
#endif
