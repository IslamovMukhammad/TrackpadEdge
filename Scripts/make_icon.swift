#!/usr/bin/env swift
// Draws the TrackpadEdge app icon in code and writes Resources/AppIcon.iconset.
// Usage: swift Scripts/make_icon.swift   (from the package folder)
//
// The design: a deep blue tile holding a trackpad. A glass column glows on its right edge
// (volume) and a warm one on its left edge (brightness); two fingertips sit at the right edge
// with a small arrow pointing inward: the slide-in that starts control.

import AppKit

func drawIcon(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = px / 1024   // design in 1024 units

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        // y is measured from the top in the design
        NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)
    }
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: (1024 - y) * s) }
    func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius * s, yRadius: radius * s)
    }
    func shadowed(_ color: NSColor, blur: CGFloat, y: CGFloat, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur * s
        shadow.shadowOffset = NSSize(width: 0, height: -y * s)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Tile (macOS icon grid: 824 pt body centred in 1024, radius ~185)
    let tile = rounded(r(100, 100, 824, 824), 185)
    shadowed(NSColor.black.withAlphaComponent(0.35), blur: 24, y: 10) { NSColor.black.setFill(); tile.fill() }
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [NSColor(red: 0.17, green: 0.30, blue: 0.95, alpha: 1),
                        NSColor(red: 0.06, green: 0.09, blue: 0.30, alpha: 1)])!
        .draw(in: tile.bounds, angle: -70)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: rounded(r(40, 40, 620, 620), 310), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    // The trackpad
    let pad = r(196, 270, 632, 484)
    shadowed(NSColor.black.withAlphaComponent(0.45), blur: 40, y: 18) {
        NSColor(white: 0.93, alpha: 1).setFill()
        rounded(pad, 64).fill()
    }
    NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(white: 0.84, alpha: 1)])!
        .draw(in: rounded(pad, 64), angle: -90)

    // Edge columns: brightness (left, warm) and volume (right, blue-white)
    func column(x: CGFloat, fill: CGFloat, color: NSColor) {
        let track = r(x, 330, 64, 364)
        NSColor(white: 0, alpha: 0.10).setFill()
        rounded(track, 32).fill()
        NSGraphicsContext.saveGraphicsState()
        rounded(track, 32).addClip()
        color.setFill()
        let h = 364 * fill
        NSBezierPath(rect: r(x, 330 + 364 - h, 64, h)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    column(x: 232, fill: 0.48, color: NSColor(red: 1.0, green: 0.78, blue: 0.20, alpha: 1))
    column(x: 728, fill: 0.66, color: NSColor(red: 0.17, green: 0.30, blue: 0.95, alpha: 1))

    // Two fingertips at the right edge
    for y: CGFloat in [400, 520] {
        let tip = NSBezierPath(ovalIn: r(612, y, 92, 92))
        shadowed(NSColor.black.withAlphaComponent(0.25), blur: 14, y: 6) {
            NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.88).setFill()
            tip.fill()
        }
    }
    // The inward arrow
    let arrow = NSBezierPath()
    arrow.lineWidth = 26 * s
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: p(560, 512))
    arrow.line(to: p(420, 512))
    arrow.move(to: p(470, 462))
    arrow.line(to: p(420, 512))
    arrow.line(to: p(470, 562))
    NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.88).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: out.appendingPathComponent(name))
    }
}
print("Wrote \(out.path)")
