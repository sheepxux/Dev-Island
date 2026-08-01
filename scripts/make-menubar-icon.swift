import AppKit

// Monochrome menu-bar adaptation of docs/media/logo.png:
// rounded-square frame + ">_" prompt glyph, black on transparent.
// Rendered at 18pt and 36pt (@2x). Geometry is defined in an 18-unit
// space and scaled, so both densities are pixel-identical in layout.

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

    // Frame: inset so the stroke stays inside 18×18; corner radius echoes
    // the logo's squircle.
    let frame = NSBezierPath(
        roundedRect: NSRect(x: 1.0, y: 1.0, width: 16.0, height: 16.0),
        xRadius: 4.2, yRadius: 4.2
    )
    frame.lineWidth = 1.6
    frame.stroke()

    // ">" chevron — left-of-center, like the logo.
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 4.9, y: 12.1))
    chevron.line(to: NSPoint(x: 8.4, y: 9.2))
    chevron.line(to: NSPoint(x: 4.9, y: 6.3))
    chevron.lineWidth = 1.8
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.stroke()

    // "_" underscore — baseline aligned with chevron's lower arm.
    let underscore = NSBezierPath()
    underscore.move(to: NSPoint(x: 9.9, y: 6.3))
    underscore.line(to: NSPoint(x: 13.4, y: 6.3))
    underscore.lineWidth = 1.8
    underscore.lineCapStyle = .round
    underscore.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = "/Users/xu/Desktop/DevLand/IslandApp/Resources"
for (scale, name) in [(CGFloat(1), "MenuBarIcon.png"), (CGFloat(2), "MenuBarIcon@2x.png")] {
    let rep = draw(scale: scale)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    print("wrote \(name) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}
