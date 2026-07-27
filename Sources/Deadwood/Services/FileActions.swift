import AppKit
import Foundation

enum FileActions {
    static let supportURL = URL(string: "https://galilei13.github.io/deadwood/")!

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func copyPaths(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func deletePermanently(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// System Settings → Privacy & Security → Full Disk Access.
    static func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openSupportPage() {
        open(supportURL)
    }
}
