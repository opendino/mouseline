#!/usr/bin/env swift
// Draws the mgestures app icon and writes it as an .icns file.
//
//   swift scripts/make-icon.swift Support/AppIcon.icns
//
// The icon is drawn in code (rather than checked in as a design file) so it can be
// regenerated with nothing but the Command Line Tools, and so every size is rendered
// natively at its own pixel resolution instead of being downscaled from 1024 px —
// small sizes stay crisp that way.
//
// Design: a macOS-style rounded square ("squircle") on the standard icon grid, filled with
// a warm orange-to-red gradient that matches the gesture trail color (RGB 1.0 / 0.55 / 0.1),
// with a white "hand.draw" SF Symbol on top. If the symbol cannot be loaded (older system,
// unusual environment), a white hand-drawn stroke with an arrow head is drawn instead.

import AppKit
import Foundation

// MARK: - Geometry

/// Apple's macOS icon grid: on a 1024 canvas the shape is 824 x 824, centered,
/// leaving a 100 pt margin for the drop shadow. Expressed as fractions of the canvas.
let shapeInset: CGFloat = 100.0 / 1024.0
/// Corner radius as a fraction of the shape size (~22%, Apple uses ~185/824).
let cornerFraction: CGFloat = 0.225

/// A rounded rectangle with *continuous* corners: each corner is a superellipse
/// quadrant that starts further along the edge than a circular arc would, so the
/// curvature ramps up smoothly instead of jumping at the tangent point. This is what
/// gives macOS / iOS icons their "squircle" look; NSBezierPath(roundedRect:) would
/// produce visibly sharper, circular corners.
func continuousRoundedRect(_ rect: CGRect, radius r: CGFloat) -> NSBezierPath {
    // A continuous corner reaches ~1.5x further along each edge than a circular one.
    let extent = min(r * 1.52, min(rect.width, rect.height) / 2)
    let exponent: CGFloat = 4.0      // 2 = circle, higher = squarer; ~4 matches Apple's corners
    let steps = 24

    let path = NSBezierPath()
    // Corner centers (where the superellipse quadrant is anchored) and the quadrant
    // each one covers, walking counter-clockwise starting at the bottom-right corner.
    let corners: [(cx: CGFloat, cy: CGFloat, startAngle: CGFloat)] = [
        (rect.maxX - extent, rect.minY + extent, -.pi / 2),  // bottom-right
        (rect.maxX - extent, rect.maxY - extent, 0),         // top-right
        (rect.minX + extent, rect.maxY - extent, .pi / 2),   // top-left
        (rect.minX + extent, rect.minY + extent, .pi),       // bottom-left
    ]
    var first = true
    for corner in corners {
        for i in 0...steps {
            let t = corner.startAngle + (CGFloat(i) / CGFloat(steps)) * (.pi / 2)
            let c = cos(t), s = sin(t)
            // Superellipse: x = a * sgn(cos) * |cos|^(2/n)
            let x = corner.cx + extent * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
            let y = corner.cy + extent * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
            let p = CGPoint(x: x, y: y)
            if first { path.move(to: p); first = false } else { path.line(to: p) }
        }
    }
    path.close()
    return path
}

// MARK: - Colors

let trailOrange = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.1, alpha: 1)
let warmRed = NSColor(srgbRed: 0.92, green: 0.22, blue: 0.16, alpha: 1)
let highlightOrange = NSColor(srgbRed: 1.0, green: 0.66, blue: 0.22, alpha: 1)

// MARK: - Drawing

/// Draws the white glyph into `rect`. Returns false if the SF Symbol is unavailable,
/// so the caller can fall back to the drawn stroke.
func drawSymbol(in rect: CGRect) -> Bool {
    guard let base = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil) else {
        return false
    }
    // A large point size keeps the vector outline exact; the image is then fitted
    // into `rect` preserving its aspect ratio.
    let config = NSImage.SymbolConfiguration(pointSize: 512, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = base.withSymbolConfiguration(config) else { return false }

    let size = symbol.size
    guard size.width > 0, size.height > 0 else { return false }
    let scale = min(rect.width / size.width, rect.height / size.height)
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    let target = CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                        width: drawn.width, height: drawn.height)
    symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    return true
}

/// Fallback glyph: a loose gesture stroke ending in an arrow head, in white.
func drawStrokeGlyph(in rect: CGRect) {
    let w = rect.width, h = rect.height
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }

    let stroke = NSBezierPath()
    stroke.move(to: p(0.10, 0.30))
    stroke.curve(to: p(0.45, 0.75), controlPoint1: p(0.15, 0.80), controlPoint2: p(0.35, 0.85))
    stroke.curve(to: p(0.85, 0.25), controlPoint1: p(0.55, 0.60), controlPoint2: p(0.65, 0.20))
    stroke.lineWidth = w * 0.09
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round
    NSColor.white.setStroke()
    stroke.stroke()

    let head = NSBezierPath()
    head.move(to: p(0.66, 0.22))
    head.line(to: p(0.88, 0.22))
    head.line(to: p(0.88, 0.44))
    head.lineWidth = w * 0.09
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
}

/// Renders the icon at exactly `pixels` x `pixels` and returns PNG data.
func renderIcon(pixels: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("Could not allocate a \(pixels) px bitmap") }
    // 1 point = 1 pixel, so all geometry below is in pixels.
    rep.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create a graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true

    let canvas = CGFloat(pixels)
    let inset = canvas * shapeInset
    let shapeRect = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let shape = continuousRoundedRect(shapeRect, radius: shapeRect.width * cornerFraction)

    // 1. Drop shadow of the whole tile, inside the standard margin.
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    tileShadow.shadowBlurRadius = canvas * 0.025
    tileShadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.010)
    tileShadow.set()
    warmRed.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 2. Gradient fill: lighter orange at the top, the trail orange in the middle,
    //    warm red at the bottom — like light falling on the tile from above.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let gradient = NSGradient(colorsAndLocations:
        (highlightOrange, 0.0), (trailOrange, 0.40), (warmRed, 1.0))!
    gradient.draw(in: shapeRect, angle: -90)   // -90: from top to bottom
    // Faint top sheen so the tile does not look flat at large sizes.
    let sheen = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.18), 0.0), (NSColor.white.withAlphaComponent(0.0), 0.5))!
    sheen.draw(in: shapeRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 3. The white glyph with a soft shadow, so it lifts off the gradient.
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(srgbRed: 0.45, green: 0.08, blue: 0.0, alpha: 0.35)
    glyphShadow.shadowBlurRadius = canvas * 0.02
    glyphShadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.008)
    glyphShadow.set()
    let glyphRect = shapeRect.insetBy(dx: shapeRect.width * 0.17, dy: shapeRect.height * 0.17)
    if !drawSymbol(in: glyphRect) {
        drawStrokeGlyph(in: glyphRect)
    }
    NSGraphicsContext.restoreGraphicsState()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return png
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift scripts/make-icon.swift <out.icns>\n".data(using: .utf8)!)
    exit(64)
}
let outputURL = URL(fileURLWithPath: arguments[1])
let fileManager = FileManager.default

let workDir = fileManager.temporaryDirectory
    .appendingPathComponent("mgestures-icon-\(ProcessInfo.processInfo.processIdentifier)")
let iconset = workDir.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: workDir)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: workDir) }

// The file names iconutil expects: icon_<pt>x<pt>[@2x].png.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try renderIcon(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed (\(iconutil.terminationStatus))\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(outputURL.path)")
