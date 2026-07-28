import SwiftUI

/// Shape of the collapsed Notch Bar — a single solid silhouette flush with
/// the screen top, rounded only at the bottom. The hardware notch's
/// physical hole hides whatever we draw inside its bounds, and the small
/// panel wedges at its bottom-outer corners get safely overpainted (the
/// menubar reserves no items in that region), so no cutout is needed.
struct NotchBarShape: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var cornerRadius: CGFloat = NotchMetrics.cornerRadius

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
