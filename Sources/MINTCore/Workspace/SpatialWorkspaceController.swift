import AppKit
import Combine

struct SpatialNavigatorDrop: Equatable {
    let source: WritingDocumentID
    let target: WritingDocumentID
    let after: Bool
}

struct WorkspaceEntityEvent: Equatable {
    let name: String
    let note: String
    let reference: OriginalSourceReference
}

@MainActor final class SpatialWorkspaceController: ObservableObject {
    @Published private(set) var layout = SpatialWorkspaceLayout(documents: [], selected: nil)
    @Published private(set) var previewTarget: SpatialDropTarget?
    private(set) var pointer = CGPoint.zero
    @Published private(set) var isDragging = false
    @Published var typewriter = false { didSet { persist() } }
    @Published var focusDimming = false { didSet { persist() } }
    @Published var whisperTyping = false
    @Published var expandedItem: String?
    @Published private(set) var selectedTile: WorkspaceTileID?
    @Published var pouchSection: WorkspacePouchSection?
    @Published var searchRequest = WorkspaceSearchRequest()
    @Published private(set) var revealSequence = 0
    private(set) var tileToReveal: WorkspaceTileID?
    weak var canvas: SpatialWorkspaceCanvasView?
    var pouchGeometryDidChange: (() -> Void)?
    var advanceSearch: ((Int) -> Void)?
    private func reveal(_ tile: WorkspaceTileID) { tileToReveal = tile; revealSequence += 1 }

    func selectTile(_ tile: WorkspaceTileID?) {
        guard selectedTile != tile else { return }
        selectedTile = tile
        pouchSection = nil
    }
    func openSearch(scope: WorkspaceSearchScope = .project, query: String? = nil) {
        if !layout.contains(.search) { layout.toggle(.search); commit() }
        selectTile(.search)
        searchRequest = .init(sequence: searchRequest.sequence + 1, scope: scope,
            query: query, documentID: activeDocumentID)
        reveal(.search)
    }
    func openPouchTools() {
        if selectedTile == nil || selectedTile == .search {
            selectTile(activeDocumentID.map(WorkspaceTileID.document))
        }
        guard let selectedTile else { return }
        pouchSection = selectedTile.documentID == nil ? .object : .format
        reveal(selectedTile)
    }
    @Published var navigatorDrop: SpatialNavigatorDrop?
    @Published var resonatingTerm: String?
    @Published var activeParagraph = ""
    var entityTerms: [String] = []
    @Published var entityEvents: [WorkspaceEntityEvent] = []
    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    func showToast(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
    private(set) var activeDocumentID: WritingDocumentID?
    private(set) var restoredPreference = false
    private var whisperOrigin = CGPoint.zero
    func noteTyping(at point: CGPoint) { whisperOrigin = point; whisperTyping = true }
    func notePointer(at point: CGPoint) {
        if whisperTyping && hypot(point.x - whisperOrigin.x, point.y - whisperOrigin.y) > 8 { whisperTyping = false }
    }
    var onCommit: ((SpatialWorkspaceLayout) -> Void)?
    var onActivate: ((WritingDocumentID) -> Void)?
    var onNavigationOrder: (([WritingDocumentID]) -> Void)?
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
        let previewColumnID = UUID()
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
        preview.move(.insertionPreview, to: previewTarget)
        if let index = preview.columns.firstIndex(where: {
            $0.slots.count == 1 && $0.slots[0].tile == .insertionPreview
        }) {
            // Stable identity keeps repeated reads from looking like layout changes.
            preview.columns[index].id = drag.previewColumnID
            if drag.tile.documentID == nil { preview.columns[index].width = 204 }
        }
        return preview
    }

