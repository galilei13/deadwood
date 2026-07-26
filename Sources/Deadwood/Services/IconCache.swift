import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Cache of real Finder icons keyed by file type, so table rows stay cheap.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for node: FileNode) -> NSImage {
        switch node.kind {
        case .directory:
            return cachedIcon(key: "\u{0}folder", type: .folder)
        case .package:
            // Packages vary a lot (apps have their own artwork) — resolve per URL,
            // but cache by extension so e.g. all .framework icons are shared.
            let ext = node.pathExtension.lowercased()
            if ext == "app" {
                return NSWorkspace.shared.icon(forFile: node.url.path)
            }
            let type = UTType(filenameExtension: ext) ?? .package
            return cachedIcon(key: "\u{0}pkg:\(ext)", type: type)
        case .file:
            let ext = node.pathExtension.lowercased()
            if ext.isEmpty {
                return cachedIcon(key: "\u{0}file", type: .data)
            }
            let type = UTType(filenameExtension: ext) ?? .data
            return cachedIcon(key: ext, type: type)
        }
    }

    private static func cachedIcon(key: String, type: UTType) -> NSImage {
        if let icon = cache[key] { return icon }
        let icon = NSWorkspace.shared.icon(for: type)
        cache[key] = icon
        return icon
    }
}
