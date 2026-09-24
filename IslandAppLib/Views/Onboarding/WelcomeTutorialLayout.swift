import CoreGraphics

/// Pure placement for the full-screen Welcome tutorial: the dark plate that
/// hangs from the menu bar's lower edge behind whatever the tour points at,
/// the coaching card under it, and the stem that ties the two together.
/// Everything is in the canvas's own top-left coordinate space, where y = 0
/// is the menu bar's lower edge, and free of AppKit/SwiftUI so the geometry
/// stays regression-testable.
enum WelcomeTutorialLayout {
    /// Margin of the plate around an expanded panel (sides and bottom).
    static let plateInset: CGFloat = 16
    /// Concentric with the panel it wraps: inner = outer − padding.
    static let plateCornerRadius: CGFloat = NotchMetrics.panelCornerRadius + plateInset
    /// A target this close to the band's lower edge is still "in the band":
    /// the collapsed island grows by the hover boost below the menu bar
    /// while the pointer is on it, and must keep its shelf rather than turn
    /// into a 2pt-tall panel wrap.
    static let inBandTolerance: CGFloat = max(
        NotchMetrics.hoverHeightBoostNotched,
        NotchMetrics.hoverHeightBoostCapsule
    )
    /// The shelf hanging from the band under a target that sits inside the
    /// menu bar (the collapsed island, the menu-bar item).
    static let shelfInset: CGFloat = 14
    static let shelfHeight: CGFloat = 40
    static let shelfCornerRadius: CGFloat = shelfHeight / 2
    /// Vertical gap between the plate and the card, spanned by the stem.
    static let connectorLength: CGFloat = 28
    /// Where the card's top sits on every step without an expanded panel, so
    /// the card slides along one line between steps.
    static let readingLine: CGFloat = shelfHeight + connectorLength
    static let stemWidth: CGFloat = 2
    static let pulseWidth: CGFloat = 2
    static let pulseLength: CGFloat = 14
    /// Minimum distance between the card and the canvas edges.
    static let edgeMargin: CGFloat = 24
    /// The stem may not touch the card's rounded corners.
    static let connectorCornerClearance: CGFloat = 32

    struct Plate: Equatable {
        var rect: CGRect
        /// Bottom corners only; the top edge is always the band's lower edge.
        var cornerRadius: CGFloat
    }

    struct Connector: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    struct Placement: Equatable {
        var plate: Plate?
        var card: CGRect
        var connector: Connector?
    }

    /// One pass of the pulse along the stem: how far it has travelled
    /// (0 at the plate, 1 at the card) and how visible it is.
    struct Pulse: Equatable {
        var progress: Double
        var opacity: Double
    }

