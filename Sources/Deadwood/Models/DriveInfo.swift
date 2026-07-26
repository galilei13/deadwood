import Foundation

struct DriveInfo: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let isRemovable: Bool
    let isInternal: Bool
    let isEjectable: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var usedCapacity: Int64? {
        guard let totalCapacity, let availableCapacity else { return nil }
        return max(0, totalCapacity - availableCapacity)
    }

    var usedFraction: Double? {
        guard let totalCapacity, totalCapacity > 0, let usedCapacity else { return nil }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    var systemImage: String {
        if isRemovable || isEjectable { return "externaldrive" }
        if isInternal { return "internaldrive" }
        return "network"
    }

    static func loadAll() -> [DriveInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey,
            .volumeIsBrowsableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        return volumes.compactMap { url -> DriveInfo? in
            guard url.path != "/dev" else { return nil }
            // The data volume is already reachable through "/" via firmlinks.
            guard url.path != "/System/Volumes/Data" else { return nil }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            guard values.volumeIsBrowsable ?? true else { return nil }

            return DriveInfo(
                id: url.path,
                url: url,
                name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                totalCapacity: values.volumeTotalCapacity.map(Int64.init),
                // Prefer the "important usage" figure — it includes purgeable
                // space and matches what Finder and System Settings report.
                availableCapacity: (values.volumeAvailableCapacityForImportantUsage).flatMap { $0 > 0 ? $0 : nil }
                    ?? values.volumeAvailableCapacity.map(Int64.init)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
