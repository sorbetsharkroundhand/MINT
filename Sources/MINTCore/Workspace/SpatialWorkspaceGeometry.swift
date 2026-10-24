import AppKit

/// Top-left coordinates. Minimum tile sizes expand the scrollable canvas, never discard tiles.
struct SpatialWorkspaceGeometry {
    static let inset: CGFloat = 8
    static let columnGap: CGFloat = 8
    static let rowGap: CGFloat = 8
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 8
    var columns: [CGRect] = []
    var tiles: [WorkspaceTileID: CGRect] = [:]
    var contentSize: CGSize

    init(layout: SpatialWorkspaceLayout, viewport: CGSize) {
        let availableWidth = max(0, viewport.width.isFinite ? viewport.width : 0)
        let availableHeight = max(0, viewport.height.isFinite ? viewport.height : 0)
        if layout.isSingleManuscript, let tile = layout.tiles.first {
            contentSize = CGSize(width: availableWidth, height: availableHeight)
            let paper = CGRect(origin: .zero, size: contentSize)
            columns = [paper]; tiles = [tile: paper]
            return
        }
        let gapWidth = CGFloat(max(0, layout.columns.count - 1)) * Self.columnGap
        let minimumWidths = layout.columns.map { column -> CGFloat in
            if let width = column.width, width.isFinite { return CGFloat(width) }
            return CGFloat(column.slots.map { $0.tile.minimumWidth }.max() ?? 260)
        }
        let requiredWidth = minimumWidths.reduce(0, +) + gapWidth + 2 * Self.inset
        let flexible = layout.columns.filter { $0.width == nil }.count
        let excess = max(0, availableWidth - requiredWidth)
        let requiredHeight = layout.columns.map { column -> CGFloat in
            guard let minimumWeight = column.slots.map(\.weight).min(), minimumWeight > 0 else { return 0 }
            return 95 / CGFloat(minimumWeight) + CGFloat(max(0, column.slots.count - 1)) * Self.rowGap
        }.max() ?? 0
        contentSize = CGSize(width: max(availableWidth, requiredWidth), height: max(availableHeight, requiredHeight + Self.topInset + Self.bottomInset))
        let height = max(0, contentSize.height - Self.topInset - Self.bottomInset)
        var x = Self.inset
        for (index, column) in layout.columns.enumerated() {
            var width = minimumWidths[index]
            if column.width == nil, flexible > 0 { width += excess / CGFloat(flexible) }
            if flexible == 0, index == 0 { width += excess }
            columns.append(CGRect(x: x, y: Self.topInset, width: width, height: height))
            let rowSpace = max(0, height - CGFloat(max(0, column.slots.count - 1)) * Self.rowGap)
            var y = Self.topInset
            for slot in column.slots {
                let slotHeight = rowSpace * CGFloat(slot.weight)
                tiles[slot.tile] = CGRect(x: x, y: y, width: width, height: slotHeight)
                y += slotHeight + Self.rowGap
            }
            x += width + Self.columnGap
        }
    }

    func dropTarget(at point: CGPoint, dragging: WorkspaceTileID, fromNavigator: Bool = false) -> SpatialDropTarget? {
        guard CGRect(origin: .zero, size: contentSize).contains(point) else { return nil }
        if columns.isEmpty { return .end }
        if point.x < Self.inset + 36 { return .start }
        if point.x > contentSize.width - Self.inset - 36 { return .end }
        for (tile, rect) in tiles where tile != dragging && tile != .insertionPreview && !(fromNavigator && tile == .navigator) {
            guard rect.contains(point), rect.width > 0, rect.height > 0 else { continue }
            let y = (point.y - rect.minY) / rect.height
            if y < 0.28 { return .above(tile) }
            if y > 0.72 { return .below(tile) }
            return point.x < rect.midX ? .before(tile) : .after(tile)
        }
        return nil
    }

}