    /// The screen minus its menu-bar band: the frame the tour window fills.
    /// AppKit frames have a bottom-left origin, so the band comes off the
    /// top by shortening the height.
    static func stageFrame(screenFrame: CGRect, menuBarHeight: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: max(0, screenFrame.height - menuBarHeight)
        )
    }

    /// AppKit screen rects have a bottom-left origin; the canvas fills the
    /// stage and reads top-left.
    static func canvasRect(fromScreenRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// A target the tour can point at: present, not empty, and at least
    /// partly inside `frame` (the screen for the island; the menu-bar band
    /// for the menu-bar item, which the system may have moved off screen or
    /// into the overflow). Anything else falls back to the no-target layout.
    static func usableTarget(_ rect: CGRect?, within frame: CGRect) -> CGRect? {
        guard let rect, !rect.isEmpty, rect.intersects(frame) else { return nil }
        return rect
    }

    /// Places the card under `target`, centered on it and clamped inside the
    /// canvas, with the plate above it: a shelf hanging from the band for a
    /// target inside the menu bar (a zero-height mark on the top edge), a
    /// wrap for a panel that reaches below it (a target within
    /// `inBandTolerance` of the band still counts as inside it). Without a
    /// target the card sits
    /// centered on the reading line with no plate. A card that would run off
    /// the bottom is pinned to the bottom margin instead of overlapping the
    /// target, and loses its stem.
    static func placement(target: CGRect?, cardSize: CGSize, canvas: CGRect) -> Placement {
        guard let target else {
            let origin = CGPoint(
                x: canvas.midX - cardSize.width / 2,
                y: canvas.minY + readingLine
            )
            return Placement(
                plate: nil,
                card: CGRect(origin: clamp(origin, cardSize: cardSize, in: canvas), size: cardSize),
                connector: nil
            )
        }

        let inBand = target.height <= inBandTolerance
        let plateBottom = inBand
            ? canvas.minY + shelfHeight
            : target.maxY + plateInset
        let preferred = CGPoint(
            x: target.midX - cardSize.width / 2,
            y: plateBottom + connectorLength
        )
        let card = CGRect(origin: clamp(preferred, cardSize: cardSize, in: canvas), size: cardSize)
        let stemX = min(
            max(target.midX, card.minX + connectorCornerClearance),
            card.maxX - connectorCornerClearance
        )

        // The plate always reaches the stem, so the stem leaves the plate
        // and never the wash when the card is pinned to a margin.
        let plate: Plate
        if inBand {
            let minX = min(target.minX, stemX) - shelfInset
            let maxX = max(target.maxX, stemX) + shelfInset
            plate = Plate(
                rect: CGRect(x: minX, y: canvas.minY, width: maxX - minX, height: shelfHeight),
                cornerRadius: shelfCornerRadius
            )
        } else {
            let minX = min(target.minX - plateInset, stemX - shelfInset)
            let maxX = max(target.maxX + plateInset, stemX + shelfInset)
            plate = Plate(
                rect: CGRect(x: minX, y: canvas.minY, width: maxX - minX, height: plateBottom - canvas.minY),
                cornerRadius: plateCornerRadius
            )
        }

        let connector = Connector(
            start: CGPoint(x: stemX, y: plate.rect.maxY),
            end: CGPoint(x: stemX, y: card.minY)
        )
        return Placement(
            plate: plate,
            card: card,
            connector: card.minY > plate.rect.maxY ? connector : nil
        )
    }

    /// The pulse for a loop phase in 0...1: it travels the stem for the
    /// first `1 - dwell` of the period, fading in over the first tenth of
    /// the travel and out over the last tenth, then rests hidden. The
    /// progress is linear; `travelPoint` applies the easing.
    static func pulse(phase: Double, dwell: Double = Motion.guideTravelDwell) -> Pulse {
        let travel = max(0.01, 1 - dwell)
        let clamped = min(max(phase, 0), 1)
        guard clamped < travel else { return Pulse(progress: 1, opacity: 0) }
        let progress = clamped / travel
        let fade = 0.1
        let opacity: Double
        if progress < fade {
            opacity = progress / fade
        } else if progress > 1 - fade {
            opacity = (1 - progress) / fade
        } else {
            opacity = 1
        }
        return Pulse(progress: progress, opacity: min(max(opacity, 0), 1))
    }

    /// The pulse's position along the stem for a travel progress in 0...1:
    /// eased from the plate toward the card.
    static func travelPoint(on connector: Connector, phase: Double) -> CGPoint {
        let clamped = min(max(phase, 0), 1)
        let eased = clamped < 0.5
            ? 2 * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 2) / 2
        return CGPoint(
            x: connector.start.x + (connector.end.x - connector.start.x) * eased,
            y: connector.start.y + (connector.end.y - connector.start.y) * eased
        )
    }

    private static func clamp(_ origin: CGPoint, cardSize: CGSize, in canvas: CGRect) -> CGPoint {
        let minX = canvas.minX + edgeMargin
        let maxX = max(minX, canvas.maxX - edgeMargin - cardSize.width)
        let minY = canvas.minY + edgeMargin
        let maxY = max(minY, canvas.maxY - edgeMargin - cardSize.height)
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }
}
