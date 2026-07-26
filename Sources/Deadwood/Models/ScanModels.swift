import Foundation

struct ScanOptions: Sendable {
    /// Include hidden files/folders so reported sizes match real disk usage.
    var includeHiddenFiles = true
    /// Descend into packages (.app bundles etc.) and show their contents.
    /// Package sizes are always counted either way.
    var showPackageContents = false

    static let defaultsIncludeHiddenKey = "scan.includeHiddenFiles"
    static let defaultsShowPackagesKey = "scan.showPackageContents"

    static func fromDefaults() -> ScanOptions {
        let defaults = UserDefaults.standard
        var options = ScanOptions()
        if defaults.object(forKey: defaultsIncludeHiddenKey) != nil {
            options.includeHiddenFiles = defaults.bool(forKey: defaultsIncludeHiddenKey)
        }
        if defaults.object(forKey: defaultsShowPackagesKey) != nil {
            options.showPackageContents = defaults.bool(forKey: defaultsShowPackagesKey)
        }
        return options
    }
}

/// Throttled snapshot of a running scan, delivered to the UI.
struct ScanProgress: Sendable {
    var itemCount: Int = 0
    var byteCount: Int64 = 0
    var currentPath: String = ""
    var errorCount: Int = 0
}

/// Everything a finished scan produced.
struct ScanResult: @unchecked Sendable {
    let root: FileNode
    let largestFiles: [FileNode]
    let itemCount: Int
    let errorCount: Int
    /// Sample of paths that could not be read (permission errors etc.).
    let skippedPaths: [String]
    let duration: TimeInterval
    let options: ScanOptions
}

/// What the sidebar can point the scanner at.
///
/// Identity (equality/hash) is the path + kind only — capacity values change
/// on every drive refresh and must not break the sidebar's selection.
struct ScanTarget: Hashable, Identifiable {
    enum Kind: String {
        case drive
        case folder
    }

    let url: URL
    let kind: Kind
    let displayName: String

    var id: String { "\(kind.rawValue):\(url.path)" }

    static func == (lhs: ScanTarget, rhs: ScanTarget) -> Bool {
        lhs.kind == rhs.kind && lhs.url.path == rhs.url.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(url.path)
    }

    static func drive(_ drive: DriveInfo) -> ScanTarget {
        ScanTarget(url: drive.url, kind: .drive, displayName: drive.name)
    }

    static func folder(_ url: URL) -> ScanTarget {
        ScanTarget(
            url: url,
            kind: .folder,
            displayName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        )
    }
}

/// Well-known user folders offered in the sidebar.
struct QuickLocation: Identifiable, Hashable {
    let url: URL
    let name: String
    let systemImage: String

    var id: String { url.path }

    static func standardLocations() -> [QuickLocation] {
        let fm = FileManager.default
        var locations: [QuickLocation] = [
            QuickLocation(url: fm.homeDirectoryForCurrentUser, name: "Home", systemImage: "house")
        ]
        let wellKnown: [(FileManager.SearchPathDirectory, String, String)] = [
            (.desktopDirectory, "Desktop", "menubar.dock.rectangle"),
            (.documentDirectory, "Documents", "doc"),
            (.downloadsDirectory, "Downloads", "arrow.down.circle"),
            (.moviesDirectory, "Movies", "film"),
            (.musicDirectory, "Music", "music.note"),
            (.picturesDirectory, "Pictures", "photo"),
            (.applicationDirectory, "Applications", "app.badge")
        ]
        for (directory, name, icon) in wellKnown {
            if let url = fm.urls(for: directory, in: directory == .applicationDirectory ? .localDomainMask : .userDomainMask).first,
               fm.fileExists(atPath: url.path) {
                locations.append(QuickLocation(url: url, name: name, systemImage: icon))
            }
        }
        return locations
    }
}
