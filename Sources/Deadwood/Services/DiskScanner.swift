import Foundation

/// Recursive, parallel disk scanner.
///
/// Directory reads are blocking syscalls, so they run on a bounded
/// `OperationQueue` instead of the Swift cooperative pool. The tree fan-out
/// uses a bounded task group at the top levels; cancellation uses structured
/// task cancellation plus a flag the IO blocks check before touching the disk
/// and periodically while processing large directory listings.
struct DiskScanner: Sendable {
    let options: ScanOptions

    /// Levels of the tree that fan out into parallel child tasks.
    private static let parallelDepthLimit = 3

    /// Keep both suspended Swift tasks and blocking filesystem calls bounded.
    private static let maxConcurrentChildTasks = min(
        max(ProcessInfo.processInfo.activeProcessorCount, 2),
        8
    )

    /// Blocking filesystem work happens here, not on the cooperative pool.
    private static let ioQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.deadwood.scan-io"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = maxConcurrentChildTasks
        return queue
    }()

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .isVolumeKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey
    ]
    private static let resourceKeySet = Set(resourceKeys)

    func scan(
        url: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let flag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await performScan(url: url, flag: flag, onProgress: onProgress)
        } onCancel: {
            flag.set()
        }
    }

    private func performScan(
        url: URL,
        flag: CancelFlag,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let start = Date()
        let tracker = ProgressTracker(onUpdate: onProgress)
        let visited = VisitedDirectories()

        let values = try? url.resourceValues(forKeys: Self.resourceKeySet)
        // Claim the root's identity up front so a mirror of the root deeper
        // in the tree can never re-introduce it.
        _ = visited.firstVisit(values?.fileResourceIdentifier as? NSObject)

        let root = FileNode(
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            kind: .directory,
            modified: values?.contentModificationDate,
            rootURL: url
        )
        let children = try await scanChildren(of: url, depth: 0, tracker: tracker, flag: flag, visited: visited)
        root.finalize(children: children.sorted(by: Self.largerFirst))

        let (progress, skipped) = tracker.finalSnapshot()
        return ScanResult(
            root: root,
            largestFiles: Self.collectLargestLeaves(root: root, count: 100),
            itemCount: progress.itemCount,
            errorCount: progress.errorCount,
            skippedPaths: skipped,
            duration: Date().timeIntervalSince(start),
            options: options
        )
    }

    // MARK: - Blocking IO bridge

    /// What one blocking directory read produces.
    private struct DirectoryListing: Sendable {
        var files: [FileNode] = []
        var subdirectories: [SubdirectoryEntry] = []
        var fileBytes: Int64 = 0
        var itemCount: Int = 0
    }

    private struct SubdirectoryEntry: Sendable {
        let url: URL
        let isPackage: Bool
        let modified: Date?
    }

    /// Runs one full directory read (list + per-item attributes) on the IO
    /// queue. The cooperative-pool task merely suspends on the continuation.
    private func readDirectory(
        at url: URL,
        tracker: ProgressTracker,
        flag: CancelFlag,
        visited: VisitedDirectories
    ) async throws -> DirectoryListing {
        let options = self.options
        return try await withCheckedThrowingContinuation { continuation in
            Self.ioQueue.addOperation {
                // A cancelled scan's queued reads must not touch the disk —
                // especially not a dead network mount.
                guard !flag.isSet else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                var listing = DirectoryListing()
                let contents: [URL]
                do {
                    contents = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: Self.resourceKeys,
                        options: options.includeHiddenFiles ? [] : [.skipsHiddenFiles]
                    )
                } catch {
                    tracker.recordError(path: url.path)
                    continuation.resume(returning: listing)
                    return
                }

                listing.itemCount = contents.count
                for (index, itemURL) in contents.enumerated() {
                    // Attribute reads for a directory with hundreds of
                    // thousands of entries can take noticeable time. Avoid a
                    // lock on every item while still responding promptly.
                    if index.isMultiple(of: 256), flag.isSet {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let values = try? itemURL.resourceValues(forKeys: Self.resourceKeySet) else {
                        tracker.recordError(path: itemURL.path)
                        continue
                    }
                    // Don't follow symlinks and don't cross into other mounted volumes.
                    if values.isSymbolicLink == true || values.isVolume == true { continue }

                    if values.isDirectory == true {
                        // Each directory identity is scanned exactly once —
                        // this defeats synthetic filesystem mirrors (like
                        // /.nofollow on macOS 26, which re-exposes the whole
                        // root) and any traversal cycle, so nothing is ever
                        // double-counted.
                        guard visited.firstVisit(values.fileResourceIdentifier as? NSObject) else { continue }
                        listing.subdirectories.append(SubdirectoryEntry(
                            url: itemURL,
                            isPackage: values.isPackage == true,
                            modified: values.contentModificationDate
                        ))
                    } else {
                        let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                        listing.files.append(FileNode(
                            name: itemURL.lastPathComponent,
                            kind: .file,
                            modified: values.contentModificationDate,
                            size: size,
                            fileCount: 1
                        ))
                        listing.fileBytes += size
                    }
                }
                continuation.resume(returning: listing)
            }
        }
    }

    // MARK: - Recursive scan

    private func scanChildren(
        of url: URL,
        depth: Int,
        tracker: ProgressTracker,
        flag: CancelFlag,
        visited: VisitedDirectories
    ) async throws -> [FileNode] {
        try Task.checkCancellation()

        let listing = try await readDirectory(at: url, tracker: tracker, flag: flag, visited: visited)
        try Task.checkCancellation()
        tracker.add(items: listing.itemCount, bytes: listing.fileBytes, path: url.path)

        var directoryNodes: [FileNode] = []
        directoryNodes.reserveCapacity(listing.subdirectories.count)

        if depth < Self.parallelDepthLimit && listing.subdirectories.count > 1 {
            directoryNodes = try await withThrowingTaskGroup(of: FileNode.self) { group in
                let initialTaskCount = min(
                    Self.maxConcurrentChildTasks,
                    listing.subdirectories.count
                )
                for entry in listing.subdirectories.prefix(initialTaskCount) {
                    group.addTask { [self] in
                        try await scanDirectoryNode(entry: entry, depth: depth + 1, tracker: tracker, flag: flag, visited: visited)
                    }
                }
                var nodes: [FileNode] = []
                nodes.reserveCapacity(listing.subdirectories.count)
                var nextEntryIndex = initialTaskCount
                while let node = try await group.next() {
                    nodes.append(node)
                    if nextEntryIndex < listing.subdirectories.count {
                        let entry = listing.subdirectories[nextEntryIndex]
                        nextEntryIndex += 1
                        group.addTask { [self] in
                            try await scanDirectoryNode(entry: entry, depth: depth + 1, tracker: tracker, flag: flag, visited: visited)
                        }
                    }
                }
                return nodes
            }
        } else {
            for entry in listing.subdirectories {
                directoryNodes.append(
                    try await scanDirectoryNode(entry: entry, depth: depth + 1, tracker: tracker, flag: flag, visited: visited)
                )
            }
        }

        return listing.files + directoryNodes
    }

    private func scanDirectoryNode(
        entry: SubdirectoryEntry,
        depth: Int,
        tracker: ProgressTracker,
        flag: CancelFlag,
        visited: VisitedDirectories
    ) async throws -> FileNode {
        let node = FileNode(
            name: entry.url.lastPathComponent,
            kind: entry.isPackage ? .package : .directory,
            modified: entry.modified
        )
        let children = try await scanChildren(of: entry.url, depth: depth, tracker: tracker, flag: flag, visited: visited)
        node.finalize(children: children.sorted(by: Self.largerFirst))
        if entry.isPackage && !options.showPackageContents {
            node.collapseToLeaf()
        }
        return node
    }

    private static func largerFirst(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        if lhs.size == rhs.size {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.size > rhs.size
    }

    // MARK: - Largest leaves

    /// Top `count` leaf nodes (files, plus packages shown as leaves) by size,
    /// collected from the visible tree, largest first.
    static func collectLargestLeaves(root: FileNode, count: Int) -> [FileNode] {
        var top: [FileNode] = []  // sorted ascending by size
        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            if let children = node.children {
                stack.append(contentsOf: children)
                continue
            }
            guard node.kind != .directory else { continue }
            if top.count < count {
                insertSorted(node, into: &top)
            } else if let smallest = top.first, node.size > smallest.size {
                top.removeFirst()
                insertSorted(node, into: &top)
            }
        }
        return top.reversed()
    }

    private static func insertSorted(_ node: FileNode, into array: inout [FileNode]) {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid].size < node.size { low = mid + 1 } else { high = mid }
        }
        array.insert(node, at: low)
    }
}

