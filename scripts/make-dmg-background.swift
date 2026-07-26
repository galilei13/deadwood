#!/usr/bin/env swift
// Draws the DMG window background (drag-to-Applications hint).
// Canvas: 1280x800 px = 640x400 pt @2x. Finder coordinates are top-left
// based; AppKit draws bottom-left, hence the flipped Y values below.
// Icons sit at Finder y≈185 → AppKit @2x y ≈ 800 - 370 = 430.
// Usage: swift scripts/make-dmg-background.swift <output.png>

import AppKit
import Foundation

let width: CGFloat = 1280
let height: CGFloat = 800

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// Light background — Finder always draws icon labels in black over custom
// background pictures, so the artwork must be light for them to read.
NSGradient(
    colors: [
        NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.89, green: 0.90, blue: 0.93, alpha: 1)
    ]
)?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

// Title — top center, well above the icon row.
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 50, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.13, green: 0.17, blue: 0.23, alpha: 1)
]
let title = "Deadwood" as NSString
let titleSize = title.size(withAttributes: titleAttributes)
title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: 690), withAttributes: titleAttributes)

// Subtitle — near the bottom, clear of the icons and their labels.
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 26, weight: .regular),
    .foregroundColor: NSColor(srgbRed: 0.13, green: 0.17, blue: 0.23, alpha: 0.55)
]
let subtitle = "Drag Deadwood into Applications to install" as NSString
let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
subtitle.draw(at: NSPoint(x: (width - subtitleSize.width) / 2, y: 110), withAttributes: subtitleAttributes)

// Arrow between the two icon slots, on the icon row's center line.
let arrowColor = NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 0.65)
let arrowY: CGFloat = 430
let arrowStart: CGFloat = 500
let arrowEnd: CGFloat = 760
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: arrowStart, y: arrowY))
arrow.line(to: NSPoint(x: arrowEnd, y: arrowY))
arrow.lineWidth = 12
arrow.lineCapStyle = .round
arrowColor.setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEnd - 38, y: arrowY + 30))
head.line(to: NSPoint(x: arrowEnd + 5, y: arrowY))
head.line(to: NSPoint(x: arrowEnd - 38, y: arrowY - 30))
head.lineWidth = 12
head.lineCapStyle = .round
head.lineJoinStyle = .round
arrowColor.setStroke()
head.stroke()

image.unlockFocus()

// Emit both scales; make-dmg.sh combines them into a HiDPI TIFF so Finder
// renders the background at 640x400 points on any display.
func writePNG(_ source: NSImage, pixelWidth: Int, pixelHeight: Int, to path: String) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let base = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dmg-background"
try writePNG(image, pixelWidth: 640, pixelHeight: 400, to: "\(base).png")
try writePNG(image, pixelWidth: 1280, pixelHeight: 800, to: "\(base)@2x.png")
print("Wrote \(base).png and \(base)@2x.png")
