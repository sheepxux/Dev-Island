import SwiftUI

/// Shape of the collapsed Notch Bar: left extension + notch inset + right extension.
///
/// The hardware notch is itself black, so the "inset" is rendered as a
/// transparent gap — the shape only fills the two side extensions.
///
/// In Task 2 (Panel) the same notch geometry is reused for the S-curved
/// expansion, so the dimensions are kept in `NotchMetrics`.
struct NotchBarShape: Shape {
    var notchWidth: CGFloat = NotchMetrics.notchWidth

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sideWidth = (rect.width - notchWidth) / 2

        // Left extension
        path.addRect(CGRect(x: 0, y: 0, width: sideWidth, height: rect.height))

        // Right extension
        path.addRect(CGRect(
            x: rect.width - sideWidth,
            y: 0,
            width: sideWidth,
            height: rect.height
        ))

        return path
    }
}

#if PREVIEWS
#Preview("Shape outline") {
    NotchBarShape()
        .fill(Palette.notchBlack)
        .frame(width: NotchMetrics.totalWidth, height: NotchMetrics.barHeight)
        .padding(40)
        .background(Color.gray.opacity(0.2))
}
#endif
