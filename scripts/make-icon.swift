#!/usr/bin/env swift
// Generates Assets/AppIcon.icns — a treemap motif on a macOS-style rounded square.
// Run from the repo root:  swift scripts/make-icon.swift

import AppKit
import Foundation

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    // Big Sur-style rounded square with standard margins.
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x1D4ED8).setFill()
    platePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [color(0x3B82F6), color(0x0E7490)])?
        .draw(in: platePath, angle: -70)

    // Treemap blocks (white, varying opacity) inside the plate.
    platePath.setClip()
    let inset = plate.insetBy(dx: 108, dy: 108)
    let gap: CGFloat = 22
    let radius: CGFloat = 26

    func block(_ rect: NSRect, _ alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
    }

    // Left column: one dominant block (the "big folder").
    let leftWidth = inset.width * 0.56
    block(NSRect(x: inset.minX, y: inset.minY, width: leftWidth, height: inset.height), 0.94)

    // Right column: three stacked blocks of decreasing size.
    let rightX = inset.minX + leftWidth + gap
    let rightWidth = inset.maxX - rightX
    let topHeight = inset.height * 0.52
    block(NSRect(x: rightX, y: inset.maxY - topHeight, width: rightWidth, height: topHeight), 0.78)

    let middleHeight = inset.height * 0.30
    let middleY = inset.maxY - topHeight - gap - middleHeight
    let middleSplit = rightWidth * 0.55
    block(NSRect(x: rightX, y: middleY, width: middleSplit, height: middleHeight), 0.62)
    block(NSRect(x: rightX + middleSplit + gap, y: middleY, width: rightWidth - middleSplit - gap, height: middleHeight), 0.5)

    let bottomHeight = middleY - gap - inset.minY
    let bottomSplit = rightWidth * 0.38
    block(NSRect(x: rightX, y: inset.minY, width: bottomSplit, height: bottomHeight), 0.44)
    block(NSRect(x: rightX + bottomSplit + gap, y: inset.minY, width: rightWidth - bottomSplit - gap, height: bottomHeight), 0.34)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, size: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed for \(size)")
    }
    try data.write(to: url)
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Deadwood.iconset")
let assetsURL = repoRoot.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

let icon = drawIcon()
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in sizes {
    try writePNG(icon, size: size, to: iconsetURL.appendingPathComponent("\(name).png"))
}

let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("Wrote \(icnsURL.path)")
