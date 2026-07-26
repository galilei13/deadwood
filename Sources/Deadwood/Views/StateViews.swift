import SwiftUI

/// Shown before the first scan.
struct EmptyStateView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Find What's Eating Your Disk")
                    .font(.title2.weight(.semibold))
                Text("Pick a drive or folder in the sidebar and press Scan,\nor jump straight in:")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    model.startScan(at: FileManager.default.homeDirectoryForCurrentUser)
                } label: {
                    Label("Scan Home Folder", systemImage: "house")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.isFolderPickerPresented = true
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-detail progress screen while a scan runs.
struct ScanningView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                Text("Scanning…")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 24) {
                    stat(value: ByteFormatter.formatCount(model.progress.itemCount), label: "items")
                    stat(value: ByteFormatter.format(model.progress.byteCount), label: "found")
                    if let start = model.scanStart {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            stat(value: ByteFormatter.formatDuration(context.date.timeIntervalSince(start)), label: "elapsed")
                        }
                    }
                }

                Text(model.progress.currentPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
                    .padding(.top, 2)

                if model.progress.errorCount > 0 {
                    Text("\(model.progress.errorCount) items could not be read")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Button("Cancel", role: .cancel) {
                model.cancelScan()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 90)
    }
}

/// Bottom status bar shown with scan results.
struct StatusBarView: View {
    @Bindable var model: AppModel
    @State private var isErrorPopoverShown = false

    var body: some View {
        HStack(spacing: 14) {
            if let root = model.scannedRoot {
                Label(
                    "\(ByteFormatter.formatCount(root.fileCount)) files — \(ByteFormatter.format(root.size))",
                    systemImage: "internaldrive"
                )
                .foregroundStyle(.secondary)

                if let result = model.result {
                    Text("Scanned in \(ByteFormatter.formatDuration(result.duration))")
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if model.isDeleting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Deleting…")
                        .foregroundStyle(.secondary)
                }
            }

            if !model.selectedNodes.isEmpty {
                Text("Selected: \(ByteFormatter.formatCount(model.topLevelSelection.count)) — \(ByteFormatter.format(model.selectedTotalSize))")
                    .foregroundStyle(.secondary)
            }

            if let result = model.result, result.errorCount > 0 {
                Button {
                    isErrorPopoverShown.toggle()
                } label: {
                    Label("\(result.errorCount) skipped", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isErrorPopoverShown, arrowEdge: .bottom) {
                    SkippedItemsPopover(result: result)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct SkippedItemsPopover: View {
    let result: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(result.errorCount) items could not be read")
                .font(.headline)

            Text("These folders were skipped, usually because the app lacks permission. Grant Deadwood **Full Disk Access** for complete results.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !result.skippedPaths.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(result.skippedPaths, id: \.self) { path in
                            Text(path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }

            Button("Open Full Disk Access Settings…") {
                FileActions.openFullDiskAccessSettings()
            }
        }
        .padding(14)
        .frame(width: 420)
    }
}
