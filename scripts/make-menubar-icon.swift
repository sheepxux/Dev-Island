import AppKit

// Monochrome menu-bar adaptation of docs/media/logo.png. The full artwork is
// deliberately not downsampled into an 18-point slot: its cream material and
// pixel lettering would turn muddy at that size. Instead this keeps the new
// logo's two defining silhouettes — the soft square body and the elevated
// terminal island — as a macOS template image that stays crisp in light and
// dark menu bars.

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let size = Int(18 * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    NSColor.black.setStroke()

    // Outer app body.
    let frame = NSBezierPath(
        roundedRect: NSRect(x: 1.0, y: 1.0, width: 16.0, height: 16.0),
        xRadius: 4.8, yRadius: 4.8
    )
    frame.lineWidth = 1.35
    frame.stroke()

    // Elevated terminal island from the upper half of the final logo.
    let island = NSBezierPath(
        roundedRect: NSRect(x: 2.7, y: 7.8, width: 12.6, height: 7.5),
        xRadius: 3.2, yRadius: 3.2
    )
    island.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let scriptURL = URL(fileURLWithPath: #filePath)
let out = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("IslandApp/Resources")
    .path
for (scale, name) in [(CGFloat(1), "MenuBarIcon.png"), (CGFloat(2), "MenuBarIcon@2x.png")] {
    let rep = draw(scale: scale)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    print("wrote \(name) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}