    func configure(project: WritingProject, selected: WritingDocumentID?, defaults: UserDefaults? = nil) {
        if let defaults { self.defaults = defaults }
        activeDocumentID = selected
        validDocuments = project.documents.filter { !project.trashedDocumentIDs.contains($0.id) }.map(\.id)
        if projectID != project.id {
            cancelDrag(); loading = true; projectID = project.id
            selectedTile = nil; pouchSection = nil; searchRequest = .init(); advanceSearch = nil
            if let data = self.defaults.data(forKey: preferenceKey),
               let saved = try? JSONDecoder().decode(Preference.self, from: data), saved.version == 1 {
                layout = saved.layout; typewriter = saved.typewriter; focusDimming = saved.focusDimming
                restoredPreference = true
            } else {
                restoredPreference = false
                layout = SpatialWorkspaceLayout(documents: validDocuments, selected: selected,
                    navigatorVisible: self.defaults.object(forKey: "mint.sidebarVisible") as? Bool ?? true)
                typewriter = false; focusDimming = false
            }
            whisperTyping = false; expandedItem = nil; toastTask?.cancel(); toast = nil
            entityEvents = []; loading = false
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
        layout.openDocument(id); commit(); reveal(.document(id)); onActivate?(id)
    }
    func openAll() { layout.openAll(validDocuments); commit(); showToast("\(validDocuments.count)개 파일을 나란히 펼쳤습니다") }
    func toggle(_ tile: WorkspaceTileID) {
        // Decode old layouts/commands, but never recreate the retired settings object.
        if tile == .inspector { openPouchTools(); return }
        cancelDrag(); layout.toggle(tile)
        if layout.contains(tile) { selectTile(tile); reveal(tile) }
        else if selectedTile == tile { selectTile(nil) }
        commit()
    }
    @discardableResult func close(_ tile: WorkspaceTileID) -> Bool {
        cancelDrag()
        guard layout.contains(tile) else { return false }
        guard layout.close(tile) else { showToast("최소 1개의 원고 창은 열려 있어야 합니다"); return false }
        if selectedTile == tile { selectTile(nil) }
        commit(); return true
    }
    func setLayout(_ value: SpatialWorkspaceLayout, persist: Bool = true) {
        layout = value
        if persist { commit() }
    }

    func beginDrag(_ tile: WorkspaceTileID, at point: CGPoint, fromNavigator: Bool = false) {
        cancelDrag()
        if let id = tile.documentID { guard validDocuments.contains(id), fromNavigator || layout.contains(tile) else { return } }
        else { guard layout.contains(tile) else { return } }
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
        // Keep the current destination while crossing the space it opened.
        if previewTarget != nil, let gap = geometry.tiles[.insertionPreview],
           gap.insetBy(dx: -8, dy: 0).contains(point) {
            return
        }
        let nextTarget = geometry.dropTarget(at: point, dragging: drag.tile, fromNavigator: drag.fromNavigator)
        if previewTarget != nextTarget {
            previewTarget = nextTarget
        }
        if let nextTarget { drag.lastTarget = nextTarget }
        self.drag = drag
    }
    func endDrag() {
        guard let drag else { return }
        guard isDragging else { self.drag = nil; return }
        if drag.fromNavigator, let navigatorDrop {
            var order = validDocuments.filter { $0 != navigatorDrop.source }
            if let target = order.firstIndex(of: navigatorDrop.target) {
                order.insert(navigatorDrop.source, at: target + (navigatorDrop.after ? 1 : 0))
                validDocuments = order; layout = drag.origin
                self.drag = nil; isDragging = false; previewTarget = nil; self.navigatorDrop = nil
                persist(); onNavigationOrder?(order); return
            }
        }
        if let target = previewTarget ?? drag.lastTarget {
            layout.move(drag.tile, to: target, swapSingleColumns: drag.fromNavigator)
        } else if !drag.fromNavigator { layout = drag.origin }
        else if let id = drag.tile.documentID { layout.openDocument(id) }
        self.drag = nil; isDragging = false; previewTarget = nil; navigatorDrop = nil
        commit()
        if let id = drag.tile.documentID { onActivate?(id) }
    }
    func cancelDrag() {
        if let drag, isDragging { layout = drag.origin }
        drag = nil; isDragging = false; previewTarget = nil; navigatorDrop = nil
    }
    func previewNavigator(_ drop: SpatialNavigatorDrop?) {
        if navigatorDrop != drop { navigatorDrop = drop }
        if drop != nil, previewTarget != nil { previewTarget = nil }
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
