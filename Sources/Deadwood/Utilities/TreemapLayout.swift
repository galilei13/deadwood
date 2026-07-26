import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing & van Wijk).
/// Input values must be positive and sorted in descending order; the returned
/// rects are parallel to the input array.
enum TreemapLayout {
    static func layout(values: [Double], in rect: CGRect) -> [CGRect] {
        guard !values.isEmpty else { return [] }
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else {
            return Array(repeating: .zero, count: values.count)
        }

        // Work in "area" units scaled to the rect.
        let scale = (rect.width * rect.height) / total
        let areas = values.map { $0 * scale }

        var result: [CGRect] = []
        result.reserveCapacity(values.count)
        var remaining = rect
        var index = 0

        while index < areas.count {
            let shortSide = max(min(remaining.width, remaining.height), 1e-6)

            // Grow the current row while it improves the worst aspect ratio.
            var rowEnd = index + 1
            var rowSum = areas[index]
            var rowMax = areas[index]
            var rowMin = areas[index]
            var worst = worstAspect(sum: rowSum, maxArea: rowMax, minArea: rowMin, shortSide: shortSide)

            while rowEnd < areas.count {
                let next = areas[rowEnd]
                let newSum = rowSum + next
                let newMax = max(rowMax, next)
                let newMin = min(rowMin, next)
                let newWorst = worstAspect(sum: newSum, maxArea: newMax, minArea: newMin, shortSide: shortSide)
                if newWorst > worst { break }
                rowSum = newSum
                rowMax = newMax
                rowMin = newMin
                worst = newWorst
                rowEnd += 1
            }

            result.append(contentsOf: layoutRow(areas[index..<rowEnd], sum: rowSum, in: &remaining))
            index = rowEnd
        }

        return result
    }

    /// Worst aspect ratio of a row with the given area stats laid along `shortSide`.
    private static func worstAspect(sum: Double, maxArea: Double, minArea: Double, shortSide: Double) -> Double {
        let s2 = sum * sum
        let w2 = Double(shortSide) * Double(shortSide)
        return max((w2 * maxArea) / s2, s2 / (w2 * minArea))
    }

    /// Lays one row of areas along the short side of `remaining`, shrinking it.
    private static func layoutRow(_ areas: ArraySlice<Double>, sum: Double, in remaining: inout CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        rects.reserveCapacity(areas.count)

        if remaining.width >= remaining.height {
            // Vertical strip on the leading edge.
            let stripWidth = CGFloat(sum) / max(remaining.height, 1e-6)
            var y = remaining.minY
            for area in areas {
                let itemHeight = CGFloat(area) / max(stripWidth, 1e-6)
                rects.append(CGRect(x: remaining.minX, y: y, width: stripWidth, height: itemHeight))
                y += itemHeight
            }
            remaining.origin.x += stripWidth
            remaining.size.width = max(0, remaining.size.width - stripWidth)
        } else {
            // Horizontal strip on the top edge.
            let stripHeight = CGFloat(sum) / max(remaining.width, 1e-6)
            var x = remaining.minX
            for area in areas {
                let itemWidth = CGFloat(area) / max(stripHeight, 1e-6)
                rects.append(CGRect(x: x, y: remaining.minY, width: itemWidth, height: stripHeight))
                x += itemWidth
            }
            remaining.origin.y += stripHeight
            remaining.size.height = max(0, remaining.size.height - stripHeight)
        }

        return rects
    }
}
