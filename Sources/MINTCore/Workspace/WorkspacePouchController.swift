import AppKit
import Combine
import QuartzCore
import SwiftUI

struct WorkspacePouchAction {
    let id: String
    let label: String
    let symbol: String
    var selected: () -> Bool = { false }
    var enabled: () -> Bool = { true }
    let perform: () -> Void
}

/// A collapsed workspace is still an open workspace, even without a visible
/// document window. Its widget must outlive transient animation panels/views.
@MainActor public enum WorkspacePouchLifetime {
    private static var retained: [ObjectIdentifier: WorkspacePouchController] = [:]

    public static var hasCollapsedWorkspace: Bool { retained.values.contains { $0.isCollapsed } }

    static func controller(for window: NSWindow) -> WorkspacePouchController? {
        retained.values.first { $0.window === window }
    }

    @discardableResult public static func restoreCollapsedWorkspaces() -> Bool {
        let workspaces = retained.values.filter { $0.isCollapsed }
        for workspace in workspaces { workspace.restore() }
        return !workspaces.isEmpty
    }

    fileprivate static func retain(_ controller: WorkspacePouchController) {
        retained[ObjectIdentifier(controller)] = controller
    }

    fileprivate static func release(_ controller: WorkspacePouchController) {
        retained.removeValue(forKey: ObjectIdentifier(controller))
    }
}

@MainActor final class WorkspacePouchController: NSObject {
    private(set) var panel: NSPanel?
    private(set) var isCollapsed = false
    private(set) var isDragging = false
    var reduceMotion = false
    var reduceTransparency = false
    var theme: MintTheme = .light { didSet { refresh() } }
    var actions: [WorkspacePouchAction] = [] { didSet { refresh() } }
    var extraActions: [WorkspacePouchAction] = []
    var targetTitle = "MINT" { didSet { content?.targetTitle = targetTitle } }
    weak var requests: ProjectEditorRequests?
    fileprivate weak var window: NSWindow?
    private var collapsedWindow: NSWindow?
    private weak var workspaceView: NSView?
    private weak var previousResponder: NSResponder?
    private let model: SpatialWorkspaceController
    private let defaults: UserDefaults
    private var content: WorkspacePouchView?
    private weak var attachedHeader: SpatialTileHeaderView?
    private var escapeMonitor: Any?
    private var toolsWereExpanded = false
    private var observers: [NSObjectProtocol] = []
    private var subscription: AnyCancellable?
    private var start: CGPoint?
    private var grabOffset = CGPoint(x: 22, y: 22)
    private var dragMonitor: Any?
    private var draggingCursor = false
    private var edge: WorkspacePouchEdge = .left
    private var ratio = 0.45
    private var loadedKey: String?
    private var target = CGPoint.zero
    private var spring = WorkspaceSpringPoint(position: .zero)
    private var timer: Timer?
    private var lastStep = ProcessInfo.processInfo.systemUptime
    private var savedButtons: [(NSButton, AnyObject?, Selector?)] = []
    private(set) var transition: NSPanel?
    private var transitionGeneration: UInt64 = 0
    private var collapsedImage: NSImage?
    private var attachmentTile: WorkspaceTileID?
    private var isAttached: Bool { content?.superview === model.canvas && model.canvas != nil }
    private struct Preference: Codable { let edge: WorkspacePouchEdge; let ratio: Double }

