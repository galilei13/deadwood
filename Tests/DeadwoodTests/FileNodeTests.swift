import Foundation
import XCTest
@testable import Deadwood

@MainActor
final class FileNodeTests: XCTestCase {
    func testIncrementalSortOrdersEveryDirectory() async {
        let nested = FileNode(name: "nested", kind: .directory, modified: nil)
        nested.finalize(children: [
            FileNode(name: "small", kind: .file, modified: nil, size: 1, fileCount: 1),
            FileNode(name: "large", kind: .file, modified: nil, size: 9, fileCount: 1)
        ])

        let root = FileNode(
            name: "root",
            kind: .directory,
            modified: nil,
            rootURL: URL(fileURLWithPath: "/tmp/root")
        )
        root.finalize(children: [
            FileNode(name: "middle", kind: .file, modified: nil, size: 5, fileCount: 1),
            nested
        ])

        await root.sortSubtreeIncrementally(
            by: [KeyPathComparator(\FileNode.size, order: .reverse)],
            yieldEvery: 1
        )

        XCTAssertEqual(root.children?.map(\.name), ["nested", "middle"])
        XCTAssertEqual(nested.children?.map(\.name), ["large", "small"])
    }
}
