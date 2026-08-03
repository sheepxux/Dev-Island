#!/usr/bin/env swift
// Render per-agent brand logos (SVG → template PNG) for the app bundle.
//
// Sources: scripts/assets/agent-logos/<source>.svg — vendored from
// @lobehub/icons-static-svg (monochrome variants, MIT-licensed package;
// the marks themselves belong to their respective owners and are used
// nominatively to identify each service).
//
// Output: IslandApp/Resources/AgentLogo-<source>.png (+ @2x)
//   - black shapes on transparent background, rendered from the 24×24
//     viewBox at 40/80 px
//   - consumed by IslandAppLib/Theme/AgentBrand.swift, which marks them
//     `isTemplate` so SwiftUI can tint per context (white on the dark
//     panel, label-color in Settings' adaptive background)
//
// Why PNG and not SVG-at-runtime: NSImage's CoreSVG decoding is private,
// version-dependent behavior; rasterizing once at dev time keeps runtime
// dumb and deterministic. Re-run after adding a new SVG:
//
//   swift scripts/make-agent-logos.swift

import AppKit

let root = URL(fileURLWithPath: #filePath)          // …/scripts/make-agent-logos.swift
    .deletingLastPathComponent()                    // …/scripts
    .deletingLastPathComponent()                    // repo root
let svgDir = root.appendingPathComponent("scripts/assets/agent-logos")
let outDir = root.appendingPathComponent("IslandApp/Resources")

/// Normalize a lobehub SVG so CoreSVG renders it correctly:
/// `1em` sizes → explicit 24, `currentColor` → opaque black (template ink).
func normalize(_ svg: String) -> String {
    svg.replacingOccurrences(of: "height=\"1em\"", with: "height=\"24\"")
       .replacingOccurrences(of: "width=\"1em\"", with: "width=\"24\"")
       .replacingOccurrences(of: "currentColor", with: "#000000")
}

func render(_ image: NSImage, px: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep alloc failed") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed")
    }
    try png.write(to: url)
}

let fm = FileManager.default
let svgs = try fm.contentsOfDirectory(at: svgDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !svgs.isEmpty else { fatalError("no SVGs in \(svgDir.path)") }

for svgURL in svgs {
    let source = svgURL.deletingPathExtension().lastPathComponent  // e.g. claude-code
    let svg = normalize(try String(contentsOf: svgURL, encoding: .utf8))
    guard let image = NSImage(data: Data(svg.utf8)) else {
        fatalError("CoreSVG could not decode \(svgURL.lastPathComponent)")
    }
    let base = outDir.appendingPathComponent("AgentLogo-\(source).png")
    let retina = outDir.appendingPathComponent("AgentLogo-\(source)@2x.png")
    try render(image, px: 40, to: base)
    try render(image, px: 80, to: retina)
    print("rendered AgentLogo-\(source).png (+@2x)")
}
