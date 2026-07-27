#!/usr/bin/env swift
// Generates and validates static QR images from docs/support-config.js.
// Run from the repository root: swift scripts/make-wallet-qrs.swift

import AppKit
import CoreImage
import Foundation

private struct WalletQR {
    let address: String
    let relativePath: String
}

private let fileManager = FileManager.default
private let repositoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let docsURL = repositoryURL.appendingPathComponent("docs", isDirectory: true)
private let configURL = docsURL.appendingPathComponent("support-config.js")
private let config = try String(contentsOf: configURL, encoding: .utf8)
private let pattern = #"\baddress\s*:\s*"([^"]+)"\s*,\s*qr\s*:\s*"([^"]+)""#
private let regex = try NSRegularExpression(pattern: pattern)
private let range = NSRange(config.startIndex..<config.endIndex, in: config)

private let wallets: [WalletQR] = regex.matches(in: config, range: range).compactMap { match in
    guard
        let addressRange = Range(match.range(at: 1), in: config),
        let pathRange = Range(match.range(at: 2), in: config)
    else {
        return nil
    }
    return WalletQR(
        address: String(config[addressRange]),
        relativePath: String(config[pathRange])
    )
}

guard wallets.count == 4 else {
    fatalError("Expected four wallet address/QR pairs in \(configURL.path); found \(wallets.count)")
}

private func makeQRCode(message: String, outputURL: URL) throws {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
        fatalError("CIQRCodeGenerator is unavailable")
    }
    filter.setValue(Data(message.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")

    guard let outputImage = filter.outputImage else {
        fatalError("Could not create QR image")
    }

    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    guard let qrImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
        fatalError("Could not render QR image")
    }

    let side = 512
    let quietZone = 40
    let available = side - (quietZone * 2)
    let scale = max(1, available / qrImage.width)
    let renderedSide = qrImage.width * scale
    let origin = (side - renderedSide) / 2

    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        fatalError("Could not create QR bitmap context")
    }

    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.interpolationQuality = .none
    context.draw(
        qrImage,
        in: CGRect(x: origin, y: origin, width: renderedSide, height: renderedSide)
    )

    guard let image = context.makeImage() else {
        fatalError("Could not finalize QR bitmap")
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode QR PNG")
    }

    try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
}

private func decodeQRCode(at url: URL) -> String? {
    guard
        let image = CIImage(contentsOf: url),
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    else {
        return nil
    }
    return detector.features(in: image)
        .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        .first
}

for wallet in wallets {
    guard wallet.relativePath.hasPrefix("./qrcodes/") else {
        fatalError("QR output must stay inside docs/qrcodes: \(wallet.relativePath)")
    }

    let outputURL = docsURL.appendingPathComponent(String(wallet.relativePath.dropFirst(2)))
    try makeQRCode(message: wallet.address, outputURL: outputURL)

    guard decodeQRCode(at: outputURL) == wallet.address else {
        fatalError("QR validation failed for \(outputURL.lastPathComponent)")
    }
    print("Validated \(outputURL.path) → \(wallet.address)")
}
