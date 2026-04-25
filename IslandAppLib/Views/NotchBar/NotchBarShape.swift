import SwiftUI

/// Shape of the collapsed Notch Bar — TWO subpaths, one per side extension,
/// each with a rounded outer-bottom corner (the inner edge stays sharp; the
/// S-curve transition into the notch lands in Task 2 with the panel).
///
/// The hardware notch fills the corridor in the middle, so we leave it
/// transparent.
struct NotchBarShape: Shape {
    var notchWidth: CGFloat
    var cornerRadius: CGFloat = NotchMetrics.cornerRadius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sideWidth = (rect.width - notchWidth) / 2
        let r = min(cornerRadius, rect.height, sideWidth / 2)

        // Left extension — rounded bottom-LEFT corner only
        path.addPath(extensionPath(
            x: 0,
            width: sideWidth,
            height: rect.height,
            roundedBottomLeft: r,
            roundedBottomRight: 0
        ))

        // Right extension — rounded bottom-RIGHT corner only
        path.addPath(extensionPath(
            x: rect.width - sideWidth,
            width: sideWidth,
            height: rect.height,
            roundedBottomLeft: 0,
            roundedBottomRight: r
        ))

        return path
    }

    /// One side extension. Top edge flat (flush with screen edge); bottom
    /// corners rounded individually so we can keep the inner edge sharp.
    private func extensionPath(
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        roundedBottomLeft bl: CGFloat,
        roundedBottomRight br: CGFloat
    ) -> Path {
        var p = Path()
        let minX = x, maxX = x + width
        let minY: CGFloat = 0, maxY = height

        // Flat top: TL -> TR
        p.move(to: CGPoint(x: minX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY))

        // Right edge down, optionally rounding the bottom-right corner
        if br > 0 {
            p.addLine(to: CGPoint(x: maxX, y: maxY - br))
            p.addArc(
                center: CGPoint(x: maxX - br, y: maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: maxX, y: maxY))
        }

        // Bottom edge over to bottom-left, optionally rounding
        if bl > 0 {
            p.addLine(to: CGPoint(x: minX + bl, y: maxY))
            p.addArc(
                center: CGPoint(x: minX + bl, y: maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: minX, y: maxY))
        }

        // Up to top-left and close
        p.addLine(to: CGPoint(x: minX, y: minY))
        p.closeSubpath()
        return p
    }
}

#if PREVIEWS
#Preview("Notch shape — rounded outer bottom") {
    NotchBarShape(notchWidth: NotchMetrics.defaultNotchWidth)
        .fill(Palette.notchBlack)
        .frame(width: NotchMetrics.defaultNotchWidth + 2 * NotchMetrics.sideExtension, height: 32)
        .padding(40)
        .background(Color.gray.opacity(0.2))
}
#endif