    init(model: SpatialWorkspaceController, defaults: UserDefaults = .standard) {
        self.model = model; self.defaults = defaults
        super.init()
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.model.canvas?.layoutTiles()
                self?.refresh(); self?.syncAttachment()
            }
        }
        model.pouchGeometryDidChange = { [weak self] in self?.syncAttachment() }
        model.dismissObject = { [weak self] tile in self?.dismissObject(tile) }
    }

    func attach(to window: NSWindow, from workspaceView: NSView? = nil) {
        guard self.window !== window else {
            if let workspaceView { self.workspaceView = workspaceView }
            let changed = loadedKey != preferenceKey
            refresh(); if changed { dock(immediate: true) }; return
        }
        detach(); self.window = window; self.workspaceView = workspaceView
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "MINT 주머니"; panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = true
        panel.isExcludedFromWindowsMenu = true
        panel.isMovable = false; panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let content = WorkspacePouchView(); content.controller = self
        content.setAccessibilityIdentifier("mint.workspace.rail"); content.setAccessibilityLabel("주머니 도구창")
        panel.contentView = content; self.panel = panel; self.content = content
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type != .keyDown {
                if self.model.pouchSection != nil, let content = self.content,
                   !content.containsControl(at: content.convert(event.locationInWindow, from: nil)) { self.dismissTools() }
                return event
            }
            guard event.keyCode == 53,
                  self.window?.attachedSheet == nil, NSApp.modalWindow == nil,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  !self.isCollapsed, !self.isDragging, !self.model.isDragging else { return event }
            if let text = self.window?.firstResponder as? NSTextView, text.hasMarkedText() { return event }
            if let editor = self.window?.firstResponder as? BlockTextView, editor.ownsEscapeKey { return event }
            guard self.model.pouchSection != nil else { return event }
            if event.isARepeat { return nil }
            self.dismissTools()
            return nil
        }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
            if let button = window.standardWindowButton(kind) {
                savedButtons.append((button, button.target as AnyObject?, button.action))
                button.target = self; button.action = #selector(collapseFromButton)
            }
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dock(immediate: false) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.detach() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dock(immediate: true) }
        })
        refresh(); dock(immediate: true)
    }

    func detach() {
        stopDragTracking()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        attachedHeader?.overlayLeading = nil; attachedHeader = nil
        timer?.invalidate(); timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        for (button, owner, action) in savedButtons { button.target = owner; button.action = action }
        savedButtons.removeAll()
        cancelTransition(); collapsedImage = nil
        content?.removeFromSuperview(); attachmentTile = nil
        panel?.orderOut(nil); panel?.close(); panel = nil; content = nil; window = nil
        start = nil; isDragging = false; isCollapsed = false
        collapsedWindow = nil
        workspaceView = nil
        WorkspacePouchLifetime.release(self)
    }

    func detachFromWorkspaceView(_ view: NSView) {
        guard workspaceView === view else { return }
        workspaceView = nil
        // SwiftUI may detach the bridge while the document window is hidden.
        // Only an actual window close or an explicit detach disposes its widget.
        guard !isCollapsed else { return }
        detach()
    }

    func setTools(_ root: AnyView) { content?.setTools(root) }

    func beginDrag(at point: CGPoint) {
        stopDragTracking()
        start = point; isDragging = false
        if isCollapsed, let panel {
            grabOffset = CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        } else { grabOffset = CGPoint(x: 22, y: 22) }
        // Own the gesture before the rail's buttons are hidden or its parent window
        // is ordered out. Tracking must not depend on the original hit-test view.
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, self.start != nil else { return event }
            // The pouch moves between events. Sample desktop coordinates directly
            // instead of converting through the panel's newly moved origin.
            let point = NSEvent.mouseLocation
            if event.type == .leftMouseDragged {
                self.updateDrag(to: point)
                return nil
            }
            let moved = self.endDrag(at: point)
            // Preserve a stationary button click; consume a drag's mouse-up so the
            // newly exposed orb cannot immediately reopen the collapsed window.
            return moved ? nil : event
        }
    }
    func updateDrag(to point: CGPoint) {
        guard let start, let window else { return }
        if !isDragging {
            guard hypot(point.x - start.x, point.y - start.y) > 7 else { return }
            releaseContentToPanel()
            attachmentTile = nil; model.selectTile(nil)
            spring = WorkspaceSpringPoint(position: CGPoint(x: start.x - grabOffset.x, y: start.y - grabOffset.y))
            isDragging = true
            NSCursor.closedHand.push(); draggingCursor = true
            refresh()
        }
        let screen = screenFrame(for: point)
        target = WorkspacePouchGeometry.clampOrb(
            CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y), screen: screen, margin: 6)
        moveTowardTarget()
        let orb = CGRect(origin: target, size: CGSize(width: 44, height: 44))
        if !isCollapsed, !window.frame.insetBy(dx: -4, dy: -4).contains(orb) {
            collapse()
        }
    }
    @discardableResult func endDrag(at point: CGPoint) -> Bool {
        guard start != nil else { return false }
        if isDragging { updateDrag(to: point) }
        start = nil
        let moved = isDragging; isDragging = false
        content?.clearPressedState()
        stopDragTracking()
        guard moved, let window else { refresh(); return false }
        if isCollapsed {
            target = WorkspacePouchGeometry.clampOrb(target, screen: screenFrame(for: point))
            moveTowardTarget(); refresh(); return true
        }
        edge = WorkspacePouchGeometry.nearestEdge(point: point, window: window.frame)
        if edge == .left || edge == .right {
            ratio = min(0.95, max(0.05, (window.frame.maxY - point.y - 48) / max(100, window.frame.height - 96)))
        } else {
            ratio = min(0.95, max(0.05, (point.x - window.frame.minX - 48) / max(100, window.frame.width - 96)))
        }
        if let data = try? JSONEncoder().encode(Preference(edge: edge, ratio: ratio)) { defaults.set(data, forKey: preferenceKey) }
        refresh(); dock(immediate: false); return true
    }

    private func stopDragTracking() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor); self.dragMonitor = nil }
        if draggingCursor { NSCursor.pop(); draggingCursor = false }
    }

    @objc private func collapseFromButton() { collapse() }
    func collapse() {
        guard !isCollapsed, let window, let panel else { return }
        model.pouchSection = nil
        releaseContentToPanel(); attachmentTile = nil
        target = CGPoint(x: panel.frame.midX - 22, y: panel.frame.midY - 22)
        spring.position = target
        previousResponder = window.firstResponder
        // Hiding a retained window is a presentation change, not an editor commit.
        // Keep marked text and the native selection with the same first responder;
        // do not enqueue diagnostics/autosave by synthesizing didChangeText here.
        target = WorkspacePouchGeometry.clampOrb(target, screen: screenFrame(for: target))
        collapsedWindow = window
        isCollapsed = true
        WorkspacePouchLifetime.retain(self)
        cancelTransition()
        // Make the orb independent of application activation before hiding the window.
        refresh()
        panel.orderFrontRegardless()
        if !reduceMotion {
            animateSnapshot(of: window, toward: collapsedSnapshotFrame(window: window, orb: CGRect(origin: target, size: CGSize(width: 44, height: 44))))
        }
        window.orderOut(nil)
        panel.orderFrontRegardless(); moveTowardTarget()
    }
    func restore() {
        guard isCollapsed, let window else { return }
        let origin = panel?.frame ?? CGRect(origin: target, size: CGSize(width: 44, height: 44))
        stopDragTracking(); cancelTransition()
        isCollapsed = false; isDragging = false; start = nil
        if !reduceMotion { window.alphaValue = 0 }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let previousResponder { window.makeFirstResponder(previousResponder) }
        collapsedWindow = nil
        // Retain the controller until an actual detach/close. A recreated SwiftUI
        // bridge adopts it, including when restoration happens before that bridge.
        refresh(); dock(immediate: false)
        if !reduceMotion {
            animateSnapshot(of: window, toward: window.frame, expandingFrom: collapsedSnapshotFrame(window: window, orb: origin))
        } else { collapsedImage = nil }
    }

    func refresh() {
        guard let panel, let content else { return }
        // The pouch is an independent panel and does not inherit SwiftUI's
        // preferredColorScheme from the manuscript window.
        let appearanceName: NSAppearance.Name = theme.editorSurface.relativeLuminance < 0.5 ? .darkAqua : .aqua
        if panel.appearance?.name != appearanceName {
            panel.appearance = NSAppearance(named: appearanceName)
        }
        content.appearance = panel.appearance
        if loadedKey != preferenceKey {
            loadedKey = preferenceKey
            if let data = defaults.data(forKey: preferenceKey), let saved = try? JSONDecoder().decode(Preference.self, from: data), saved.ratio.isFinite {
                edge = saved.edge; ratio = min(0.95, max(0.05, saved.ratio))
            } else { edge = .left; ratio = 0.45 }
        }
        let attached = isAttached, flying = attachmentTile != nil && !attached
        content.toolsExpanded = attached && model.pouchSection != nil
        content.targetTitle = targetTitle
        content.configure(orb: isCollapsed || isDragging || flying,
            horizontal: edge == .top || edge == .bottom,
            actions: attached ? [] : actions, theme: theme, attached: attached)
        panel.hidesOnDeactivate = !isCollapsed && !isDragging
        panel.canHide = !isCollapsed && !isDragging
        let opacity: CGFloat = attached || flying ? 1 : (model.whisperTyping && !isCollapsed && !isDragging ? 0.06 : (isCollapsed || isDragging || content.hovered || reduceTransparency ? 1 : 0.84))
        if reduceMotion || isCollapsed || isDragging { panel.alphaValue = opacity }
        else if abs(panel.alphaValue - opacity) > 0.001 {
            WorkspaceHTMLStyle.animate(0.12) { panel.animator().alphaValue = opacity }
        }
        panel.ignoresMouseEvents = model.whisperTyping && !isCollapsed && !isDragging && !attached && !flying
        if attached { panel.orderOut(nil) }
        else if isCollapsed || isDragging || flying {
            panel.setFrame(CGRect(origin: spring.position, size: CGSize(width: 44, height: 44)), display: false)
        }
        else if let window { panel.setContentSize(WorkspacePouchGeometry.dockedFrame(window: window.frame, edge: edge, ratio: ratio).size) }
        content.needsLayout = true; content.needsDisplay = true
        if isCollapsed { panel.orderFrontRegardless() }
    }
    func toggleTools() {
        if model.pouchSection != nil { dismissTools(); return }
        model.openPouchTools()
        refresh(); syncAttachment()
    }
    private var preferenceKey: String { "mint.workspace-pouch.\(model.projectID?.rawValue.uuidString ?? "window")" }
    private func dock(immediate: Bool) {
        guard let window, let panel else { return }
        if !isCollapsed && !isDragging, attachmentFrame() != nil { syncAttachment(); return }
        refresh()
        if !isCollapsed && !isDragging {
            target = WorkspacePouchGeometry.dockedFrame(window: window.frame, edge: edge, ratio: ratio).origin
            let screen = screenFrame(for: CGPoint(x: window.frame.midX, y: window.frame.midY))
            target.x = min(max(screen.minX + 6, target.x), screen.maxX - panel.frame.width - 6)
            target.y = min(max(screen.minY + 6, target.y), screen.maxY - panel.frame.height - 6)
        } else if isCollapsed { target = WorkspacePouchGeometry.clampOrb(target, screen: screenFrame(for: target)) }
        if immediate { spring = WorkspaceSpringPoint(position: target); panel.setFrameOrigin(target) }
        else { moveTowardTarget() }
        if window.isVisible || isCollapsed { panel.orderFrontRegardless() }
    }
    private func moveTowardTarget() {
        guard let panel else { return }
        if reduceMotion {
            timer?.invalidate(); timer = nil
            spring = WorkspaceSpringPoint(position: target); panel.setFrameOrigin(target)
            if attachmentTile != nil { finishAttachment() }
            return
        }
        guard timer == nil else { return }
        lastStep = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func step() {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - lastStep; lastStep = now
        if attachmentTile != nil, !isCollapsed, !isDragging, let frame = attachmentFrame()?.screen {
            target = CGPoint(x: frame.midX - 22, y: frame.midY - 22)
        }
        spring.step(target: target, stiffness: isDragging ? 640 : 280, damping: isDragging ? 50 : 34, elapsed: elapsed)
        panel?.setFrameOrigin(spring.position)
        if spring.isSettled(at: target) {
            timer?.invalidate(); timer = nil
            if attachmentTile != nil { finishAttachment() } else { panel?.setFrameOrigin(target) }
        }
    }

    private func attachmentFrame() -> (canvas: SpatialWorkspaceCanvasView, local: CGRect, screen: CGRect)? {
        guard let tile = model.selectedTile, let canvas = model.canvas,
              canvas.window === window, let placement = canvas.pouchPlacement(for: tile), let window else { return nil }
        let local = placement.trigger.offsetBy(dx: placement.frame.minX, dy: placement.frame.minY)
        return (canvas, local, window.convertToScreen(canvas.convert(local, to: nil)))
    }

    /// The compact trigger follows selection without moving the native object.
    /// Its popover is an overlay with no reserved layout or scroll space.
    func syncAttachment() {
        guard !isCollapsed, !isDragging, start == nil, window?.isVisible == true else { return }
        guard let tile = model.selectedTile, let destination = attachmentFrame() else {
            if attachmentTile != nil {
                releaseContentToPanel(); attachmentTile = nil
                model.pouchSection = nil
                refresh(); dock(immediate: false)
            }
            return
        }
        if attachmentTile == tile, isAttached {
            updateAttachedFrame()
            return
        }
        if attachmentTile != tile {
            releaseContentToPanel()
            if attachmentTile == nil, let panel {
                spring = WorkspaceSpringPoint(position: CGPoint(x: panel.frame.midX - 22, y: panel.frame.midY - 22))
            }
            attachmentTile = tile
            refresh()
        }
        target = CGPoint(x: destination.screen.midX - 22, y: destination.screen.midY - 22)
        timer?.invalidate(); timer = nil
        spring = WorkspaceSpringPoint(position: target)
        finishAttachment()
    }

    private func releaseContentToPanel() {
        guard isAttached, let content, let panel, let window else { return }
        returnToolFocus()
        // Preserve the grab origin when the expanded card leaves the canvas.
        let lip = content.placement?.trigger ?? content.bounds
        let rect = window.convertToScreen(content.convert(lip, to: nil))
        attachedHeader?.overlayLeading = nil; attachedHeader = nil
        content.hideToolsImmediately(); content.placement = nil; toolsWereExpanded = false
        content.removeFromSuperview(); panel.contentView = content
        panel.setFrame(rect, display: false)
        spring = WorkspaceSpringPoint(position: CGPoint(x: rect.midX - 22, y: rect.midY - 22))
        panel.orderFrontRegardless()
    }

    private func returnToolFocus() {
        guard content?.toolsOwnFirstResponder == true else { return }
        let editor = model.projectID.flatMap { project in
            model.selectedTile?.documentID.flatMap { requests?.editor(for: .init(projectID: project, documentID: $0)) }
        } ?? requests?.nativeEditor
        window?.makeFirstResponder(editor)
    }

    private func finishAttachment() {
        guard !isCollapsed, !isDragging, let destination = attachmentFrame(), let content, let panel else {
            attachmentTile = nil; refresh(); dock(immediate: false); return
        }
        attachmentTile = model.selectedTile
        panel.contentView = nil
        content.removeFromSuperview()
        if let tile = model.selectedTile {
            attachedHeader = destination.canvas.header(for: tile)
        }
        destination.canvas.addSubview(content, positioned: .above, relativeTo: nil)
        content.autoresizingMask = []
        panel.orderOut(nil); refresh(); updateAttachedFrame()
    }
    private func updateAttachedFrame() {
        guard let content, let tile = model.selectedTile, let placement = model.canvas?.pouchPlacement(for: tile) else { return }
        if let canvas = model.canvas, canvas.subviews.last !== content {
            canvas.addSubview(content, positioned: .above, relativeTo: nil)
        }
        let opened = !toolsWereExpanded && model.pouchSection != nil
        toolsWereExpanded = model.pouchSection != nil
        if content.placement != placement {
            content.placement = placement; content.frame = placement.frame
        }
        if attachedHeader == nil { attachedHeader = model.canvas?.header(for: tile) }
        if let host = model.canvas?.hosts[tile] {
            attachedHeader?.overlayLeading = placement.frame.minX + placement.trigger.minX - host.frame.minX
        }
        if opened { content.revealTools(reduceMotion: reduceMotion) }
    }
    func dismissTools() {
        guard model.pouchSection != nil else { return }
        returnToolFocus()
        model.pouchSection = nil
        content?.hideToolsImmediately()
        refresh(); syncAttachment()
        content?.layoutSubtreeIfNeeded()
    }
    func dismissObject(_ tile: WorkspaceTileID) {
        returnToolFocus()
        if tile.documentID != nil && model.layout.openDocuments.count <= 1 {
            collapse()
        } else if model.close(tile) { requests?.focusEditor() }
    }
    private func screenFrame(for point: CGPoint) -> CGRect {
        (NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? window?.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
    func showMoreMenu(in view: NSView) {
        moreMenu().popUp(positioning: nil, at: CGPoint(x: view.bounds.maxX, y: view.bounds.midY), in: view)
    }
    func moreMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for (index, action) in menuActions.enumerated() {
            let item = NSMenuItem(title: action.label, action: #selector(invokeExtra(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            item.state = action.selected() ? .on : .off; item.isEnabled = action.enabled()
            item.setAccessibilityIdentifier(action.id); menu.addItem(item)
        }
        return menu
    }
    @objc private func invokeExtra(_ item: NSMenuItem) {
        guard menuActions.indices.contains(item.tag), menuActions[item.tag].enabled() else { return }; menuActions[item.tag].perform()
    }
    private var menuActions: [WorkspacePouchAction] { (isAttached ? actions : []) + extraActions }
    private func cancelTransition() {
        transitionGeneration &+= 1
        transition?.orderOut(nil); transition?.close(); transition = nil
        window?.alphaValue = 1
    }

    private func animateSnapshot(of window: NSWindow, toward rect: CGRect, expandingFrom origin: CGRect? = nil) {
        let image: NSImage
        if origin != nil, let cached = collapsedImage {
            image = cached
        } else {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                window.alphaValue = 1
                return
            }
            // Capture once per collapse, never on pointer movement or animation ticks.
            view.cacheDisplay(in: view.bounds, to: bitmap)
            image = NSImage(size: view.bounds.size); image.addRepresentation(bitmap)
            if origin == nil { collapsedImage = image }
        }
        let generation = transitionGeneration
        let ghost = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ghost.isReleasedWhenClosed = false; ghost.ignoresMouseEvents = true; ghost.level = .floating
        ghost.isOpaque = false; ghost.backgroundColor = .clear; ghost.hasShadow = false
        ghost.hidesOnDeactivate = false; ghost.animationBehavior = .none
        ghost.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: window.frame.size))
        imageView.image = image; imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.name = "collapseBlur"
        blur?.setValue(origin == nil ? 12 : 0, forKey: kCIInputRadiusKey)
        if let blur { imageView.layer?.filters = [blur] }
        let blurAnimation = CABasicAnimation(keyPath: "filters.collapseBlur.inputRadius")
        blurAnimation.fromValue = origin == nil ? 0 : 10; blurAnimation.toValue = origin == nil ? 12 : 0
        blurAnimation.duration = origin == nil ? 0.12 : 0.14
        blurAnimation.timingFunction = origin == nil ? CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) : WorkspaceHTMLStyle.calm
        imageView.layer?.add(blurAnimation, forKey: "pouch.blur")
        ghost.contentView = imageView; transition = ghost
        if let origin { ghost.setFrame(origin, display: false); ghost.alphaValue = 0; window.alphaValue = 0 }
        ghost.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = origin == nil ? 0.12 : 0.14
            context.timingFunction = origin == nil ? CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) : WorkspaceHTMLStyle.calm
            ghost.animator().setFrame(rect, display: true); ghost.animator().alphaValue = origin == nil ? 0 : 1
        } completionHandler: { [weak self, weak ghost, weak window] in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation, self.transition === ghost else {
                    ghost?.orderOut(nil); ghost?.close()
                    return
                }
                window?.alphaValue = 1; ghost?.orderOut(nil); ghost?.close()
                self.transition = nil
                if origin != nil { self.collapsedImage = nil }
            }
        }
    }
    private func collapsedSnapshotFrame(window: NSWindow, orb: CGRect) -> CGRect {
        let size = CGSize(width: window.frame.width * 0.03, height: window.frame.height * 0.03)
        return CGRect(x: orb.midX - size.width / 2, y: orb.midY - size.height / 2, width: size.width, height: size.height)
    }
}
