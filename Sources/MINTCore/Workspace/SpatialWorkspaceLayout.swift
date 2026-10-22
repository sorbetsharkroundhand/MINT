import Foundation

enum WorkspaceTileID: Hashable, Codable, Sendable, Identifiable {
    case document(WritingDocumentID)
    case navigator, characters, narrative, margin, context, outline, map, review, search, inspector
    case insertionPreview

    var id: String {
        switch self {
        case .document(let id): "document.\(id.rawValue.uuidString)"
        case .navigator: "navigator"
        case .characters: "characters"
        case .narrative: "narrative"
        case .margin: "margin"
        case .context: "context"
        case .outline: "outline"
        case .map: "map"
        case .review: "review"
        case .search: "search"
        case .inspector: "inspector"
        case .insertionPreview: "insertion-preview"
        }
    }
    var documentID: WritingDocumentID? {
        if case .document(let id) = self { id } else { nil }
    }
    var minimumWidth: Double {
        switch self { case .navigator: 165; case .document, .insertionPreview: 260; case .search, .inspector: 300; default: 210 }
    }
    var maximumWidth: Double {
        switch self { case .navigator: 320; case .document: 1600; default: 420 }
    }
    var idealWidth: Double? {
        switch self { case .navigator: 204; case .document, .insertionPreview: nil; case .search, .inspector: 340; default: 256 }
    }
}

enum SpatialDropTarget: Equatable, Sendable {
    case start, end
    case before(WorkspaceTileID), after(WorkspaceTileID)
    case above(WorkspaceTileID), below(WorkspaceTileID)

    var tile: WorkspaceTileID? {
        switch self {
        case .before(let id), .after(let id), .above(let id), .below(let id): id
        case .start, .end: nil
        }
    }
}

struct SpatialWorkspaceSlot: Equatable, Codable, Sendable {
    var tile: WorkspaceTileID
    var weight: Double = 1
}

struct SpatialWorkspaceColumn: Equatable, Codable, Sendable, Identifiable {
    var id = UUID()
    var width: Double?
    var slots: [SpatialWorkspaceSlot]

    mutating func normalize() {
        guard !slots.isEmpty else { return }
        for index in slots.indices where !slots[index].weight.isFinite || slots[index].weight <= 0 {
            slots[index].weight = 1
        }
        let scale = slots.map(\.weight).max() ?? 1
        let sum = slots.reduce(0) { $0 + $1.weight / scale }
        for index in slots.indices { slots[index].weight = (slots[index].weight / scale) / sum }
        if let width, !width.isFinite { self.width = nil }
    }
}

/// Presentation only. Document IDs refer back to the sole ProjectSession owner.
struct SpatialWorkspaceLayout: Equatable, Codable, Sendable {
    var columns: [SpatialWorkspaceColumn]
    var tiles: [WorkspaceTileID] { columns.flatMap { $0.slots.map(\.tile) } }
    var openDocuments: [WritingDocumentID] { tiles.compactMap(\.documentID) }

    init(documents: [WritingDocumentID], selected: WritingDocumentID?, navigatorVisible: Bool = true) {
        columns = navigatorVisible ? [.init(width: 204, slots: [.init(tile: .navigator)])] : []
        guard let first = selected.flatMap({ documents.contains($0) ? $0 : nil }) ?? documents.first else { return }
        openDocument(first)
        if let next = documents.first(where: { $0 != first }) { openDocument(next) }
    }

    func contains(_ tile: WorkspaceTileID) -> Bool { tiles.contains(tile) }

    mutating func openDocument(_ id: WritingDocumentID) {
        guard !contains(.document(id)) else { return }
        let position = columns.lastIndex { $0.slots.contains { $0.tile.documentID != nil } }
            .map { $0 + 1 } ?? columns.endIndex
        columns.insert(.init(width: nil, slots: [.init(tile: .document(id))]), at: position)
    }

    mutating func openAll(_ documents: [WritingDocumentID]) {
        for id in documents where !contains(.document(id)) {
            columns.append(.init(width: nil, slots: [.init(tile: .document(id))]))
        }
    }

    @discardableResult mutating func close(_ tile: WorkspaceTileID) -> Bool {
        guard contains(tile), tile.documentID == nil || openDocuments.count > 1 else { return false }
        remove(tile)
        return true
    }

    mutating func toggle(_ tile: WorkspaceTileID) {
        guard tile.documentID == nil else { return }
        if contains(tile) { remove(tile); return }
        if tile == .navigator {
            columns.insert(.init(width: 204, slots: [.init(tile: tile)]), at: 0)
        } else if let last = columns.indices.last,
                  !columns[last].slots.contains(where: { $0.tile.documentID != nil || $0.tile == .navigator }) {
            let weight = 1 / Double(columns[last].slots.count + 1)
            columns[last].slots.append(.init(tile: tile, weight: weight))
            columns[last].normalize()
        } else {
            columns.append(.init(width: tile.idealWidth, slots: [.init(tile: tile)]))
        }
    }

