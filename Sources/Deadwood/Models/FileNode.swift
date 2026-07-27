import Foundation
import Observation

/// A node in the scanned file tree.
///
/// Memory: nodes store only their name — the full URL is derived from the
/// ancestor chain on demand. For multi-million-file scans this saves hundreds
/// of megabytes versus storing a URL per node.
///
/// Thread-safety contract: a node (and its subtree) is built by exactly one
/// task inside `DiskScanner` and is never shared until the scan finishes.
/// After the scanner hands the root to `AppModel`, all mutation happens on
/// the main actor. That single-ownership handoff is why `@unchecked Sendable`
/// is safe here.
@Observable
final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    enum Kind: Comparable {
        case directory
        case package
        case file
    }

    let id = UUID()
    let name: String
    let kind: Kind
    let modified: Date?

    /// Set only on the scan root; all other nodes derive their URL from it.
    private let rootURL: URL?

    /// Allocated size in bytes (files: on-disk allocation; directories: sum of children).
    private(set) var size: Int64
    /// Total number of files in this subtree (1 for a file).
    private(set) var fileCount: Int
    /// `nil` for leaf rows — this drives `Table(children:)` disclosure.
    private(set) var children: [FileNode]?

    @ObservationIgnored private(set) weak var parent: FileNode?

    var isDirectory: Bool { kind != .file }

    init(name: String, kind: Kind, modified: Date?, size: Int64 = 0, fileCount: Int = 0, rootURL: URL? = nil) {
        self.name = name
        self.kind = kind
        self.modified = modified
        self.size = size
        self.fileCount = fileCount
        self.rootURL = rootURL
        self.children = kind == .file ? nil : []
    }

    /// Full file URL, rebuilt from the ancestor chain.
    /// Only valid while the node is attached to a living tree.
    var url: URL {
        if let rootURL { return rootURL }
        guard let parent else { return URL(fileURLWithPath: name) }
        return parent.url.appendingPathComponent(name)
    }

    var pathExtension: String { (name as NSString).pathExtension }

    // MARK: - Scan-time construction (single-owner, off-main)

    func finalize(children: [FileNode]) {
        var total: Int64 = 0
        var files = 0
        for child in children {
            child.parent = self
            total += child.size
            files += child.fileCount
        }
        self.children = children.isEmpty ? nil : children
        self.size = total
        self.fileCount = files
    }

    /// Collapses a scanned package into a leaf that keeps its total size.
    func collapseToLeaf() {
        children = nil
    }

    // MARK: - Post-scan mutation (main actor only)

    @MainActor
    func removeFromParent() {
        guard let parent else { return }
        parent.children?.removeAll { $0.id == id }
        if parent.children?.isEmpty == true {
            parent.children = nil  // preserve the nil-means-leaf invariant
        }
        var ancestor: FileNode? = parent
        while let node = ancestor {
            node.size -= size
            node.fileCount -= fileCount
            ancestor = node.parent
        }
        self.parent = nil
    }

    @MainActor
    func sortSubtree(by comparators: [KeyPathComparator<FileNode>]) {
        sortSubtree(areInOrder: Self.sortClosure(for: comparators))
    }

    /// Sorts the full tree without monopolizing the main actor for the entire
    /// traversal. A single unusually wide directory still has to be sorted as
    /// one unit, but large multi-directory trees yield regularly so the app
    /// can continue rendering and handling input.
    @MainActor
    func sortSubtreeIncrementally(
        by comparators: [KeyPathComparator<FileNode>],
        yieldEvery directoryCount: Int = 128
    ) async {
        let areInOrder = Self.sortClosure(for: comparators)
        var stack: [FileNode] = [self]
        var sortedDirectoryCount = 0

        while let node = stack.popLast() {
            guard !Task.isCancelled else { return }
            guard var kids = node.children else { continue }

            kids.sort(by: areInOrder)
            node.children = kids
            for child in kids where child.children != nil {
                stack.append(child)
            }

            sortedDirectoryCount += 1
            if sortedDirectoryCount.isMultiple(of: max(directoryCount, 1)) {
                await Task.yield()
            }
        }
    }

    private func sortSubtree(areInOrder: (FileNode, FileNode) -> Bool) {
        guard var kids = children else { return }
        kids.sort(by: areInOrder)
        for child in kids {
            child.sortSubtree(areInOrder: areInOrder)
        }
        children = kids
    }

    /// Specializes the primary comparator into a plain closure —
    /// KeyPathComparator dispatch is several times slower, which matters
    /// when re-sorting millions of nodes on a column-header click.
    private static func sortClosure(for comparators: [KeyPathComparator<FileNode>]) -> (FileNode, FileNode) -> Bool {
        guard let primary = comparators.first else {
            return { $0.size > $1.size }
        }
        let reverse = primary.order == .reverse

        func by<T: Comparable>(_ value: @escaping (FileNode) -> T) -> (FileNode, FileNode) -> Bool {
            { a, b in
                let x = value(a)
                let y = value(b)
                if x == y {
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                return reverse ? x > y : x < y
            }
        }

        switch primary.keyPath {
        case \FileNode.name:
            return { a, b in
                let comparison = a.name.localizedCaseInsensitiveCompare(b.name)
                if comparison == .orderedSame { return a.size > b.size }
                return reverse ? comparison == .orderedDescending : comparison == .orderedAscending
            }
        case \FileNode.size: return by { $0.size }
        case \FileNode.fileCount: return by { $0.fileCount }
        case \FileNode.modifiedSortValue: return by { $0.modifiedSortValue }
        case \FileNode.typeLabel: return by { $0.typeLabel }
        case \FileNode.fractionOfParent: return by { $0.fractionOfParent }
        default:
            return { a, b in
                for comparator in comparators {
                    switch comparator.compare(a, b) {
                    case .orderedAscending: return true
                    case .orderedDescending: return false
                    case .orderedSame: continue
                    }
                }
                return false
            }
        }
    }

    // MARK: - Queries

    var fractionOfParent: Double {
        guard let parent else { return 1 }
        guard parent.size > 0 else { return 0 }
        return Double(size) / Double(parent.size)
    }

    /// Root-first path of ancestors including self.
    var ancestryPath: [FileNode] {
        var path: [FileNode] = []
        var node: FileNode? = self
        while let current = node {
            path.append(current)
            node = current.parent
        }
        return path.reversed()
    }

    func isDescendant(of other: FileNode) -> Bool {
        var node = parent
        while let current = node {
            if current === other { return true }
            node = current.parent
        }
        return false
    }

    /// Sort key for the Modified column (items without a date sort last).
    var modifiedSortValue: Date { modified ?? .distantPast }

    var typeLabel: String {
        switch kind {
        case .directory: return "Folder"
        case .package: return pathExtension.isEmpty ? "Package" : pathExtension.uppercased()
        case .file: return pathExtension.isEmpty ? "File" : pathExtension.uppercased()
        }
    }

    // MARK: - Hashable

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
