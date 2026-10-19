import AppKit
import SwiftUI
import QuartzCore

struct SpatialWorkspaceCanvas: NSViewRepresentable {
    @ObservedObject var model: SpatialWorkspaceController
    let theme: MintTheme
    let content: (WorkspaceTileID) -> AnyView
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.mintWorkspaceAccessibilityOptions) private var accessibilityOptions

    func makeNSView(context: Context) -> SpatialCanvasScrollView {
        let scroll = SpatialCanvasScrollView()
        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.borderType = .noBorder; scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = scroll.canvas
        scroll.canvas.setAccessibilityIdentifier("mint.workspace.tiles")
        return scroll
    }
    func updateNSView(_ view: SpatialCanvasScrollView, context: Context) {
        view.canvas.model = model
        view.canvas.reduceMotion = systemReduceMotion || accessibilityOptions.reduceMotion
        view.canvas.theme = theme
        view.canvas.updateHosts(content: content)
        view.needsLayout = true
    }
}

final class SpatialCanvasScrollView: NSScrollView {
    let canvas = SpatialWorkspaceCanvasView()
    override func layout() {
        super.layout()
        canvas.viewport = contentView.bounds.size
        canvas.layoutTiles()
    }
}

/// Hosts stay siblings for their entire lifetime. Column/row changes only change their frames.
final class SpatialWorkspaceCanvasView: NSView {
    weak var model: SpatialWorkspaceController?
    var theme: MintTheme = .light
    var viewport = CGSize.zero
    var reduceMotion = false
    private var projectID: WritingProjectID?
    private var lastTheme: MintTheme?
    private var animateLayout = false
    private var dragMonitor: Any?
    private var dragPill: NSPanel?
    private var handles: [String: SpatialResizeHandle] = [:]
    private struct Resize {
        let origin: SpatialWorkspaceLayout
        let start: CGPoint
        let axis: SpatialResizeAxis
        let column: Int
        let startWidth: Double
        let direction: Double
        let height: Double
    }
    private var resize: Resize?
    private(set) var hosts: [WorkspaceTileID: NSHostingView<AnyView>] = [:]
    private(set) var geometry = SpatialWorkspaceGeometry(
        layout: SpatialWorkspaceLayout(documents: [], selected: nil), viewport: .zero)
    override var isFlipped: Bool { true }

    func updateHosts(content: (WorkspaceTileID) -> AnyView) {
        guard let model else { return }
        if projectID != model.projectID {
            for host in hosts.values { host.removeFromSuperview() }
            hosts.removeAll(); projectID = model.projectID
            stopDragPresentation()
        }
        let updateExisting = lastTheme != theme
        lastTheme = theme
        var retained = Set(model.layout.tiles)
        if let dragged = model.draggedTile { retained.insert(dragged) }
        for key in Array(hosts.keys) where !retained.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for tile in retained {
            let host: NSHostingView<AnyView>
            if let existing = hosts[tile] {
                host = existing
                if updateExisting { host.rootView = content(tile) }
            }
            else {
                host = NSHostingView(rootView: content(tile))
                host.sizingOptions = []
                host.setAccessibilityIdentifier("mint.tile.\(tile.id)")
                hosts[tile] = host; addSubview(host)
            }
            host.isHidden = model.isDragging && !model.dragFromNavigator && model.draggedTile == tile
        }
        layoutTiles()
    }

