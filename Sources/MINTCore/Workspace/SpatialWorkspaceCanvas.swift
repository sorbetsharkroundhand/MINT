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
        model.canvas = view.canvas
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
    private var geometryLayout: SpatialWorkspaceLayout?
    private var geometryViewport = CGSize.zero
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
    private var dragSequence: UInt64 = 0
    private var grabbedTile: WorkspaceTileID?
    private var grabStart = CGPoint.zero
    private var wakeMonitor: Any?
    private var scrollObserver: NSObjectProtocol?
    private var revealedSequence = 0
    private var dragPill: NSPanel?
    private let pointerSpring = WorkspacePointerSpring()
    private var transitions: [(panel: NSPanel, host: NSView?)] = []
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
            geometryLayout = nil
            stopDragPresentation()
        }
        let updateExisting = lastTheme != theme
        lastTheme = theme
        let nextLayout = model.presentationLayout
        animateLayout = lastLayout != nil && lastLayout != nextLayout && resize == nil
        lastLayout = nextLayout
        var retained = Set(model.layout.tiles)
        if let dragged = model.draggedTile { retained.insert(dragged) }
        for key in Array(hosts.keys) where !retained.contains(key) {
            guard let host = hosts.removeValue(forKey: key) else { continue }
            targetFrames.removeValue(forKey: key)
            frameTransitions.removeValue(forKey: ObjectIdentifier(host))
            host.removeFromSuperview()
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
                host.wantsLayer = true; host.layer?.masksToBounds = true; host.layer?.cornerRadius = 13
                host.setAccessibilityIdentifier("mint.tile.\(tile.id)")
                hosts[tile] = host; addSubview(host)
                newTiles.insert(tile)
            }
            host.isHidden = model.isDragging && !model.dragFromNavigator && model.draggedTile == tile
        }
        layoutTiles()
    }

    func layoutTiles() {
        guard let model, viewport.width > 0, viewport.height > 0 else { return }
        let presentation = model.presentationLayout
        if geometryLayout != presentation || geometryViewport != viewport {
            geometry = SpatialWorkspaceGeometry(layout: presentation, viewport: viewport)
            geometryLayout = presentation; geometryViewport = viewport
            updateContentSize()
        }
        for (tile, host) in hosts {
            guard let rect = geometry.tiles[tile], !host.isHidden else { continue }
            guard targetFrames[tile] != rect || newTiles.contains(tile) else { continue }
            targetFrames[tile] = rect
            if animateLayout && !reduceMotion {
                if newTiles.contains(tile) {
                    host.frame = rect
                    host.alphaValue = 0
                    WorkspaceHTMLStyle.animate(0.12) { host.animator().alphaValue = 1 }
                }
                transition(host, to: rect, duration: 0.12)
            } else {
                frameTransitions.removeValue(forKey: ObjectIdentifier(host)); host.frame = rect
            }
        }
        newTiles.removeAll()
        animateLayout = false
        if revealedSequence != model.revealSequence, let tile = model.tileToReveal, let rect = geometry.tiles[tile] {
            revealedSequence = model.revealSequence
            _ = scrollToVisible(rect.insetBy(dx: -8, dy: -8))
        }
        updateContentSize()
        updateResizeHandles()
        needsDisplay = true
        model.pouchGeometryDidChange?()
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
        updateContentSize()
        model?.pouchGeometryDidChange?()
        if frameTransitions.isEmpty { frameTimer?.invalidate(); frameTimer = nil }
    }
    private func updateContentSize() {
        // Only actual objects participate in the scroll extent, never overlays.
        let bottom = hosts.values.filter { !$0.isHidden }.map { $0.frame.maxY + SpatialWorkspaceGeometry.bottomInset }.max() ?? 0
        let size = CGSize(width: geometry.contentSize.width, height: max(geometry.contentSize.height, bottom))
        if frame.size != size { setFrameSize(size) }
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
        // Resize controls are not interactive during a tile drag.
        if model.isDragging {
            for handle in handles.values { handle.isHidden = true }
            return
        }
        let presentation = model.presentationLayout
        var required: Set<String> = []
        func place(_ identifier: String, axis: SpatialResizeAxis, frame: CGRect) {
            required.insert(identifier)
            let handle = handles[identifier] ?? SpatialResizeHandle()
            if handle.superview == nil { handles[identifier] = handle; addSubview(handle) }
            handle.canvas = self; handle.axis = axis; handle.theme = theme
            handle.isHidden = false
            handle.frame = frame; handle.toolTip = "드래그하여 크기 조절 · 행 경계 더블클릭: 50:50"
            handle.setAccessibilityIdentifier(identifier); handle.setAccessibilityRole(.splitter)
            handle.setAccessibilityLabel("창 크기 조절")
        }
        for (column, targetRect) in geometry.columns.enumerated() {
            let slot = presentation.columns.indices.contains(column) ? presentation.columns[column].slots.first?.tile : nil
            let rect = slot.flatMap { hosts[$0]?.frame } ?? targetRect
            if column < geometry.columns.count - 1 {
                place("mint.tile.column-resize.\(column)", axis: .column(column),
                    frame: CGRect(x: rect.maxX + 1, y: targetRect.minY, width: 6, height: targetRect.height))
            }
            guard presentation.columns.indices.contains(column) else { continue }
            let slots = presentation.columns[column].slots
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
        stopFrameTransitions()
        animateLayout = false; layoutTiles()
        dragSequence &+= 1
        grabbedTile = tile; grabStart = screenPoint(for: event); dragTracking = true
        if let id = tile.documentID { model.onActivate?(id) }
        model.beginDrag(tile, at: canvasPoint(for: event), fromNavigator: fromNavigator)
        // The source header disappears during detachment. Continue tracking at the app
        // boundary, like the HTML's document mousemove/mouseup handlers.
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self, self.dragTracking else { return event }
            switch event.type {
            case .leftMouseDragged:
                self.continuePanelDrag(event); return nil
            case .leftMouseUp:
                let moved = self.model?.isDragging == true
                self.finishPanelDrag(event)
                // Let a navigator row finish its ordinary click when no drag began.
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
        let wasDragging = model.isDragging, previous = model.previewTarget
        let pointer = screenPoint(for: event)
        let beginning = !wasDragging && hypot(pointer.x - grabStart.x, pointer.y - grabStart.y) > 5
        // Capture the retained native view before publishing a detached layout.
        let sourceHost = grabbedTile.flatMap { hosts[$0] }
        let sourceFrame = beginning ? sourceHost.map { screenFrame(of: $0) } : nil
        let sourceImage = beginning && !model.dragFromNavigator && !reduceMotion ? sourceHost.flatMap { snapshot($0) } : nil
        var presented = geometry
        for (tile, host) in hosts where !host.isHidden { presented.tiles[tile] = host.frame }
        model.updateDrag(to: canvasPoint(for: event), geometry: presented)
        if !wasDragging, model.isDragging {
            NSCursor.closedHand.push(); draggingCursor = true
            showDragPill(model.draggedTile, at: pointer); positionDragPill(event)
            if !model.dragFromNavigator, let host = sourceHost, let origin = sourceFrame {
                frameTransitions.removeValue(forKey: ObjectIdentifier(host))
                let width = origin.width * min(0.35, max(0.08, 96 / origin.width))
                let height = origin.height * min(0.28, max(0.06, 36 / origin.height))
                let destination = CGRect(x: pointer.x + 45 - width / 2, y: pointer.y - height / 2, width: width, height: height)
                animateTile(host, from: origin, to: destination, duration: 0.12, hidingHost: false, image: sourceImage)
            }
        }
        if model.isDragging {
            if !model.dragFromNavigator { hosts[model.draggedTile!]?.isHidden = true }
            updateNavigatorDrop(event)
            if previous != model.previewTarget || !wasDragging {
                animateLayout = true
                layoutTiles()
            }
            positionDragPill(event)
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
        let tile = model.draggedTile
        let origin = dragPill?.frame
        let sequence = dragSequence
        model.endDrag(); stopDragPresentation()
        if let tile { hosts[tile]?.isHidden = false }
        animateLayout = true; layoutTiles()
        if let tile, let origin {
            let project = projectID
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.projectID == project, self.dragSequence == sequence,
                      self.model?.isDragging != true, let host = self.hosts[tile],
                      let destination = self.geometry.tiles[tile] else { return }
                self.frameTransitions.removeValue(forKey: ObjectIdentifier(host))
                self.targetFrames[tile] = destination; host.frame = destination; host.isHidden = false
                host.layoutSubtreeIfNeeded()
                self.animateTile(host, from: origin, to: self.screenFrame(of: host), duration: 0.12, hidingHost: true)
            }
        }
    }
    func cancelInteraction() {
        dragSequence &+= 1
        if let resize { model?.setLayout(resize.origin, persist: false); self.resize = nil }
        model?.cancelDrag(); stopDragPresentation()
        for host in hosts.values { host.isHidden = false }
        animateLayout = true; layoutTiles()
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
        dragTracking = false; grabbedTile = nil
        if draggingCursor { NSCursor.pop(); draggingCursor = false }
        pointerSpring.stop()
        for transition in transitions { transition.host?.alphaValue = 1; transition.panel.orderOut(nil); transition.panel.close() }
        transitions.removeAll()
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor); self.dragMonitor = nil }
        dragPill?.orderOut(nil); dragPill?.close(); dragPill = nil
    }
    private func screenFrame(of host: NSView) -> CGRect {
        window?.convertToScreen(host.convert(host.bounds, to: nil)) ?? .zero
    }
    private func screenPoint(for event: NSEvent) -> CGPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    private func canvasPoint(for event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        return convert(window.convertPoint(fromScreen: screenPoint(for: event)), from: nil)
    }
    private func snapshot(_ host: NSView) -> NSImage? {
        guard host.bounds.width > 0, host.bounds.height > 0,
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
        return image
    }
    private func animateTile(_ host: NSView, from origin: CGRect, to target: CGRect, duration: Double, hidingHost: Bool, image captured: NSImage? = nil) {
        guard !reduceMotion, origin.width > 0, target.width > 0, let image = captured ?? snapshot(host) else { return }
        var from = origin
        if hidingHost {
            let width = target.width * min(0.45, max(0.08, origin.width / target.width))
            let height = target.height * min(0.35, max(0.06, origin.height / target.height))
            from = .init(x: origin.midX - width / 2, y: origin.midY - height / 2, width: width, height: height)
        }
        let ghost = NSPanel(contentRect: from, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ghost.isReleasedWhenClosed = false; ghost.ignoresMouseEvents = true; ghost.isOpaque = false
        ghost.backgroundColor = .clear; ghost.level = .floating
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: origin.size))
        imageView.image = image; imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true; imageView.layer?.masksToBounds = true
        imageView.layer?.cornerRadius = hidingHost ? 13 : 24
        let rounding = CABasicAnimation(keyPath: "cornerRadius")
        rounding.fromValue = hidingHost ? 22 : 13; rounding.toValue = hidingHost ? 13 : 24
        rounding.duration = duration; rounding.timingFunction = WorkspaceHTMLStyle.calm
        imageView.layer?.add(rounding, forKey: "tile.rounding")
        ghost.contentView = imageView
        transitions.append((ghost, hidingHost ? host : nil))
        if hidingHost { host.alphaValue = 0; ghost.alphaValue = 0.45 } else { ghost.alphaValue = 0.92 }
        ghost.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration; context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
            ghost.animator().setFrame(target, display: true); ghost.animator().alphaValue = hidingHost ? 1 : 0
        } completionHandler: { [weak self, weak host, weak ghost] in
            MainActor.assumeIsolated {
                host?.alphaValue = 1; ghost?.orderOut(nil); ghost?.close()
                self?.transitions.removeAll { $0.panel === ghost }
            }
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFrameTransitions()
            model?.cancelDrag(); stopDragPresentation()
            if let wakeMonitor { NSEvent.removeMonitor(wakeMonitor); self.wakeMonitor = nil }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver); self.scrollObserver = nil }
        } else if wakeMonitor == nil {
            window?.acceptsMouseMovedEvents = true
            wakeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                if let self, event.window === self.window {
                    self.model?.notePointer(at: self.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow)
                    if event.type == .leftMouseDown {
                        let point = self.convert(event.locationInWindow, from: nil)
                        if self.visibleRect.contains(point) {
                            var hit = self.hitTest(point)
                            while let view = hit, !(view is WorkspacePouchView) { hit = view.superview }
                            if hit == nil {
                                let tile = self.hosts.first { !$0.value.isHidden && $0.value.frame.contains(point) }?.key
                                self.model?.selectTile(tile)
                            }
                        }
                    }
                }
                return event
            }
            if let clip = enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                    object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model?.pouchGeometryDidChange?() }
                }
            }
        }
    }

    func pouchPlacement(for tile: WorkspaceTileID) -> WorkspacePouchPlacement? {
        guard let host = hosts[tile], !host.isHidden, host.frame.width >= 112, host.frame.height > 50 else { return nil }
        let height = model?.pouchSection?.preferredHeight(for: tile) ?? 0
        return WorkspacePouchPlacement(object: host.frame, visible: visibleRect, tile: tile, toolHeight: height)
    }
    func header(for tile: WorkspaceTileID) -> SpatialTileHeaderView? {
        func find(_ view: NSView) -> SpatialTileHeaderView? {
            if let header = view as? SpatialTileHeaderView { return header }
            for child in view.subviews { if let header = find(child) { return header } }
            return nil
        }
        return hosts[tile].flatMap(find)
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
            documentHeader
            EditorPane(projectSession: session, editorRequests: requests, completion: completion,
                settings: completion.settings, theme: theme, editorBridge: editorBridge,
                positionStore: positionStore, documentID: documentID, showsChrome: false)
            HStack(spacing: 6) {
                if hoveringStats {
                    Text("Enter 새 문단 · 주머니에서 서식·AI · ⋮⋮ 문단 이동").mintUIFont(9).lineLimit(1)
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
    private var documentHeader: some View {
        SpatialTileHeader(tile: .document(documentID), title: document?.title ?? "원고", theme: theme,
            active: active, actions: []).frame(height: 32)
    }

    private var document: WritingDocument? { session.document(documentID) }
    private var active: Bool { session.selectedDocumentID == documentID }
    private var statistics: WorkspaceWritingStatistics {
        _ = statsRevision
        let key = session.activeProject.map { ProjectDocumentKey(projectID: $0.id, documentID: documentID) }
        let text = key.flatMap { requests.editor(for: $0)?.string } ?? document?.body ?? ""
        return WorkspaceWritingStatistics(text: text, goal: session.presentationPreferences.integer(forKey: "mint.writing-goal.\(documentID.rawValue.uuidString)"))
    }
}
