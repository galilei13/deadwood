import XCTest
@testable import Deadwood

final class FileActionsTests: XCTestCase {
    func testSupportURLUsesTheProjectGitHubPagesSite() {
        XCTAssertEqual(FileActions.supportURL.scheme, "https")
        XCTAssertEqual(FileActions.supportURL.host, "galilei13.github.io")
        XCTAssertEqual(FileActions.supportURL.path, "/deadwood")
        XCTAssertTrue(FileActions.supportURL.absoluteString.hasSuffix("/deadwood/"))
    }
}
