import SwiftUI

/// Interactive treemap of the current treemap root.
/// Click selects, double-click drills into a folder, breadcrumb climbs back up.
struct TreemapView: View {
    @Bindable var model: AppModel
    let root: FileNode

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredID: FileNode.ID?
    @State private var hoverLocation: CGPoint = .zero
    /// Cells are recomputed only when root/size/tree/appearance change —
    /// never on hover, which fires on every mouse move.
    @State private var cells: [Cell] = []

    private struct Cell: Identifiable {
        let id: FileNode.ID
        let node: FileNode
        let rect: CGRect
        let color: Color
        let isGroupTitleVisible: Bool
        let depth: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            GeometryReader { geometry in
                canvas(cells: cells)
                    .gesture(
                        SpatialTapGesture(count: 2).onEnded { value in
                            drillIn(at: value.location, cells: cells)
                        }
                    )
                    .simultaneousGesture(
                        // Selection reacts on the first click immediately —
                        // no double-click-interval lag.
                        SpatialTapGesture().onEnded { value in
                            select(at: value.location, cells: cells)
                        }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverLocation = location
                            hoveredID = hitTest(at: location, cells: cells)?.node.id
                        case .ended:
                            hoveredID = nil
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        hoverTooltip(cells: cells, in: geometry.size)
                    }
                    .onChange(of: layoutKey(for: geometry.size), initial: true) { _, _ in
                        cells = buildCells(in: geometry.size)
                        hoveredID = nil
                    }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let path = root.ancestryPath
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        model.treemapRoot = node
                    } label: {
                        Text(node.name)
                            .font(.callout.weight(index == path.count - 1 ? .semibold : .regular))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                    .disabled(index == path.count - 1)
                }
                Spacer(minLength: 0)
                Text(ByteFormatter.format(root.size))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Layout

    private func layoutKey(for size: CGSize) -> String {
        "\(root.id)|\(Int(size.width))x\(Int(size.height))|\(model.treeVersion)|\(colorScheme)"
    }

    private func buildCells(in size: CGSize) -> [Cell] {
        let outerRect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
        guard outerRect.width > 20, outerRect.height > 20 else { return [] }

        let children = (root.children ?? [])
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
        guard !children.isEmpty else { return [] }

        let rects = TreemapLayout.layout(values: children.map { Double($0.size) }, in: outerRect)

        var cells: [Cell] = []
        for (index, child) in children.enumerated() {
            let rect = rects[index].insetBy(dx: 1.5, dy: 1.5)
            guard rect.width > 2, rect.height > 2 else { continue }

            let color = branchColor(index: index, level: 0)
            let showTitle = child.isDirectory && rect.width > 70 && rect.height > 44

            cells.append(Cell(
                id: child.id,
                node: child,
                rect: rect,
                color: color,
                isGroupTitleVisible: showTitle,
                depth: 0
            ))

            // One nested level for large folder cells.
            if let grandchildren = child.children, rect.width * rect.height > 5000 {
                let innerTop = showTitle ? CGFloat(18) : 4
                let innerRect = CGRect(
                    x: rect.minX + 4,
                    y: rect.minY + innerTop,
                    width: rect.width - 8,
                    height: rect.height - innerTop - 4
                )
                guard innerRect.width > 12, innerRect.height > 12 else { continue }

                let visible = grandchildren
                    .filter { $0.size > 0 }
                    .sorted { $0.size > $1.size }
                    .prefix(40)
                guard !visible.isEmpty else { continue }

                let innerRects = TreemapLayout.layout(values: visible.map { Double($0.size) }, in: innerRect)
                for (innerIndex, grandchild) in visible.enumerated() {
                    let cellRect = innerRects[innerIndex].insetBy(dx: 1, dy: 1)
                    guard cellRect.width > 3, cellRect.height > 3 else { continue }
                    cells.append(Cell(
                        id: grandchild.id,
                        node: grandchild,
                        rect: cellRect,
                        color: branchColor(index: index, level: 1),
                        isGroupTitleVisible: false,
                        depth: 1
                    ))
                }
            }
        }
        return cells
    }

    private func branchColor(index: Int, level: Int) -> Color {
        let hue = (0.56 + Double(index) * 0.618033988749895).truncatingRemainder(dividingBy: 1)
        if colorScheme == .dark {
            return Color(hue: hue, saturation: level == 0 ? 0.45 : 0.38, brightness: level == 0 ? 0.42 : 0.58)
        }
        return Color(hue: hue, saturation: level == 0 ? 0.38 : 0.30, brightness: level == 0 ? 0.78 : 0.90)
    }

