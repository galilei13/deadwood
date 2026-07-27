import AppKit
import Foundation
import Observation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case tree
    case treemap
    case largest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tree: return "Tree"
        case .treemap: return "Treemap"
        case .largest: return "Largest Files"
        }
    }

    var systemImage: String {
        switch self {
        case .tree: return "list.bullet.indent"
        case .treemap: return "square.grid.3x3.topleft.filled"
        case .largest: return "arrow.down.right.circle"
        }
    }
}

/// A delete request with its URLs captured at request time — node URLs are
/// derived from the parent chain and become meaningless once a node is
/// detached (e.g. after a rescan), so they must never be resolved later.
struct PendingDeletion {
    let items: [(node: FileNode, url: URL)]

    init(nodes: [FileNode] = []) {
        items = nodes.map { ($0, $0.url) }
    }

    var isEmpty: Bool { items.isEmpty }
    var nodes: [FileNode] { items.map(\.node) }
}

/// Single source of truth for the whole app.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case idle
        case scanning
        case complete
    }

    // MARK: Sidebar

    private(set) var drives: [DriveInfo] = []
    let quickLocations = QuickLocation.standardLocations()
    private(set) var recentFolders: [URL] = []
    var selectedTarget: ScanTarget?

    // MARK: Scan lifecycle

    private(set) var phase: Phase = .idle
    private(set) var progress = ScanProgress()
    private(set) var scanStart: Date?
    private(set) var result: ScanResult?
    private(set) var largestFiles: [FileNode] = []
    var errorMessage: String?

    // MARK: Detail state

    var viewMode: ViewMode = .tree
    var selection: Set<FileNode.ID> = [] {
        didSet { resolveSelection() }
    }
    private(set) var selectedNodes: [FileNode] = []
    private(set) var topLevelSelection: [FileNode] = []
    private(set) var selectedTotalSize: Int64 = 0
    var sortOrder: [KeyPathComparator<FileNode>] = AppModel.defaultSortOrder
    var treemapRoot: FileNode?
    var pendingPermanentDelete = PendingDeletion()
    var isFolderPickerPresented = false
    /// Quick Look (space bar) state — non-nil URL presents the preview panel.
    /// Arrow keys in the panel navigate `quickLookItems`; the binding write
    /// that navigation performs is mirrored back into the table selection.
    var quickLookURL: URL? {
        didSet { syncSelectionFromQuickLook(oldValue) }
    }
    private(set) var quickLookItems: [URL] = []
    /// Nodes behind `quickLookItems`, in the same order.
    @ObservationIgnored private var quickLookContext: [FileNode] = []
    /// True when panel navigation should move the table selection
    /// (single-item anchor). Multi-selections preview within themselves.
    @ObservationIgnored private var quickLookFollowsSelection = false
    @ObservationIgnored private var isSyncingQuickLook = false
    private(set) var isDeleting = false
    private(set) var isSorting = false
    /// Bumped whenever the tree's structure changes (scan, sort, deletion) so
    /// layout caches (treemap) know to recompute.
    private(set) var treeVersion = 0

    private static let defaultSortOrder: [KeyPathComparator<FileNode>] = [
        KeyPathComparator(\FileNode.size, order: .reverse),
        KeyPathComparator(\FileNode.name)
    ]

    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var sortGeneration = 0
    @ObservationIgnored private var sortTask: Task<Void, Never>?
    @ObservationIgnored private var volumeObservers: [NSObjectProtocol] = []

    private static let recentFoldersKey = "sidebar.recentFolders"
    private static let maxRecentFolders = 6

    var scannedRoot: FileNode? { result?.root }

    var isScanning: Bool { phase == .scanning }

    init() {
        refreshDrives()
        loadRecentFolders()
        observeVolumeChanges()
    }

    deinit {
        for observer in volumeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Drives & locations

    func refreshDrives() {
        // Volume enumeration stats every mount — including network mounts —
        // so it must stay off the main thread.
        Task.detached(priority: .utility) { [weak self] in
            let drives = DriveInfo.loadAll()
            let model = self
            await MainActor.run { model?.drives = drives }
        }
    }

    private func observeVolumeChanges() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshDrives()
                }
            }
            volumeObservers.append(observer)
        }
    }

    private func loadRecentFolders() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentFoldersKey) ?? []
        recentFolders = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecentFolder(_ url: URL) {
        // Drives and standard sidebar locations already have their own rows.
        guard !drives.contains(where: { $0.url.path == url.path }),
              !quickLocations.contains(where: { $0.url.path == url.path }) else { return }
        recentFolders.removeAll { $0.path == url.path }
        recentFolders.insert(url, at: 0)
        if recentFolders.count > Self.maxRecentFolders {
            recentFolders.removeLast(recentFolders.count - Self.maxRecentFolders)
        }
        UserDefaults.standard.set(recentFolders.map(\.path), forKey: Self.recentFoldersKey)
    }

    // MARK: - Scanning

    func scanSelectedTarget() {
        guard let target = selectedTarget else { return }
        startScan(at: target.url)
    }

    func rescan() {
        guard let root = result?.root else {
            scanSelectedTarget()
            return
        }
        startScan(at: root.url)
    }

    func startScan(at url: URL) {
        // Validate before touching the in-flight scan — a bad path must not
        // kill the current scan or leave phase stuck at .scanning.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            errorMessage = "\(url.path) is not a folder that can be scanned."
            return
        }

        scanTask?.cancel()
        cancelSort()
        clearQuickLook()
        addRecentFolder(url)
        phase = .scanning
        progress = ScanProgress()
        scanStart = Date()
        scanGeneration += 1
        let generation = scanGeneration

        let scanner = DiskScanner(options: ScanOptions.fromDefaults())
        scanTask = Task { [weak self] in
            do {
                let result = try await scanner.scan(url: url) { [weak self] snapshot in
                    let model = self
                    Task { @MainActor in
                        guard let model, model.scanGeneration == generation, model.isScanning else { return }
                        model.progress = snapshot
                    }
                }
                guard !Task.isCancelled else { return }
                self?.finishScan(with: result)
            } catch is CancellationError {
                // cancelScan() already restored the UI state.
            } catch {
                guard !Task.isCancelled else { return }
                self?.failScan(with: error)
            }
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        phase = result != nil ? .complete : .idle
    }

    private func finishScan(with result: ScanResult) {
        clearQuickLook()
        self.result = result
        largestFiles = result.largestFiles
        treemapRoot = result.root
        selection = []
        // A pending delete confirmation from the previous tree must not
        // survive into this one — its nodes are now detached.
        pendingPermanentDelete = PendingDeletion()
        phase = .complete
        treeVersion += 1
        // The scanner already delivers every level sorted by size descending.
        if sortOrder != Self.defaultSortOrder {
            applySort()
        }
    }

    private func failScan(with error: Error) {
        errorMessage = error.localizedDescription
        phase = result != nil ? .complete : .idle
    }

    // MARK: - Selection & sorting

    private func resolveSelection() {
        selectedNodes = nodes(for: selection)
        // Cache the derived views of the selection — topLevel(of:) is
        // quadratic and the status bar reads these on every render.
        topLevelSelection = Self.topLevel(of: selectedNodes)
        selectedTotalSize = topLevelSelection.reduce(0) { $0 + $1.size }
        // Clicking a different row while the panel is open re-anchors the
        // preview, exactly like Finder.
        if quickLookURL != nil, !isSyncingQuickLook, !selectedNodes.isEmpty {
            quickLook(selectedNodes)
        }
    }

    /// Resolves row IDs to live nodes with a single tree traversal.
    func nodes(for ids: Set<FileNode.ID>) -> [FileNode] {
        guard !ids.isEmpty, let root = result?.root else { return [] }
        var remaining = ids
        var found: [FileNode] = []
        var stack: [FileNode] = [root]
        while let node = stack.popLast(), !remaining.isEmpty {
            if remaining.remove(node.id) != nil {
                found.append(node)
            }
            if let children = node.children {
                stack.append(contentsOf: children)
            }
        }
        return found
    }

    /// Filters out nodes contained inside other nodes of the same set.
    static func topLevel(of nodes: [FileNode]) -> [FileNode] {
        nodes.filter { node in
            !nodes.contains { other in other !== node && node.isDescendant(of: other) }
        }
    }

    func applySort() {
        sortTask?.cancel()
        sortGeneration += 1
        let generation = sortGeneration

        guard let root = result?.root else {
            isSorting = false
            return
        }

        let comparators = sortOrder
        isSorting = true
        sortTask = Task { [weak self] in
            await root.sortSubtreeIncrementally(by: comparators)
            guard let self,
                  !Task.isCancelled,
                  self.sortGeneration == generation,
                  self.result?.root === root else { return }
            self.treeVersion += 1
            self.isSorting = false
            self.sortTask = nil
        }
    }

    private func cancelSort() {
        sortTask?.cancel()
        sortTask = nil
        sortGeneration += 1
        isSorting = false
    }

    // MARK: - File actions

    func reveal(_ nodes: [FileNode]) {
        let urls = Self.topLevel(of: nodes).map(\.url)
        guard !urls.isEmpty else { return }
        FileActions.revealInFinder(urls)
    }

    func copyPaths(_ nodes: [FileNode]) {
        let urls = Self.topLevel(of: nodes).map(\.url)
        guard !urls.isEmpty else { return }
        FileActions.copyPaths(urls)
    }

    func trash(_ nodes: [FileNode]) {
        removeItems(PendingDeletion(nodes: Self.topLevel(of: nodes)).items, permanently: false)
    }

    func requestPermanentDelete(_ nodes: [FileNode]) {
        let pending = PendingDeletion(nodes: Self.topLevel(of: nodes))
        guard !pending.isEmpty else { return }
        pendingPermanentDelete = pending
    }

    /// Opens (or re-anchors) the Quick Look panel on the given nodes.
    ///
    /// Finder semantics: a single anchor previews among its visible
    /// neighbours (siblings in the tree, the whole list in Largest Files)
    /// and arrow keys move the real selection along; a multi-selection
    /// previews just within itself and leaves the selection untouched.
    func quickLook(_ nodes: [FileNode]) {
        let top = Self.topLevel(of: nodes)
        guard let anchor = top.first else { return }

        isSyncingQuickLook = true
        defer { isSyncingQuickLook = false }

        if top.count > 1 {
            quickLookContext = top
            quickLookFollowsSelection = false
        } else if viewMode == .largest, largestFiles.contains(where: { $0 === anchor }) {
            quickLookContext = largestFiles
            quickLookFollowsSelection = true
        } else if let siblings = anchor.parent?.children, siblings.count > 1 {
            quickLookContext = siblings
            quickLookFollowsSelection = true
        } else {
            quickLookContext = [anchor]
            quickLookFollowsSelection = false
        }
        quickLookItems = quickLookContext.map(\.url)
        quickLookURL = anchor.url
    }

    /// Panel arrow navigation wrote a new URL — move the selection with it.
    private func syncSelectionFromQuickLook(_ oldValue: URL?) {
        guard quickLookURL != oldValue,
              !isSyncingQuickLook,
              quickLookFollowsSelection,
              let url = quickLookURL,
              let node = quickLookContext.first(where: { $0.url.path == url.path }),
              selection != [node.id] else { return }
        isSyncingQuickLook = true
        selection = [node.id]
        isSyncingQuickLook = false
    }

    /// Clears every piece of Quick Look state together so URLs and retained
    /// nodes from an old tree cannot survive a rescan or deletion.
    private func clearQuickLook() {
        isSyncingQuickLook = true
        quickLookURL = nil
        quickLookItems = []
        quickLookContext = []
        quickLookFollowsSelection = false
        isSyncingQuickLook = false
    }

    func revealSelectionInFinder() { reveal(selectedNodes) }
    func copySelectionPaths() { copyPaths(selectedNodes) }
    func trashSelection() { trash(selectedNodes) }
    func requestPermanentDeleteOfSelection() { requestPermanentDelete(selectedNodes) }
    func quickLookSelection() { quickLook(selectedNodes) }

    func confirmPermanentDelete() {
        let pending = pendingPermanentDelete
        pendingPermanentDelete = PendingDeletion()
        removeItems(pending.items, permanently: true)
    }

    /// Deletes off the main actor so a 100k-file folder doesn't beachball the
    /// app. URLs were captured while the nodes were attached — never derived
    /// at delete time — and detached (stale) nodes are skipped outright.
    private func removeItems(_ items: [(node: FileNode, url: URL)], permanently: Bool) {
        guard !items.isEmpty, !isDeleting else { return }
        isDeleting = true

        Task {
            var failures: [String] = []
            for (node, url) in items {
                let isAttached = node.parent != nil || node === result?.root
                guard isAttached else { continue }
                do {
                    try await Self.removeFromDisk(url: url, permanently: permanently)
                    pruneRemovedNode(node)
                    if let previewed = quickLookURL,
                       previewed.path == url.path || previewed.path.hasPrefix(url.path + "/") {
                        quickLookURL = nil
                    }
                } catch {
                    failures.append("\(node.name): \(error.localizedDescription)")
                }
            }
            selection = []
            isDeleting = false
            if !failures.isEmpty {
                let verb = permanently ? "delete" : "move to Trash"
                errorMessage = "Could not \(verb):\n" + failures.joined(separator: "\n")
            }
        }
    }

    private nonisolated static func removeFromDisk(url: URL, permanently: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            if permanently {
                try FileActions.deletePermanently(url)
            } else {
                try FileActions.moveToTrash(url)
            }
        }.value
    }

    /// Removes a successfully-deleted node from every piece of app state.
    /// Must run before `removeFromParent()` breaks the ancestor chain.
    private func pruneRemovedNode(_ node: FileNode) {
        clearQuickLook()
        if let current = treemapRoot, current === node || current.isDescendant(of: node) {
            treemapRoot = node.parent ?? result?.root
        }
        if let root = result?.root, node === root {
            result = nil
            largestFiles = []
            treemapRoot = nil
            phase = .idle
        } else {
            node.removeFromParent()
            if let root = result?.root {
                // Backfill the ranking after a deletion instead of merely
                // shrinking what used to be the top 100.
                largestFiles = DiskScanner.collectLargestLeaves(root: root, count: 100)
            }
        }
        treeVersion += 1
    }
}
