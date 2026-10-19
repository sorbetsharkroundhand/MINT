import AppKit
import Combine

@MainActor final class SpatialWorkspaceController: ObservableObject {
    @Published private(set) var layout = SpatialWorkspaceLayout(documents: [], selected: nil)
    @Published private(set) var previewTarget: SpatialDropTarget?
    @Published private(set) var pointer = CGPoint.zero
    @Published private(set) var isDragging = false
    @Published var typewriter = false { didSet { persist() } }
    @Published var focusDimming = false { didSet { persist() } }
    @Published var whisperTyping = false
    @Published var expandedItem: String?
    var onCommit: ((SpatialWorkspaceLayout) -> Void)?
    var onActivate: ((WritingDocumentID) -> Void)?
    private(set) var projectID: WritingProjectID?
    private var defaults: UserDefaults
    private var validDocuments: [WritingDocumentID] = []
    private var drag: Drag?
    private var loading = false

    private struct Drag {
        let tile: WorkspaceTileID
        let origin: SpatialWorkspaceLayout
        let start: CGPoint
        let fromNavigator: Bool
        var lastTarget: SpatialDropTarget?
    }
    private struct Preference: Codable {
        var version = 1
        var layout: SpatialWorkspaceLayout
        var typewriter: Bool
        var focusDimming: Bool
    }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var draggedTile: WorkspaceTileID? { isDragging ? drag?.tile : nil }
    var dragFromNavigator: Bool { drag?.fromNavigator == true }
    var presentationLayout: SpatialWorkspaceLayout {
        guard isDragging, let drag, let previewTarget else { return layout }
        var preview = layout
        preview.move(drag.tile, to: previewTarget)
        if drag.tile.documentID == nil,
           let index = preview.columns.firstIndex(where: { $0.slots.count == 1 && $0.slots[0].tile == drag.tile }) {
            preview.columns[index].width = 204
        }
        return preview
    }

    func configure(project: WritingProject, selected: WritingDocumentID?, defaults: UserDefaults? = nil) {
        if let defaults { self.defaults = defaults }
        validDocuments = project.documents.filter { !project.trashedDocumentIDs.contains($0.id) }.map(\.id)
        if projectID != project.id {
            cancelDrag(); loading = true; projectID = project.id
            if let data = self.defaults.data(forKey: preferenceKey),
               let saved = try? JSONDecoder().decode(Preference.self, from: data), saved.version == 1 {
                layout = saved.layout; typewriter = saved.typewriter; focusDimming = saved.focusDimming
            } else {
                layout = SpatialWorkspaceLayout(documents: validDocuments, selected: selected,
                    navigatorVisible: self.defaults.object(forKey: "mint.sidebarVisible") as? Bool ?? true)
                typewriter = false; focusDimming = false
            }
            whisperTyping = false; expandedItem = nil; loading = false
        }
        guard !isDragging else { return }
        var normalized = layout
        normalized.normalize(validDocuments: validDocuments)
        if let selected, validDocuments.contains(selected) { normalized.openDocument(selected) }
        if normalized != layout { layout = normalized }
        persist()
    }

    func open(_ id: WritingDocumentID) {
        guard validDocuments.contains(id) else { return }
        layout.openDocument(id); commit(); onActivate?(id)
    }
    func openAll() { layout.openAll(validDocuments); commit() }
    func toggle(_ tile: WorkspaceTileID) { cancelDrag(); layout.toggle(tile); commit() }
    @discardableResult func close(_ tile: WorkspaceTileID) -> Bool {
        cancelDrag()
        guard layout.close(tile) else { return false }
        commit(); return true
    }
    func setLayout(_ value: SpatialWorkspaceLayout, persist: Bool = true) {
        layout = value
        if persist { commit() }
    }

    func beginDrag(_ tile: WorkspaceTileID, at point: CGPoint, fromNavigator: Bool = false) {
        cancelDrag()
        drag = Drag(tile: tile, origin: layout, start: point, fromNavigator: fromNavigator)
        pointer = point
    }
    func updateDrag(to point: CGPoint, geometry: SpatialWorkspaceGeometry) {
        guard var drag else { return }
        pointer = point
        if !isDragging {
            guard hypot(point.x - drag.start.x, point.y - drag.start.y) > 5 else { return }
            isDragging = true
            if !drag.fromNavigator { layout.remove(drag.tile) }
        }
        if let previewTarget, let gap = geometry.tiles[drag.tile],
           gap.insetBy(dx: -8, dy: 0).contains(point) {
            self.drag = drag; self.previewTarget = previewTarget; return
        }
        previewTarget = geometry.dropTarget(at: point, dragging: drag.tile, fromNavigator: drag.fromNavigator)
        if let previewTarget { drag.lastTarget = previewTarget }
        self.drag = drag
    }
    func endDrag() {
        guard let drag else { return }
        guard isDragging else { self.drag = nil; return }
        if let target = previewTarget ?? drag.lastTarget {
            layout.move(drag.tile, to: target, swapSingleColumns: drag.fromNavigator)
        } else if !drag.fromNavigator { layout = drag.origin }
        else if let id = drag.tile.documentID { layout.openDocument(id) }
        self.drag = nil; isDragging = false; previewTarget = nil
        commit()
        if let id = drag.tile.documentID { onActivate?(id) }
    }
    func cancelDrag() {
        if let drag, isDragging { layout = drag.origin }
        drag = nil; isDragging = false; previewTarget = nil
    }
    func commit() { persist(); onCommit?(layout) }
    private var preferenceKey: String { "mint.spatial-workspace.\(projectID?.rawValue.uuidString ?? "none")" }
    private func persist() {
        guard projectID != nil, !loading, !isDragging else { return }
        if let data = try? JSONEncoder().encode(Preference(layout: layout, typewriter: typewriter, focusDimming: focusDimming)) {
            defaults.set(data, forKey: preferenceKey)
        }
    }
}
