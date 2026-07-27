import Foundation
import XCTest
@testable import Deadwood

final class DiskScannerTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadwood-tests-\(UUID().uuidString)", isDirectory: true)

        let directories = [
            "sub/deep",
            ".hidden",
            "noperm",
            "Fake.app/Contents"
        ]
        for directory in directories {
            try FileManager.default.createDirectory(
                at: fixtureURL.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }

        try writeFile("a.bin", byteCount: 1_024 * 1_024)
        try writeFile("sub/b.bin", byteCount: 2_048 * 1_024)
        try writeFile("sub/deep/c.bin", byteCount: 512 * 1_024)
        try writeFile(".hidden/h.bin", byteCount: 256 * 1_024)
        try writeFile("Fake.app/Contents/x.bin", byteCount: 128 * 1_024)

        try FileManager.default.createSymbolicLink(
            at: fixtureURL.appendingPathComponent("link"),
            withDestinationURL: fixtureURL.appendingPathComponent("sub")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: fixtureURL.appendingPathComponent("noperm").path
        )
    }

    override func tearDownWithError() throws {
        if let fixtureURL {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fixtureURL.appendingPathComponent("noperm").path
            )
            try? FileManager.default.removeItem(at: fixtureURL)
        }
        fixtureURL = nil
    }

    func testDefaultScanIncludesHiddenFilesAndCollapsesPackages() async throws {
        var options = ScanOptions()
        options.includeHiddenFiles = true
        options.showPackageContents = false

        let result = try await DiskScanner(options: options).scan(url: fixtureURL) { _ in }
        let root = result.root
        let logicalBytes: Int64 = Int64(1_024 + 2_048 + 512 + 256 + 128) * 1_024

        XCTAssertGreaterThanOrEqual(root.size, logicalBytes)
        XCTAssertLessThan(root.size, logicalBytes + 500_000)
        XCTAssertEqual(root.fileCount, 5)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertTrue(result.skippedPaths.first?.hasSuffix("noperm") == true)

        let names = Set((root.children ?? []).map(\.name))
        XCTAssertFalse(names.contains("link"))
        XCTAssertTrue(names.contains(".hidden"))

        let package = try XCTUnwrap(root.children?.first { $0.name == "Fake.app" })
        XCTAssertEqual(package.kind, .package)
        XCTAssertNil(package.children)
        XCTAssertGreaterThanOrEqual(package.size, 128 * 1_024)

        let subdirectory = try XCTUnwrap(root.children?.first { $0.name == "sub" })
        XCTAssertEqual(subdirectory.fileCount, 2)
        XCTAssertGreaterThanOrEqual(subdirectory.size, Int64(2_048 + 512) * 1_024)

        let deep = try XCTUnwrap(subdirectory.children?.first { $0.name == "deep" })
        XCTAssertTrue(deep.parent === subdirectory)
        XCTAssertEqual(deep.url.path, fixtureURL.appendingPathComponent("sub/deep").path)

        XCTAssertEqual(result.largestFiles.count, 5)
        XCTAssertEqual(result.largestFiles.first?.name, "b.bin")
        XCTAssertEqual(result.largestFiles.map(\.size), result.largestFiles.map(\.size).sorted(by: >))
    }

    func testHiddenFilesCanBeExcluded() async throws {
        var options = ScanOptions()
        options.includeHiddenFiles = false

        let result = try await DiskScanner(options: options).scan(url: fixtureURL) { _ in }

        XCTAssertEqual(result.root.fileCount, 4)
        XCTAssertFalse((result.root.children ?? []).contains { $0.name == ".hidden" })
    }

    func testPackageContentsCanBeExpanded() async throws {
        var options = ScanOptions()
        options.showPackageContents = true

        let result = try await DiskScanner(options: options).scan(url: fixtureURL) { _ in }
        let package = try XCTUnwrap(result.root.children?.first { $0.name == "Fake.app" })

        XCTAssertFalse(package.children?.isEmpty ?? true)
    }

    func testEqualSizedSiblingsHaveStableNameOrdering() async throws {
        try writeFile("equal-z.bin", byteCount: 4_096)
        try writeFile("equal-a.bin", byteCount: 4_096)

        let result = try await DiskScanner(options: ScanOptions()).scan(url: fixtureURL) { _ in }
        let equalNames = (result.root.children ?? [])
            .filter { $0.name.hasPrefix("equal-") }
            .map(\.name)

        XCTAssertEqual(equalNames, ["equal-a.bin", "equal-z.bin"])
    }

    func testCancellationPropagates() async throws {
        let task = Task {
            try await DiskScanner(options: ScanOptions()).scan(url: fixtureURL) { _ in }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled scan should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testLargestFilesCanBeBackfilledAfterTreeMutation() async throws {
        let result = try await DiskScanner(options: ScanOptions()).scan(url: fixtureURL) { _ in }
        let largest = try XCTUnwrap(result.largestFiles.first)

        await largest.removeFromParent()
        let refreshed = DiskScanner.collectLargestLeaves(root: result.root, count: 100)

        XCTAssertFalse(refreshed.contains { $0 === largest })
        XCTAssertEqual(refreshed.count, 4)
        XCTAssertEqual(refreshed.first?.name, "a.bin")
    }

    private func writeFile(_ relativePath: String, byteCount: Int) throws {
        let url = fixtureURL.appendingPathComponent(relativePath)
        try Data(repeating: 0xA5, count: byteCount).write(to: url)
    }
}
