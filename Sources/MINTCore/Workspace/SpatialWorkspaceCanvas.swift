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
        scroll.canvas.setAccessibilityElement(true)
        scroll.canvas.setAccessibilityRole(.group)
        scroll.canvas.setAccessibilityLabel("문서와 도구 타일 작업 공간")
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
    private var lastLayout: SpatialWorkspaceLayout?
    private var newTiles: Set<WorkspaceTileID> = []
    private var targetFrames: [WorkspaceTileID: CGRect] = [:]
    private struct FrameTransition {
        let view: NSView
        let origin: CGRect
        let target: CGRect
        let began: Double
        let duration: Double
        let remove: Bool
    }
    private var frameTransitions: [ObjectIdentifier: FrameTransition] = [:]
    private var frameTimer: Timer?
    private var dragMonitor: Any?
    private var dragTracking = false
    private var draggingCursor = false
    private var wakeMonitor: Any?
    private var dragPill: NSPanel?
    private let pointerSpring = WorkspacePointerSpring()
    private final class DropPreviewView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    private let dropPreviewView: NSView = {
        let view = DropPreviewView(frame: .zero)
        view.wantsLayer = true
        view.layer?.cornerRadius = 13
        view.layer?.borderWidth = 2
        view.isHidden = true
        return view
    }()
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
            stopFrameTransitions()
            resize = nil
            for host in hosts.values { host.removeFromSuperview() }
            hosts.removeAll(); projectID = model.projectID; lastLayout = nil; targetFrames.removeAll()
            stopDragPresentation()
        }
        let updateExisting = lastTheme != theme
        lastTheme = theme
        let nextLayout = model.layout
        animateLayout = lastLayout != nil && lastLayout != nextLayout && resize == nil && !model.isDragging
        lastLayout = nextLayout
        var retained = Set(model.layout.tiles)
        if let dragged = model.draggedTile { retained.insert(dragged) }
        for key in Array(hosts.keys) where !retained.contains(key) {
            guard let host = hosts.removeValue(forKey: key) else { continue }
            targetFrames.removeValue(forKey: key)
            if animateLayout && !reduceMotion {
                var target = host.frame
                let sharesColumn = hosts.values.contains { abs($0.frame.minX - host.frame.minX) < 1 }
                if sharesColumn { target.size.height = 0 } else { target.size.width = 0 }
                transition(host, to: target, duration: 0.27, remove: true)
            } else { host.removeFromSuperview() }
        }
        for tile in retained {
            let host: NSHostingView<AnyView>
            if let existing = hosts[tile] {
                host = existing
                if updateExisting { host.rootView = content(tile) }
            } else {
                host = NSHostingView(rootView: content(tile))
                host.sizingOptions = []
                host.wantsLayer = true; host.layer?.masksToBounds = true; host.layer?.cornerRadius = 13
                host.setAccessibilityIdentifier("mint.tile.\(tile.id)")
                hosts[tile] = host; addSubview(host)
                newTiles.insert(tile)
            }
            host.isHidden = false
            host.alphaValue = (model.isDragging && !model.dragFromNavigator && model.draggedTile == tile) ? 0.38 : 1.0
        }
        if dropPreviewView.superview == nil {
            addSubview(dropPreviewView)
        }
        if !model.isDragging {
            layoutTiles()
        } else {
            updateDragVisuals(previewTarget: model.previewTarget)
        }
    }

    func layoutTiles() {
        guard let model, viewport.width > 0, viewport.height > 0 else { return }
        // Keep native editor sizes stable until the drop commits the new layout.
        guard !model.isDragging else {
            updateDragVisuals(previewTarget: model.previewTarget)
            return
        }
        geometry = SpatialWorkspaceGeometry(layout: model.layout, viewport: viewport)
        setFrameSize(geometry.contentSize)
        for (tile, host) in hosts {
            guard let rect = geometry.tiles[tile], !host.isHidden else { continue }
            guard targetFrames[tile] != rect || newTiles.contains(tile) else { continue }
            targetFrames[tile] = rect
            if animateLayout && !reduceMotion {
                if newTiles.contains(tile) {
                    var start = rect
                    if model.layout.columns.contains(where: { $0.slots.count == 1 && $0.slots.first?.tile == tile }) { start.size.width = 0 }
                    else { start.size.height = 0 }
                    host.frame = start
                }
                transition(host, to: rect, duration: 0.26)
            } else {
                frameTransitions.removeValue(forKey: ObjectIdentifier(host)); host.frame = rect
            }
        }
        newTiles.removeAll()
        animateLayout = false
        updateResizeHandles()
        needsDisplay = true
    }

    private func transition(_ view: NSView, to target: CGRect, duration: Double, remove: Bool = false) {
        frameTransitions[ObjectIdentifier(view)] = .init(view: view, origin: view.frame, target: target,
            began: ProcessInfo.processInfo.systemUptime, duration: duration, remove: remove)
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFrames() }
        }
        frameTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func stepFrames() {
        let now = ProcessInfo.processInfo.systemUptime
        for (key, value) in frameTransitions {
            let progress = min(1, (now - value.began) / value.duration)
            let t = WorkspaceHTMLStyle.progress(progress)
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            value.view.frame = CGRect(x: mix(value.origin.minX, value.target.minX), y: mix(value.origin.minY, value.target.minY),
                width: mix(value.origin.width, value.target.width), height: mix(value.origin.height, value.target.height))
            if progress >= 1 {
                if value.remove { value.view.removeFromSuperview() }
                frameTransitions.removeValue(forKey: key)
            }
        }
        updateResizeHandles()
        if frameTransitions.isEmpty { frameTimer?.invalidate(); frameTimer = nil }
    }
    private func stopFrameTransitions() {
        frameTimer?.invalidate(); frameTimer = nil
        for value in frameTransitions.values {
            if value.remove { value.view.removeFromSuperview() } else { value.view.frame = value.target }
        }
        frameTransitions.removeAll()
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
        for (column, targetRect) in geometry.columns.enumerated() {
            let slot = model.layout.columns.indices.contains(column) ? model.layout.columns[column].slots.first?.tile : nil
            let rect = slot.flatMap { hosts[$0]?.frame } ?? targetRect
            if column < geometry.columns.count - 1 {
                place("mint.tile.column-resize.\(column)", axis: .column(column),
                    frame: CGRect(x: rect.maxX + 1, y: targetRect.minY, width: 6, height: targetRect.height))
            }
            guard model.layout.columns.indices.contains(column) else { continue }
            let slots = model.layout.columns[column].slots
            for row in 0..<max(0, slots.count - 1) {
                if let tile = hosts[slots[row].tile]?.frame ?? geometry.tiles[slots[row].tile] {
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
        model.cancelDrag()
        stopDragPresentation()
        // Finish any earlier open/close animation before freezing the drag geometry.
        stopFrameTransitions()
        animateLayout = false
        layoutTiles()
        dragTracking = true
        if let id = tile.documentID { model.onActivate?(id) }
        model.beginDrag(tile, at: canvasPoint(for: event), fromNavigator: fromNavigator)
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self, self.dragTracking else { return event }
            switch event.type {
            case .leftMouseDragged:
                self.continuePanelDrag(event); return nil
            case .leftMouseUp:
                let moved = self.model?.isDragging == true
                self.finishPanelDrag(event)
                return moved ? nil : event
            case .keyDown where event.keyCode == 53:
                self.cancelInteraction(); return nil
            default: return event
            }
        }
    }

    func continuePanelDrag(_ event: NSEvent) {
        guard dragTracking, let model else { return }
        if event.window === window { autoscroll(with: event) }
        let wasDragging = model.isDragging
        let pointer = screenPoint(for: event)
        var presented = geometry
        for (tile, host) in hosts where !host.isHidden { presented.tiles[tile] = host.frame }
        model.updateDrag(to: canvasPoint(for: event), geometry: presented)
        if !wasDragging, model.isDragging {
            NSCursor.closedHand.push(); draggingCursor = true
            showDragPill(model.draggedTile, at: pointer)
            if !model.dragFromNavigator, let dragged = model.draggedTile {
                hosts[dragged]?.alphaValue = 0.38
            }
        }
        if model.isDragging {
            updateNavigatorDrop(event)
            positionDragPill(event)
            updateDragVisuals(previewTarget: model.previewTarget)
        }
    }

    private func updateDragVisuals(previewTarget: SpatialDropTarget?) {
        guard let target = previewTarget, let rect = previewFrame(for: target) else {
            dropPreviewView.isHidden = true
            return
        }
        if dropPreviewView.superview == nil { addSubview(dropPreviewView) }
        else { addSubview(dropPreviewView, positioned: .above, relativeTo: nil) }
        dropPreviewView.layer?.backgroundColor = theme.blue.withAlphaComponent(0.10).cgColor
        dropPreviewView.layer?.borderColor = theme.blue.withAlphaComponent(0.55).cgColor
        dropPreviewView.frame = rect
        dropPreviewView.isHidden = false
    }

    private func previewFrame(for target: SpatialDropTarget) -> CGRect? {
        let inset = SpatialWorkspaceGeometry.inset
        let height = max(0, geometry.contentSize.height - inset * 2)
        switch target {
        case .start:
            return CGRect(x: inset, y: inset, width: 6, height: height)
        case .end:
            return CGRect(x: max(inset, geometry.contentSize.width - inset - 6), y: inset, width: 6, height: height)
        case .before(let tile):
            guard let rect = hosts[tile]?.frame ?? geometry.tiles[tile] else { return nil }
            return CGRect(x: rect.minX, y: rect.minY, width: max(48, rect.width * 0.25), height: rect.height)
        case .after(let tile):
            guard let rect = hosts[tile]?.frame ?? geometry.tiles[tile] else { return nil }
            let width = max(48, rect.width * 0.25)
            return CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height)
        case .above(let tile):
            guard let rect = hosts[tile]?.frame ?? geometry.tiles[tile] else { return nil }
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(36, rect.height * 0.28))
        case .below(let tile):
            guard let rect = hosts[tile]?.frame ?? geometry.tiles[tile] else { return nil }
            let band = max(36, rect.height * 0.28)
            return CGRect(x: rect.minX, y: rect.maxY - band, width: rect.width, height: band)
        }
    }

    private func updateNavigatorDrop(_ event: NSEvent) {
        guard let model, model.dragFromNavigator, let source = model.draggedTile?.documentID,
              let navigator = hosts[.navigator] else { model?.previewNavigator(nil); return }
        func rows(_ view: NSView) -> [SpatialNavigatorDragView] {
            (view as? SpatialNavigatorDragView).map { [$0] } ?? view.subviews.flatMap(rows)
        }
        for row in rows(navigator) where row.documentID != source {
            let point = row.convert(canvasPoint(for: event), from: self)
            if row.bounds.contains(point) {
                model.previewNavigator(.init(source: source, target: row.documentID, after: point.y > row.bounds.midY)); return
            }
        }
        model.previewNavigator(nil)
    }

    func finishPanelDrag(_ event: NSEvent) {
        guard dragTracking, let model else { return }
        if model.isDragging { continuePanelDrag(event) }
        model.endDrag()
        stopDragPresentation()
        for host in hosts.values {
            host.isHidden = false
            host.alphaValue = 1.0
        }
        animateLayout = true
        layoutTiles()
    }

    func cancelInteraction() {
        if let resize { model?.setLayout(resize.origin, persist: false); self.resize = nil }
        model?.cancelDrag()
        stopDragPresentation()
        for host in hosts.values {
            host.isHidden = false
            host.alphaValue = 1.0
        }
        animateLayout = true
        layoutTiles()
    }

    private func showDragPill(_ tile: WorkspaceTileID?, at pointer: CGPoint) {
        guard let tile else { return }
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.level = .floating
        panel.isReleasedWhenClosed = false
        func header(_ view: NSView) -> SpatialTileHeaderView? {
            (view as? SpatialTileHeaderView) ?? view.subviews.compactMap(header).first
        }
        let title = hosts[tile].flatMap(header)?.title.stringValue ?? "원고"
        let symbol: String = switch tile {
        case .navigator: "folder"; case .characters: "person.2"; case .narrative: "arrow.triangle.branch"; case .margin: "sparkles"; default: "doc.text"
        }
        let label = NSTextField(labelWithString: title)
        label.font = MintFonts.ui(11, weight: .medium); label.textColor = theme.ink
        label.lineBreakMode = .byTruncatingTail
        let labelWidth = min(160, label.fittingSize.width)
        panel.setContentSize(.init(width: labelWidth + 47, height: 36))
        let surface = NSVisualEffectView(frame: panel.contentView!.bounds); surface.wantsLayer = true
        surface.material = .popover; surface.blendingMode = .behindWindow; surface.state = .active
        surface.layer?.cornerRadius = 10; surface.layer?.masksToBounds = true; surface.layer?.backgroundColor = theme.pill.cgColor
        let icon = NSImageView(frame: .init(x: 13, y: 11, width: 14, height: 14))
        icon.image = WorkspaceIcons.image(symbol); icon.contentTintColor = theme.novel
        label.frame = CGRect(x: 34, y: 9, width: labelWidth, height: 18)
        surface.addSubview(icon); surface.addSubview(label)
        panel.contentView = surface; dragPill = panel; panel.alphaValue = reduceMotion ? 0.96 : 0
        panel.setFrameOrigin(.init(x: pointer.x + 12, y: pointer.y - 18))
        panel.orderFrontRegardless()
        if !reduceMotion {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.65; grow.toValue = 1; grow.duration = 0.22; grow.timingFunction = WorkspaceHTMLStyle.calm
            surface.layer?.add(grow, forKey: "pill.grow")
            WorkspaceHTMLStyle.animate(0.18) { panel.animator().alphaValue = 0.96 }
        }
    }

    private func positionDragPill(_ event: NSEvent) {
        let screen = screenPoint(for: event)
        if let dragPill { pointerSpring.move(dragPill, to: CGPoint(x: screen.x + 12, y: screen.y - 18), reducedMotion: reduceMotion) }
    }

    private func stopDragPresentation() {
        dragTracking = false
        if draggingCursor { NSCursor.pop(); draggingCursor = false }
        pointerSpring.stop()
        for host in hosts.values { host.alphaValue = 1 }
        dropPreviewView.isHidden = true
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor); self.dragMonitor = nil }
        dragPill?.orderOut(nil); dragPill?.close(); dragPill = nil
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    private func canvasPoint(for event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        return convert(window.convertPoint(fromScreen: screenPoint(for: event)), from: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFrameTransitions()
            model?.cancelDrag(); stopDragPresentation()
            if let wakeMonitor { NSEvent.removeMonitor(wakeMonitor); self.wakeMonitor = nil }
        } else if wakeMonitor == nil {
            window?.acceptsMouseMovedEvents = true
            wakeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                if let self, event.window === self.window {
                    self.model?.notePointer(at: self.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow)
                }
                return event
            }
        }
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
    @State private var hoveringStats = false
    @State private var statsRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            SpatialTileHeader(tile: .document(documentID), title: document?.title ?? "원고", theme: theme,
                active: active, actions: headerActions).frame(height: 32).opacity(model.whisperTyping ? 0.08 : 1)
            EditorPane(projectSession: session, editorRequests: requests, completion: completion,
                settings: completion.settings, theme: theme, editorBridge: editorBridge,
                positionStore: positionStore, documentID: documentID, showsChrome: false)
            HStack(spacing: 6) {
                if hoveringStats {
                    Text("Enter 새 문단 · 드래그하여 텍스트 다듬기/발췌 · ⋮⋮ 문단 이동").mintUIFont(9).lineLimit(1)
                }
                Spacer(minLength: 8)
                if hoveringStats { Text(statistics.detail).font(MintFonts.monoUI(9)).fixedSize() }
                Circle().stroke(theme.sepC, lineWidth: 1.5).overlay {
                    Circle().trim(from: 0, to: statistics.progress).stroke(theme.blueC, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: 11, height: 11).accessibilityLabel("집필 목표 \(Int(statistics.progress * 100))퍼센트")
                Text("\(statistics.characters.formatted())자").font(MintFonts.monoUI(10)).fixedSize()
            }.foregroundStyle(theme.workspaceMutedC).padding(.horizontal, 14).frame(height: 26).opacity(model.whisperTyping ? 0.08 : (hoveringStats ? 1 : 0.65))
                .onHover { hoveringStats = $0 }.help(statistics.detail)
                .animation(WorkspaceHTMLStyle.animation(0.24), value: hoveringStats)
        }
        .background(WorkspacePaperSurface(theme: theme, surface: active ? theme.editorSurface : theme.cardSurface))
        .animation(WorkspaceHTMLStyle.animation(0.32), value: model.whisperTyping)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mint.document-tile.\(documentID.rawValue.uuidString)")
        .task { await Task.yield(); statsRevision += 1 }
    }
    private var document: WritingDocument? { session.document(documentID) }
    private var active: Bool { session.selectedDocumentID == documentID }
    private var statistics: WorkspaceWritingStatistics {
        _ = statsRevision
        let key = session.activeProject.map { ProjectDocumentKey(projectID: $0.id, documentID: documentID) }
        let text = key.flatMap { requests.editor(for: $0)?.string } ?? document?.body ?? ""
        return WorkspaceWritingStatistics(text: text, goal: session.presentationPreferences.integer(forKey: "mint.writing-goal.\(documentID.rawValue.uuidString)"))
    }
    private var headerActions: [SpatialHeaderAction] {
        var actions = [
            SpatialHeaderAction(id: "mint.tile.typewriter.\(documentID.rawValue.uuidString)", label: "타자기",
                symbol: "", title: "타자기", selected: model.typewriter) { model.typewriter.toggle(); model.showToast(model.typewriter ? "타자기 스크롤 켜짐 — 현재 문단을 눈높이 중앙에 유지합니다" : "타자기 스크롤 꺼짐"); requests.focusEditor() },
            SpatialHeaderAction(id: "mint.tile.focus.\(documentID.rawValue.uuidString)", label: "문단 집중",
                symbol: "", title: "집중", selected: model.focusDimming) { model.focusDimming.toggle(); requests.focusEditor() },
            SpatialHeaderAction(id: "mint.tile.continue.\(documentID.rawValue.uuidString)", label: "이어쓰기 — 로컬 AI",
                symbol: "sparkles", title: "이어쓰기", enabled: completion.engineState == .ready && completion.settings.authorization == .enabled && completion.settings.autocompleteEnabled) {
                    guard let project = session.activeProject, let editor = requests.editor(for: .init(projectID: project.id, documentID: documentID)) else { return }
                    editor.window?.makeFirstResponder(editor)
                    (editor.delegate as? MintBlockEditor.Coordinator)?.requestExplicitCompletion(editor)
                }
        ]
        if !model.layout.openDocuments.isEmpty {
            actions.append(SpatialHeaderAction(id: "mint.tile.close.\(documentID.rawValue.uuidString)",
                label: "이 문서 창 닫기", symbol: "xmark") { _ = model.close(.document(documentID)); requests.focusEditor() })
        }
        return actions
    }
}
