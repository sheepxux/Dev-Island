import CoreGraphics

/// Pure placement for the full-screen Welcome tutorial: where the scrim opens
/// a spotlight around a real on-screen target, where the coaching card sits
/// under it, and the connector that ties the two together. Everything is in
/// the canvas's own top-left coordinate space and free of AppKit/SwiftUI so
/// the geometry stays regression-testable.
enum WelcomeTutorialLayout {
    /// Breathing room between a target and the spotlight edge.
    static let spotlightInset: CGFloat = 10
    static let spotlightCornerRadius: CGFloat = 18
    /// Vertical gap between the spotlight and the card, spanned by the
    /// connector.
    static let connectorLength: CGFloat = 28
    /// Minimum distance between the card and the canvas edges.
    static let edgeMargin: CGFloat = 24
    /// The connector may not touch the card's rounded corners.
    static let connectorCornerClearance: CGFloat = 32

    struct Connector: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    struct Placement: Equatable {
        var spotlight: CGRect?
        var card: CGRect
        var connector: Connector?
    }

    /// AppKit screen rects have a bottom-left origin; the canvas fills the
    /// screen and reads top-left.
    static func canvasRect(fromScreenRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func spotlight(around target: CGRect) -> CGRect {
        target.insetBy(dx: -spotlightInset, dy: -spotlightInset)
    }

    /// Places the card under `target`, centered on it and clamped inside the
    /// canvas; without a target the card is centered. A card that would run
    /// off the bottom is pinned to the bottom margin instead of overlapping
    /// the target.
    static func placement(target: CGRect?, cardSize: CGSize, canvas: CGRect) -> Placement {
        guard let target else {
            let origin = CGPoint(
                x: canvas.midX - cardSize.width / 2,
                y: canvas.midY - cardSize.height / 2
            )
            return Placement(
                spotlight: nil,
                card: CGRect(origin: clamp(origin, cardSize: cardSize, in: canvas), size: cardSize),
                connector: nil
            )
        }

        let spotlight = spotlight(around: target)
        let preferred = CGPoint(
            x: target.midX - cardSize.width / 2,
            y: spotlight.maxY + connectorLength
        )
        let card = CGRect(origin: clamp(preferred, cardSize: cardSize, in: canvas), size: cardSize)
        let connectorX = min(
            max(target.midX, card.minX + connectorCornerClearance),
            card.maxX - connectorCornerClearance
        )
        let connector = Connector(
            start: CGPoint(x: connectorX, y: spotlight.maxY),
            end: CGPoint(x: connectorX, y: card.minY)
        )
        return Placement(
            spotlight: spotlight,
            card: card,
            connector: card.minY > spotlight.maxY ? connector : nil
        )
    }

    /// Where the stage's one bloom sits: on the spotlight when the tour
    /// points at something, otherwise behind the card.
    static func bloomCenter(of placement: Placement) -> CGPoint {
        if let spotlight = placement.spotlight {
            return CGPoint(x: spotlight.midX, y: spotlight.midY)
        }
        return CGPoint(x: placement.card.midX, y: placement.card.midY)
    }

    /// Opacity of the breathing ring for a loop phase in 0...1: a full cosine
    /// breath from `restOpacity` up to 1 and back, continuous at the wrap.
    static let restOpacity: Double = 0.45

    static func breathOpacity(phase: Double) -> Double {
        let wave = 0.5 - 0.5 * cos(2 * .pi * phase)
        return restOpacity + (1 - restOpacity) * wave
    }

    /// The travelling point's position along the connector for a loop phase
    /// in 0...1: eased from the spotlight toward the card, then it starts
    /// over at the spotlight.
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
