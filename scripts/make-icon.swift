#!/usr/bin/env swift
// Generates Assets/AppIcon.icns from the project-owned source artwork.
// Run from the repo root:  swift scripts/make-icon.swift

import AppKit
import Foundation

let canvas: CGFloat = 1024

func drawIcon(source: NSImage) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    // Keep the supplied artwork intact inside a macOS-style app-icon plate.
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.white.setFill()
    platePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    platePath.setClip()
    source.draw(
        in: plate,
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.08).setStroke()
    platePath.lineWidth = 2
    platePath.stroke()

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
let sourceURL = repoRoot.appendingPathComponent("Assets/AppIconSource.jpeg")
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Deadwood.iconset")
let assetsURL = repoRoot.appendingPathComponent("Assets")
guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("Missing or unreadable source artwork: \(sourceURL.path)")
}
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

let icon = drawIcon(source: source)
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