    // MARK: - Drawing

    private func canvas(cells: [Cell]) -> some View {
        Canvas { context, _ in
            for cell in cells {
                let path = Path(roundedRect: cell.rect, cornerRadius: 3)
                context.fill(path, with: .color(cell.color))

                if cell.node.id == hoveredID {
                    context.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: 2)
                } else if model.selection.contains(cell.node.id) {
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
                } else if cell.depth == 0 {
                    context.stroke(path, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
                }

                if cell.isGroupTitleVisible {
                    drawLabel(context: context, cell: cell)
                } else if cell.depth == 1, cell.rect.width > 64, cell.rect.height > 26 {
                    drawInnerLabel(context: context, cell: cell)
                } else if cell.depth == 0, !cell.node.isDirectory, cell.rect.width > 64, cell.rect.height > 26 {
                    drawInnerLabel(context: context, cell: cell)
                }
            }
        }
    }

    private func drawLabel(context: GraphicsContext, cell: Cell) {
        let text = Text("\(cell.node.name)  \(ByteFormatter.format(cell.node.size))")
            .font(.caption.weight(.medium))
            .foregroundStyle(labelColor)
        var resolved = context.resolve(text)
        let available = CGSize(width: cell.rect.width - 12, height: 14)
        let measured = resolved.measure(in: available)
        guard measured.width <= available.width else {
            let short = Text(cell.node.name).font(.caption.weight(.medium)).foregroundStyle(labelColor)
            resolved = context.resolve(short)
            let shortSize = resolved.measure(in: available)
            guard shortSize.width <= available.width else { return }
            context.draw(resolved, at: CGPoint(x: cell.rect.minX + 6, y: cell.rect.minY + 4), anchor: .topLeading)
            return
        }
        context.draw(resolved, at: CGPoint(x: cell.rect.minX + 6, y: cell.rect.minY + 4), anchor: .topLeading)
    }

    private func drawInnerLabel(context: GraphicsContext, cell: Cell) {
        let text = Text(cell.node.name)
            .font(.caption2)
            .foregroundStyle(labelColor.opacity(0.9))
        let resolved = context.resolve(text)
        let available = CGSize(width: cell.rect.width - 8, height: 12)
        let measured = resolved.measure(in: available)
        guard measured.width <= available.width else { return }
        context.draw(resolved, at: CGPoint(x: cell.rect.midX, y: cell.rect.midY), anchor: .center)
    }

    private var labelColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.75)
    }

    // MARK: - Interaction

    /// Deepest (most specific) cell under the point.
    private func hitTest(at point: CGPoint, cells: [Cell]) -> Cell? {
        cells
            .filter { $0.rect.contains(point) }
            .max { $0.depth < $1.depth }
    }

    private func select(at point: CGPoint, cells: [Cell]) {
        guard let cell = hitTest(at: point, cells: cells) else {
            model.selection = []
            return
        }
        model.selection = [cell.node.id]
    }

    private func drillIn(at point: CGPoint, cells: [Cell]) {
        guard let cell = hitTest(at: point, cells: cells) else { return }
        var target: FileNode? = cell.node
        // Drill into the nearest folder (a grandchild file drills into its parent).
        while let node = target, node.children == nil {
            target = node.parent
        }
        if let target, target !== root {
            model.treemapRoot = target
            hoveredID = nil
        }
    }

    @ViewBuilder
    private func hoverTooltip(cells: [Cell], in size: CGSize) -> some View {
        if let hoveredID, let cell = cells.first(where: { $0.node.id == hoveredID }) {
            let node = cell.node
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(ByteFormatter.format(node.size)) — \(ByteFormatter.formatPercent(node.size, of: root.size)) of \(root.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if node.isDirectory {
                    Text("\(ByteFormatter.formatCount(node.fileCount)) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 4, y: 2)
            .frame(maxWidth: 320, alignment: .leading)
            .offset(
                x: min(hoverLocation.x + 14, max(size.width - 260, 0)),
                y: min(hoverLocation.y + 16, max(size.height - 80, 0))
            )
            .allowsHitTesting(false)
        }
    }
}
