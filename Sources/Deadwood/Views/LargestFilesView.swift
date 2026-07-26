import SwiftUI

/// Flat list of the biggest space consumers found in the scan.
struct LargestFilesView: View {
    @Bindable var model: AppModel

    var body: some View {
        Table(model.largestFiles, selection: $model.selection) {
            TableColumn("#") { node in
                Text(rankText(for: node))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(28)
            .alignment(.trailing)

            TableColumn("Name") { node in
                NameCell(node: node)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Size") { node in
                HStack(spacing: 8) {
                    Text(ByteFormatter.format(node.size))
                        .monospacedDigit()
                        .frame(width: 76, alignment: .trailing)
                    PercentCell(fraction: fractionOfLargest(node))
                }
            }
            .width(min: 150, ideal: 210, max: 280)

            TableColumn("Location") { node in
                Text(parentPath(of: node))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(node.url.path)
            }
            .width(min: 200, ideal: 360)
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            FileActionMenu(model: model, nodes: model.nodes(for: ids))
        } primaryAction: { ids in
            model.reveal(model.nodes(for: ids))
        }
        .onDeleteCommand {
            model.trashSelection()
        }
        .onKeyPress(KeyEquivalent(" ")) {
            guard !model.selectedNodes.isEmpty else { return .ignored }
            model.quickLookSelection()
            return .handled
        }
        .overlay {
            if model.largestFiles.isEmpty {
                ContentUnavailableView(
                    "No Files Found",
                    systemImage: "doc",
                    description: Text("The scanned folder contains no files.")
                )
            }
        }
    }

    private func rankText(for node: FileNode) -> String {
        if let index = model.largestFiles.firstIndex(where: { $0 === node }) {
            return String(index + 1)
        }
        return ""
    }

    private func fractionOfLargest(_ node: FileNode) -> Double {
        guard let largest = model.largestFiles.first, largest.size > 0 else { return 0 }
        return Double(node.size) / Double(largest.size)
    }

    private func parentPath(of node: FileNode) -> String {
        node.url.deletingLastPathComponent().path
    }
}