    func layoutTiles() {
        guard let model, viewport.width > 0, viewport.height > 0 else { return }
        geometry = SpatialWorkspaceGeometry(layout: model.presentationLayout, viewport: viewport)
        setFrameSize(geometry.contentSize)
        let changes = {
            for (tile, host) in self.hosts {
                if let rect = self.geometry.tiles[tile], !host.isHidden {
                    if self.animateLayout && !self.reduceMotion { host.animator().frame = rect }
                    else { host.frame = rect }
                }
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
            changes()
        }
        animateLayout = false
        updateResizeHandles()
        needsDisplay = true
    }

    private func updateResizeHandles() {
        guard let model else { return }
        var required: Set<String> = []
        func place(_ identifier: String, axis: SpatialResizeAxis, frame: CGRect) {
            required.insert(identifier)
            let handle = handles[identifier] ?? SpatialResizeHandle()
            if handle.superview == nil { handles[identifier] = handle; addSubview(handle) }
            handle.canvas = self; handle.axis = axis; handle.theme = theme
            handle.frame = frame; handle.toolTip = "드래그하여 크기 조절 · 행 경계 더블클릭: 50:50"
            handle.setAccessibilityIdentifier(identifier); handle.setAccessibilityRole(.splitter)
            handle.setAccessibilityLabel("창 크기 조절")
        }
        for (column, rect) in geometry.columns.enumerated() {
            if column < geometry.columns.count - 1 {
                place("mint.tile.column-resize.\(column)", axis: .column(column),
                    frame: CGRect(x: rect.maxX + 1, y: rect.minY, width: 6, height: rect.height))
            }
            guard model.presentationLayout.columns.indices.contains(column) else { continue }
            let slots = model.presentationLayout.columns[column].slots
            for row in 0..<max(0, slots.count - 1) {
                if let tile = geometry.tiles[slots[row].tile] {
                    place("mint.tile.row-resize.\(column).\(row)", axis: .row(column, row),
                        frame: CGRect(x: rect.minX, y: tile.maxY, width: rect.width, height: 6))
                }
            }
        }
        for identifier in Array(handles.keys) where !required.contains(identifier) {
            handles.removeValue(forKey: identifier)?.removeFromSuperview()
        }
    }

    func beginResize(_ axis: SpatialResizeAxis, event: NSEvent) {
        guard let model, !model.isDragging else { return }
        let origin = model.layout
        switch axis {
        case .column(let left):
            guard origin.columns.indices.contains(left + 1) else { return }
            let rightFixed = origin.columns[left].width == nil && origin.columns[left + 1].width != nil
            let target = rightFixed ? left + 1 : left
            resize = Resize(origin: origin, start: convert(event.locationInWindow, from: nil), axis: axis,
                column: target, startWidth: origin.columns[target].width ?? geometry.columns[target].width,
                direction: rightFixed ? -1 : 1, height: 0)
        case .row(let column, _):
            guard geometry.columns.indices.contains(column) else { return }
            resize = Resize(origin: origin, start: convert(event.locationInWindow, from: nil), axis: axis,
                column: column, startWidth: 0, direction: 1, height: geometry.columns[column].height)
        }
    }
    func continueResize(_ event: NSEvent) {
        guard let resize, let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        var value = resize.origin
        switch resize.axis {
        case .column:
            value.setColumnWidth(resize.column, width: resize.startWidth + (point.x - resize.start.x) * resize.direction)
        case .row(let column, let row):
            value.resizeRows(column: column, row: row, delta: point.y - resize.start.y, height: resize.height)
        }
        model.setLayout(value, persist: false); layoutTiles()
    }
    func finishResize() { guard resize != nil else { return }; resize = nil; model?.commit() }

    func beginPanelDrag(_ tile: WorkspaceTileID, event: NSEvent, fromNavigator: Bool = false) {
        guard let model, event.buttonNumber == 0 else { return }
        if let id = tile.documentID { model.onActivate?(id) }
        model.beginDrag(tile, at: convert(event.locationInWindow, from: nil), fromNavigator: fromNavigator)
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53, self?.model?.isDragging == true else { return event }
            self?.cancelInteraction(); return nil
        }
    }
    func continuePanelDrag(_ event: NSEvent) {
        guard let model else { return }
        let wasDragging = model.isDragging, previous = model.previewTarget
        model.updateDrag(to: convert(event.locationInWindow, from: nil), geometry: geometry)
        if !wasDragging, model.isDragging { showDragPill(model.draggedTile) }
        if model.isDragging {
            if !model.dragFromNavigator { hosts[model.draggedTile!]?.isHidden = true }
            updateNavigatorDrop(event)
            animateLayout = previous != model.previewTarget || !wasDragging
            layoutTiles(); positionDragPill(event)
        }
    }
    private func updateNavigatorDrop(_ event: NSEvent) {
        guard let model, model.dragFromNavigator, let source = model.draggedTile?.documentID,
              let navigator = hosts[.navigator] else { model?.previewNavigator(nil); return }
        func rows(_ view: NSView) -> [SpatialNavigatorDragView] {
            (view as? SpatialNavigatorDragView).map { [$0] } ?? view.subviews.flatMap(rows)
        }
        for row in rows(navigator) where row.documentID != source {
            let point = row.convert(event.locationInWindow, from: nil)
            if row.bounds.contains(point) {
                model.previewNavigator(.init(source: source, target: row.documentID, after: point.y > row.bounds.midY)); return
            }
        }
        model.previewNavigator(nil)
    }
    func finishPanelDrag(_ event: NSEvent) {
        guard let model else { return }
        let tile = model.draggedTile
        model.endDrag(); stopDragPresentation()
        if let tile { hosts[tile]?.isHidden = false }
        animateLayout = true; layoutTiles()
    }
    func cancelInteraction() {
        if let resize { model?.setLayout(resize.origin, persist: false); self.resize = nil }
        model?.cancelDrag(); stopDragPresentation()
        for host in hosts.values { host.isHidden = false }
        animateLayout = true; layoutTiles()
    }
    private func showDragPill(_ tile: WorkspaceTileID?) {
        guard let tile else { return }
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.level = .floating
        panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: hosts[tile]?.accessibilityLabel() ?? (tile.documentID == nil ? "도구" : "원고"))
        label.font = MintFonts.ui(11, weight: .medium); label.textColor = theme.ink
        label.lineBreakMode = .byTruncatingTail
        let surface = NSView(frame: panel.contentView!.bounds); surface.wantsLayer = true
        surface.layer?.cornerRadius = 10; surface.layer?.backgroundColor = theme.pill.cgColor
        label.frame = CGRect(x: 13, y: 9, width: 154, height: 18); surface.addSubview(label)
        panel.contentView = surface; dragPill = panel; panel.orderFrontRegardless()
    }
    private func positionDragPill(_ event: NSEvent) {
        guard let window else { return }
        let screen = window.convertPoint(toScreen: event.locationInWindow)
        dragPill?.setFrameOrigin(CGPoint(x: screen.x + 12, y: screen.y - 18))
    }
    private func stopDragPresentation() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor); self.dragMonitor = nil }
        dragPill?.orderOut(nil); dragPill?.close(); dragPill = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { model?.cancelDrag(); stopDragPresentation() }
    }
}

