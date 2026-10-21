import AppKit
import Combine
import QuartzCore

struct WorkspacePouchAction {
    let id: String
    let label: String
    let symbol: String
    var selected: () -> Bool = { false }
    var enabled: () -> Bool = { true }
    let perform: () -> Void
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
    private weak var window: NSWindow?
    private weak var previousResponder: NSResponder?
    private let model: SpatialWorkspaceController
    private let defaults: UserDefaults
    private var content: WorkspacePouchView?
    private var observers: [NSObjectProtocol] = []
    private var subscription: AnyCancellable?
    private var start: CGPoint?
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
    private struct Preference: Codable { let edge: WorkspacePouchEdge; let ratio: Double }

    init(model: SpatialWorkspaceController, defaults: UserDefaults = .standard) {
        self.model = model; self.defaults = defaults
        super.init()
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else {
            let changed = loadedKey != preferenceKey
            refresh(); if changed { dock(immediate: true) }; return
        }
        detach(); self.window = window
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "MINT 주머니"; panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
        panel.isMovable = false; panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = WorkspacePouchView(); content.controller = self
        content.setAccessibilityIdentifier("mint.workspace.rail"); content.setAccessibilityLabel("주머니 도구창")
        panel.contentView = content; self.panel = panel; self.content = content
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
        timer?.invalidate(); timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        for (button, owner, action) in savedButtons { button.target = owner; button.action = action }
        savedButtons.removeAll()
        cancelTransition(); collapsedImage = nil
        panel?.orderOut(nil); panel?.close(); panel = nil; content = nil; window = nil
        start = nil; isDragging = false; isCollapsed = false
    }

    func beginDrag(at point: CGPoint) {
        stopDragTracking()
        start = point; isDragging = false
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
            guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
            isDragging = true
            NSCursor.closedHand.push(); draggingCursor = true
            refresh()
        }
        let screen = screenFrame(for: point)
        target = WorkspacePouchGeometry.clampOrb(
            CGPoint(x: point.x - 22, y: point.y - 22), screen: screen, margin: 6)
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
        previousResponder = window.firstResponder
        // Hiding a retained window is a presentation change, not an editor commit.
        // Keep marked text and the native selection with the same first responder;
        // do not enqueue diagnostics/autosave by synthesizing didChangeText here.
        target = WorkspacePouchGeometry.clampOrb(target, screen: screenFrame(for: target))
        cancelTransition()
        isCollapsed = true
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
        window.makeKeyAndOrderFront(nil)
        if let previousResponder { window.makeFirstResponder(previousResponder) }
        refresh(); dock(immediate: false)
        if !reduceMotion {
            animateSnapshot(of: window, toward: window.frame, expandingFrom: collapsedSnapshotFrame(window: window, orb: origin))
        } else { collapsedImage = nil }
    }

    func refresh() {
        guard let panel, let content else { return }
        if loadedKey != preferenceKey {
            loadedKey = preferenceKey
            if let data = defaults.data(forKey: preferenceKey), let saved = try? JSONDecoder().decode(Preference.self, from: data), saved.ratio.isFinite {
                edge = saved.edge; ratio = min(0.95, max(0.05, saved.ratio))
            } else { edge = .left; ratio = 0.45 }
        }
        content.configure(orb: isCollapsed || isDragging, horizontal: edge == .top || edge == .bottom,
            actions: actions, theme: theme)
        panel.hidesOnDeactivate = !isCollapsed && !isDragging
        let opacity: CGFloat = model.whisperTyping && !isCollapsed && !isDragging ? 0.06 : (isCollapsed || isDragging || content.hovered || reduceTransparency ? 1 : 0.84)
        if reduceMotion { panel.alphaValue = opacity }
        else if abs(panel.alphaValue - opacity) > 0.001 {
            WorkspaceHTMLStyle.animate(0.32) { panel.animator().alphaValue = opacity }
        }
        panel.ignoresMouseEvents = model.whisperTyping && !isCollapsed && !isDragging
        if isCollapsed || isDragging { panel.setContentSize(CGSize(width: 44, height: 44)) }
        else if let window { panel.setContentSize(WorkspacePouchGeometry.dockedFrame(window: window.frame, edge: edge, ratio: ratio).size) }
        content.needsLayout = true; content.needsDisplay = true
    }
    private var preferenceKey: String { "mint.workspace-pouch.\(model.projectID?.rawValue.uuidString ?? "window")" }
    private func dock(immediate: Bool) {
        guard let window, let panel else { return }
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
        if reduceMotion { spring = WorkspaceSpringPoint(position: target); panel.setFrameOrigin(target); return }
        guard timer == nil else { return }
        lastStep = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func step() {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - lastStep; lastStep = now
        spring.step(target: target, stiffness: isDragging ? 640 : 280, damping: isDragging ? 50 : 34, elapsed: elapsed)
        panel?.setFrameOrigin(spring.position)
        if spring.isSettled(at: target) { panel?.setFrameOrigin(target); timer?.invalidate(); timer = nil }
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
        for (index, action) in extraActions.enumerated() {
            let item = NSMenuItem(title: action.label, action: #selector(invokeExtra(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            item.state = action.selected() ? .on : .off; item.isEnabled = action.enabled()
            item.setAccessibilityIdentifier(action.id); menu.addItem(item)
        }
        return menu
    }
    @objc private func invokeExtra(_ item: NSMenuItem) {
        guard extraActions.indices.contains(item.tag), extraActions[item.tag].enabled() else { return }; extraActions[item.tag].perform()
    }
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
        blurAnimation.duration = origin == nil ? 0.36 : 0.38
        blurAnimation.timingFunction = origin == nil ? CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) : WorkspaceHTMLStyle.calm
        imageView.layer?.add(blurAnimation, forKey: "pouch.blur")
        ghost.contentView = imageView; transition = ghost
        if let origin { ghost.setFrame(origin, display: false); ghost.alphaValue = 0; window.alphaValue = 0 }
        ghost.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = origin == nil ? 0.36 : 0.38
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
