import CoreGraphics
import XCTest
@testable import Deadwood

final class TreemapLayoutTests: XCTestCase {
    func testLayoutPreservesCountAreaAndSeparation() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

        let rectangles = TreemapLayout.layout(values: values, in: bounds)

        XCTAssertEqual(rectangles.count, values.count)
        let totalArea = rectangles.reduce(0.0) {
            $0 + Double($1.width * $1.height)
        }
        XCTAssertEqual(totalArea, 240_000, accuracy: 1)

        for firstIndex in rectangles.indices {
            for secondIndex in rectangles.indices where secondIndex > firstIndex {
                let overlap = rectangles[firstIndex].intersection(rectangles[secondIndex])
                XCTAssertLessThan(
                    overlap.width * overlap.height,
                    0.01,
                    "Rectangles \(firstIndex) and \(secondIndex) overlap"
                )
            }
        }

        let firstAspectRatio = Double(rectangles[0].width / rectangles[0].height)
        XCTAssertGreaterThan(firstAspectRatio, 0.2)
        XCTAssertLessThan(firstAspectRatio, 5)
    }

    func testEmptyAndZeroAreaInputsAreHandled() {
        XCTAssertEqual(TreemapLayout.layout(values: [], in: .zero), [])
        XCTAssertEqual(
            TreemapLayout.layout(values: [1, 2], in: .zero),
            [.zero, .zero]
        )
    }
}