    /// Used only by a reversible drag transaction; unlike close, a temporary layout may be empty.
    mutating func remove(_ tile: WorkspaceTileID) {
        for index in columns.indices {
            columns[index].slots.removeAll { $0.tile == tile }
            columns[index].normalize()
        }
        columns.removeAll { $0.slots.isEmpty }
    }

    mutating func move(_ tile: WorkspaceTileID, to target: SpatialDropTarget, swapSingleColumns: Bool = false) {
        guard target.tile != tile else { return }
        if swapSingleColumns, case .before = target, swapColumns(tile, target.tile) { return }
        if swapSingleColumns, case .after = target, swapColumns(tile, target.tile) { return }
        remove(tile)
        let newColumn = SpatialWorkspaceColumn(width: tile.idealWidth, slots: [.init(tile: tile)])
        switch target {
        case .start: columns.insert(newColumn, at: 0)
        case .end: columns.append(newColumn)
        case .before(let anchor), .after(let anchor), .above(let anchor), .below(let anchor):
            guard let column = columns.firstIndex(where: { $0.slots.contains { $0.tile == anchor } }),
                  let row = columns[column].slots.firstIndex(where: { $0.tile == anchor }) else {
                columns.append(newColumn); return
            }
            switch target {
            case .before: columns.insert(newColumn, at: column)
            case .after: columns.insert(newColumn, at: column + 1)
            case .above, .below:
                let half = max(0.25, columns[column].slots[row].weight / 2)
                columns[column].slots[row].weight = half
                let insertion = target == .above(anchor) ? row : row + 1
                columns[column].slots.insert(.init(tile: tile, weight: half), at: insertion)
                columns[column].normalize()
            default: break
            }
        }
    }

    private mutating func swapColumns(_ tile: WorkspaceTileID, _ anchor: WorkspaceTileID?) -> Bool {
        guard let anchor,
              let from = columns.firstIndex(where: { $0.slots.count == 1 && $0.slots[0].tile == tile }),
              let to = columns.firstIndex(where: { $0.slots.count == 1 && $0.slots[0].tile == anchor }), from != to else { return false }
        columns.swapAt(from, to); return true
    }

    mutating func setColumnWidth(_ column: Int, width: Double) {
        guard columns.indices.contains(column), width.isFinite,
              let tile = columns[column].slots.first?.tile else { return }
        columns[column].width = min(tile.maximumWidth, max(tile.minimumWidth, width)).rounded()
    }

    mutating func resizeRows(column: Int, row: Int, delta: Double, height: Double) {
        guard columns.indices.contains(column), columns[column].slots.indices.contains(row),
              columns[column].slots.indices.contains(row + 1), delta.isFinite, height.isFinite else { return }
        let combined = columns[column].slots[row].weight + columns[column].slots[row + 1].weight
        let top = columns[column].slots[row].weight + delta / max(200, height) * combined
        columns[column].slots[row].weight = min(combined * 0.8, max(combined * 0.2, top))
        columns[column].slots[row + 1].weight = combined - columns[column].slots[row].weight
    }

    mutating func equalizeRows(column: Int, row: Int) {
        guard columns.indices.contains(column), columns[column].slots.indices.contains(row),
              columns[column].slots.indices.contains(row + 1) else { return }
        let half = (columns[column].slots[row].weight + columns[column].slots[row + 1].weight) / 2
        columns[column].slots[row].weight = half; columns[column].slots[row + 1].weight = half
    }

    func reorderedDocuments(_ original: [WritingDocumentID]) -> [WritingDocumentID] {
        let open = openDocuments.filter { original.contains($0) }
        var result = original, offset = 0
        for index in result.indices where open.contains(result[index]) {
            result[index] = open[offset]; offset += 1
        }
        return result
    }

    mutating func normalize(validDocuments: [WritingDocumentID]) {
        var seen: Set<WorkspaceTileID> = [], columnIDs: Set<UUID> = []
        for index in columns.indices {
            if !columnIDs.insert(columns[index].id).inserted { columns[index].id = UUID() }
            columns[index].slots.removeAll {
                // Keep the legacy enum case decodable without restoring a settings tile.
                if $0.tile == .insertionPreview || $0.tile == .inspector { return true }
                if let id = $0.tile.documentID, !validDocuments.contains(id) { return true }
                return !seen.insert($0.tile).inserted
            }
            columns[index].normalize()
            if let width = columns[index].width { setColumnWidth(index, width: width) }
        }
        columns.removeAll { $0.slots.isEmpty }
        if openDocuments.isEmpty, let first = validDocuments.first { openDocument(first) }
    }
}
