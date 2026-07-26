import Foundation

enum ByteFormatter {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func format(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    static func formatCount(_ count: Int) -> String {
        countFormatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    static func formatPercent(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let percent = Double(part) / Double(total) * 100
        if percent < 0.1 && part > 0 {
            return "<0.1%"
        }
        return String(format: "%.1f%%", percent)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 { return String(format: "%.2fs", interval) }
        if interval < 60 { return String(format: "%.1fs", interval) }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return "\(minutes)m \(seconds)s"
    }
}