/// Registry of directory identities already scanned, shared across parallel
/// tasks. `fileResourceIdentifier` compares file system objects by identity,
/// so firmlink/synthetic mirrors of an already-visited directory register as
/// duplicates and are skipped.
private final class VisitedDirectories: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: Set<AnyHashable> = []

    /// Returns true the first time an identity is seen (or when the
    /// identifier is unavailable — no dedup possible, keep scanning).
    func firstVisit(_ identifier: NSObject?) -> Bool {
        guard let identifier else { return true }
        lock.lock()
        defer { lock.unlock() }
        return identifiers.insert(AnyHashable(identifier)).inserted
    }
}

/// Cross-task cancellation flag readable from Dispatch worker threads.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Aggregates scan progress across parallel tasks and emits throttled updates.
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = ScanProgress()
    private var skippedPaths: [String] = []
    private var lastEmit = DispatchTime.now().uptimeNanoseconds
    private let onUpdate: @Sendable (ScanProgress) -> Void

    private static let emitInterval: UInt64 = 80_000_000  // 80 ms
    private static let maxSkippedSamples = 50

    init(onUpdate: @escaping @Sendable (ScanProgress) -> Void) {
        self.onUpdate = onUpdate
    }

    func add(items: Int, bytes: Int64, path: String) {
        lock.lock()
        progress.itemCount += items
        progress.byteCount += bytes
        progress.currentPath = path
        let emit = shouldEmitLocked()
        let snapshot = progress
        lock.unlock()
        if emit { onUpdate(snapshot) }
    }

    func recordError(path: String) {
        lock.lock()
        progress.errorCount += 1
        if skippedPaths.count < Self.maxSkippedSamples {
            skippedPaths.append(path)
        }
        lock.unlock()
    }

    func finalSnapshot() -> (ScanProgress, [String]) {
        lock.lock()
        defer { lock.unlock() }
        return (progress, skippedPaths)
    }

    private func shouldEmitLocked() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastEmit >= Self.emitInterval else { return false }
        lastEmit = now
        return true
    }
}
