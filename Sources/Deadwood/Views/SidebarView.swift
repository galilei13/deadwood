import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selectedTarget) {
            Section("Devices") {
                ForEach(model.drives) { drive in
                    DriveRow(drive: drive)
                        .tag(ScanTarget.drive(drive))
                }
            }

            Section("Locations") {
                ForEach(model.quickLocations) { location in
                    Label(location.name, systemImage: location.systemImage)
                        .tag(ScanTarget.folder(location.url))
                        .help(location.url.path)
                }
            }

            if !model.recentFolders.isEmpty {
                Section("Recent Scans") {
                    ForEach(model.recentFolders, id: \.path) { url in
                        Label(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, systemImage: "clock.arrow.circlepath")
                            .tag(ScanTarget.folder(url))
                            .help(url.path)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Solid panel — no translucent/glass material behind the list.
        // Empty ignoresSafeAreaEdges keeps the color below the toolbar, so
        // the title-bar strip stays uniform across the whole window.
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor), ignoresSafeAreaEdges: [])
        .contextMenu(forSelectionType: ScanTarget.self) { targets in
            if let target = targets.first {
                Button("Scan \(target.displayName)") {
                    model.startScan(at: target.url)
                }
                Button("Reveal in Finder") {
                    FileActions.revealInFinder([target.url])
                }
            }
        } primaryAction: { targets in
            if let target = targets.first {
                model.startScan(at: target.url)
            }
        }
        .safeAreaInset(edge: .bottom) {
            scanButton
        }
    }

    private var scanButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                model.scanSelectedTarget()
            } label: {
                Label(
                    model.selectedTarget.map { "Scan \($0.displayName)" } ?? "Scan",
                    systemImage: "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedTarget == nil || model.isScanning)
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DriveRow: View {
    let drive: DriveInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(drive.name, systemImage: drive.systemImage)
                .lineLimit(1)

            if let fraction = drive.usedFraction {
                CapacityBar(fraction: fraction)
            }

            if let available = drive.availableCapacity, let total = drive.totalCapacity {
                Text("\(ByteFormatter.format(available)) free of \(ByteFormatter.format(total))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .help(drive.url.path)
    }
}

struct CapacityBar: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(height, geometry.size.width * clamped))
            }
        }
        .frame(height: height)
    }

    private var fillColor: Color {
        switch fraction {
        case 0.92...: return .red
        case 0.8...: return .orange
        default: return .accentColor
        }
    }
}