struct SpatialDocumentTile: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var requests: ProjectEditorRequests
    @ObservedObject var completion: CompletionController
    @ObservedObject var model: SpatialWorkspaceController
    let documentID: WritingDocumentID
    let theme: MintTheme
    var editorBridge: ProjectEditorBridge?
    let positionStore: WritingPositionStore

    var body: some View {
        VStack(spacing: 0) {
            SpatialTileHeader(tile: .document(documentID), title: document?.title ?? "원고", theme: theme,
                active: active, actions: headerActions).frame(height: 32)
            EditorPane(projectSession: session, editorRequests: requests, completion: completion,
                settings: completion.settings, theme: theme, editorBridge: editorBridge,
                positionStore: positionStore, documentID: documentID, showsChrome: false)
            HStack(spacing: 6) {
                Spacer()
                Text("\(characters.formatted())자").font(MintFonts.monoUI(10))
            }.foregroundStyle(theme.ink3C).padding(.horizontal, 14).frame(height: 26)
        }
        .background(WorkspacePaperSurface(theme: theme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mint.document-tile.\(documentID.rawValue.uuidString)")
    }
    private var document: WritingDocument? { session.document(documentID) }
    private var active: Bool { session.selectedDocumentID == documentID }
    private var characters: Int { document?.body.count ?? 0 }
    private var headerActions: [SpatialHeaderAction] {
        var actions = [
            SpatialHeaderAction(id: "mint.tile.typewriter.\(documentID.rawValue.uuidString)", label: "타자기",
                symbol: "align.vertical.center", selected: model.typewriter) { model.typewriter.toggle(); requests.focusEditor() },
            SpatialHeaderAction(id: "mint.tile.focus.\(documentID.rawValue.uuidString)", label: "문단 집중",
                symbol: "eye", selected: model.focusDimming) { model.focusDimming.toggle(); requests.focusEditor() }
        ]
        if model.layout.openDocuments.count > 1 {
            actions.append(SpatialHeaderAction(id: "mint.tile.close.\(documentID.rawValue.uuidString)",
                label: "이 문서 창 닫기", symbol: "xmark") { _ = model.close(.document(documentID)); requests.focusEditor() })
        }
        return actions
    }
}
