import SwiftUI

/// Hierarchical, sortable table of the scanned tree.
struct FileTreeTable: View {
    @Bindable var model: AppModel
    let root: FileNode

    var body: some View {
        Table(
            root.children ?? [],
            children: \.children,
            selection: $model.selection,
            sortOrder: $model.sortOrder
        ) {
            TableColumn("Name", value: \.name) { node in
                NameCell(node: node)
            }
            .width(min: 220, ideal: 340)

            TableColumn("Size", value: \.size) { node in
                Text(ByteFormatter.format(node.size))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 84, max: 120)
            .alignment(.trailing)

            TableColumn("% of Parent", value: \.fractionOfParent) { node in
                PercentCell(fraction: node.fractionOfParent)
            }
            .width(min: 110, ideal: 150, max: 240)

            TableColumn("Items", value: \.fileCount) { node in
                Text(node.kind == .file ? "—" : ByteFormatter.formatCount(node.fileCount))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 76, max: 110)
            .alignment(.trailing)

            TableColumn("Modified", value: \.modifiedSortValue) { node in
                Text(node.modified.map { Self.dateFormatter.string(from: $0) } ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 130, max: 170)

            TableColumn("Kind", value: \.typeLabel) { node in
                Text(node.typeLabel)
                    .foregroundStyle(.secondary)
            }
            .width(min: 56, ideal: 80, max: 130)
        }
        .onChange(of: model.sortOrder) {
            model.applySort()
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            FileActionMenu(model: model, nodes: model.nodes(for: ids))
        } primaryAction: { ids in
            for node in model.nodes(for: ids) {
                if node.kind == .file {
                    FileActions.open(node.url)
                } else {
                    FileActions.revealInFinder([node.url])
                }
            }
        }
        .onDeleteCommand {
            model.trashSelection()
        }
        .onKeyPress(KeyEquivalent(" ")) {
            guard !model.selectedNodes.isEmpty else { return .ignored }
            model.quickLookSelection()
            return .handled
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct NameCell: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(for: node))
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .lineLimit(1)
        }
    }
}

struct PercentCell: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                let clamped = min(max(fraction, 0), 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.quaternary.opacity(0.6))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(2, geometry.size.width * clamped))
                }
            }
            .frame(height: 9)

            Text(percentText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var percentText: String {
        let percent = fraction * 100
        if percent > 0, percent < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", min(percent, 100))
    }
}

/// Shared right-click menu for file rows (tree + largest files).
struct FileActionMenu: View {
    let model: AppModel
    let nodes: [FileNode]

    var body: some View {
        if nodes.isEmpty {
            EmptyView()
        } else {
            Button("Quick Look") {
                model.quickLook(nodes)
            }
            Button(nodes.count == 1 ? "Reveal in Finder" : "Reveal \(nodes.count) Items in Finder") {
                model.reveal(nodes)
            }
            if nodes.count == 1, let node = nodes.first, node.kind == .file {
                Button("Open") {
                    FileActions.open(node.url)
                }
            }
            Button("Copy Path") {
                model.copyPaths(nodes)
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                model.trash(nodes)
            }
            Button("Delete Permanently…", role: .destructive) {
                model.requestPermanentDelete(nodes)
            }
        }
    }
}
