import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @AppStorage(ScanOptions.defaultsIncludeHiddenKey) private var includeHiddenFiles = true
    @AppStorage(ScanOptions.defaultsShowPackagesKey) private var showPackageContents = false

    var body: some View {
        mainContent
            .quickLookPreview($model.quickLookURL, in: model.quickLookItems)
            .fileImporter(
                isPresented: $model.isFolderPickerPresented,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    model.startScan(at: url)
                }
            }
            .alert("Error", isPresented: errorAlertShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("Delete Permanently?", isPresented: deleteAlertShown) {
                Button("Delete", role: .destructive) {
                    model.confirmPermanentDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(permanentDeleteMessage)
            }
    }

    private var mainContent: some View {
        // A plain fixed panel instead of NavigationSplitView — no collapsible
        // sidebar, no draggable divider, no animation to go wrong.
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 250)
            Divider()
            detail
                .frame(minWidth: 660, minHeight: 580)
        }
        .toolbar { toolbarContent }
        .navigationTitle("Deadwood")
        .navigationSubtitle(model.scannedRoot.map { $0.url.path } ?? "")
    }

    private var errorAlertShown: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var deleteAlertShown: Binding<Bool> {
        Binding(
            get: { !model.pendingPermanentDelete.isEmpty },
            set: { if !$0 { model.pendingPermanentDelete = PendingDeletion() } }
        )
    }

    private var permanentDeleteMessage: String {
        let nodes = model.pendingPermanentDelete.nodes
        let names = nodes.prefix(4).map { "“\($0.name)”" }.joined(separator: ", ")
        let suffix = nodes.count > 4 ? " and \(nodes.count - 4) more items" : ""
        let size = ByteFormatter.format(nodes.reduce(0) { $0 + $1.size })
        return "\(names)\(suffix) (\(size)) will be deleted immediately. This cannot be undone."
    }

    @ViewBuilder
    private var detail: some View {
        if model.isScanning {
            ScanningView(model: model)
        } else if let root = model.scannedRoot {
            VStack(spacing: 0) {
                switch model.viewMode {
                case .tree:
                    FileTreeTable(model: model, root: root)
                case .treemap:
                    TreemapView(model: model, root: model.treemapRoot ?? root)
                case .largest:
                    LargestFilesView(model: model)
                }
                Divider()
                StatusBarView(model: model)
            }
        } else {
            EmptyStateView(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if model.isScanning {
                Button {
                    model.cancelScan()
                } label: {
                    Label("Stop Scan", systemImage: "stop.fill")
                }
                .help("Stop the current scan (⌘.)")
            } else {
                Button {
                    model.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.scannedRoot == nil)
                .help("Scan the same folder again (⌘R)")
            }

            Button {
                model.isFolderPickerPresented = true
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .disabled(model.isScanning)
            .help("Choose a folder to scan (⌘O)")
        }

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $model.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.scannedRoot == nil)
            .help("Switch between tree, treemap and largest files (⌘1–⌘3)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.quickLookSelection()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
            .disabled(model.selectedNodes.isEmpty)
            .help("Preview the selection with Quick Look (Space)")

            Button {
                model.revealSelectionInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.forward.circle")
            }
            .disabled(model.selectedNodes.isEmpty)
            .help("Show the selection in Finder")

            Button {
                model.trashSelection()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(model.selectedNodes.isEmpty || model.isDeleting)
            .help("Move the selection to the Trash (⌫)")

            Menu {
                Button("Copy Path") {
                    model.copySelectionPaths()
                }
                .disabled(model.selectedNodes.isEmpty)

                Button("Delete Permanently…", role: .destructive) {
                    model.requestPermanentDeleteOfSelection()
                }
                .disabled(model.selectedNodes.isEmpty || model.isDeleting)

                Divider()

                Toggle("Include Hidden Files", isOn: $includeHiddenFiles)
                Toggle("Show Package Contents", isOn: $showPackageContents)
                Text("Options apply to the next scan")

                Divider()

                Button("Open Full Disk Access Settings…") {
                    FileActions.openFullDiskAccessSettings()
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}
