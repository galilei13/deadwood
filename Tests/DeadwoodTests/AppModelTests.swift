import Foundation
import XCTest
@testable import Deadwood

@MainActor
final class AppModelTests: XCTestCase {
    func testStartingScanClearsQuickLookState() async throws {
        let fixture = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let previewURL = fixture.appendingPathComponent("preview.txt")
        try Data("preview".utf8).write(to: previewURL)

        let root = FileNode(
            name: fixture.lastPathComponent,
            kind: .directory,
            modified: nil,
            rootURL: fixture
        )
        let child = FileNode(
            name: previewURL.lastPathComponent,
            kind: .file,
            modified: nil,
            size: 7,
            fileCount: 1
        )
        root.finalize(children: [child])

        let model = AppModel()
        model.quickLook([child])
        XCTAssertEqual(model.quickLookURL, previewURL)
        XCTAssertEqual(model.quickLookItems, [previewURL])

        model.startScan(at: fixture)

        XCTAssertNil(model.quickLookURL)
        XCTAssertTrue(model.quickLookItems.isEmpty)
        try await waitUntil { !model.isScanning }
    }

    func testPermanentDeletionBackfillsLargestFiles() async throws {
        let fixture = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }

        for index in 0...100 {
            let name = String(format: "file-%03d.bin", index)
            let url = fixture.appendingPathComponent(name)
            try Data(repeating: UInt8(index % 255), count: (index + 1) * 4_096).write(to: url)
        }

        let model = AppModel()
        model.startScan(at: fixture)
        try await waitUntil { !model.isScanning }

        XCTAssertEqual(model.largestFiles.count, 100)
        let largest = try XCTUnwrap(model.largestFiles.first)
        XCTAssertEqual(largest.name, "file-100.bin")

        model.requestPermanentDelete([largest])
        model.confirmPermanentDelete()
        try await waitUntil { !model.isDeleting }

        XCTAssertEqual(model.largestFiles.count, 100)
        XCTAssertFalse(model.largestFiles.contains { $0 === largest })
        XCTAssertEqual(model.largestFiles.first?.name, "file-099.bin")
        XCTAssertEqual(model.largestFiles.last?.name, "file-000.bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.appendingPathComponent("file-100.bin").path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadwood-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for asynchronous model state")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
