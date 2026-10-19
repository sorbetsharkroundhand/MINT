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
    private var edge: WorkspacePouchEdge = .left
    private var ratio = 0.45
    private var loadedKey: String?
    private var target = CGPoint.zero
    private var spring = WorkspaceSpringPoint(position: .zero)
    private var timer: Timer?
    private var lastStep = ProcessInfo.processInfo.systemUptime
    private var savedButtons: [(NSButton, AnyObject?, Selector?)] = []
    private var transition: NSPanel?
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
        panel.hidesOnDeactivate = true; panel.collectionBehavior = [.fullScreenAuxiliary]
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
        timer?.invalidate(); timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        for (button, owner, action) in savedButtons { button.target = owner; button.action = action }
        savedButtons.removeAll()
        transition?.orderOut(nil); transition?.close(); transition = nil
        panel?.orderOut(nil); panel?.close(); panel = nil; content = nil; window = nil
        start = nil; isDragging = false; isCollapsed = false
    }

    func beginDrag(at point: CGPoint) { start = point; isDragging = false }
    func updateDrag(to point: CGPoint) {
        guard let start, let window else { return }
        if !isDragging {
            guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
            isDragging = true; refresh()
        }
        let screen = screenFrame(for: point)
        target = WorkspacePouchGeometry.clampOrb(CGPoint(x: point.x - 22, y: point.y - 22), screen: screen, margin: 6)
        moveTowardTarget()
        let orb = CGRect(origin: target, size: CGSize(width: 44, height: 44))
        if !isCollapsed, !window.frame.insetBy(dx: -4, dy: -4).contains(orb) { collapse() }
    }
    @discardableResult func endDrag(at point: CGPoint) -> Bool {
        guard start != nil else { return false }
        start = nil
        let moved = isDragging; isDragging = false
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

    @objc private func collapseFromButton() { collapse() }
    func collapse() {
        guard !isCollapsed, let window, let panel else { return }
        previousResponder = window.firstResponder
        if let editor = window.firstResponder as? BlockTextView, editor.hasMarkedText() {
            editor.unmarkText(); editor.didChangeText()
        }
        target = WorkspacePouchGeometry.clampOrb(target, screen: screenFrame(for: target))
        if !reduceMotion { animateSnapshot(of: window, toward: CGRect(origin: target, size: CGSize(width: 44, height: 44))) }
        isCollapsed = true; window.orderOut(nil); refresh()
        panel.setContentSize(CGSize(width: 44, height: 44)); panel.orderFrontRegardless(); moveTowardTarget()
    }
    func restore() {
        guard isCollapsed, let window else { return }
        let origin = panel?.frame ?? CGRect(origin: target, size: CGSize(width: 44, height: 44))
        isCollapsed = false; isDragging = false; start = nil
        window.makeKeyAndOrderFront(nil)
        if let previousResponder { window.makeFirstResponder(previousResponder) }
        refresh(); dock(immediate: false)
        if !reduceMotion {
            animateSnapshot(of: window, toward: window.frame, expandingFrom: origin)
        }
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
        panel.alphaValue = model.whisperTyping && !isCollapsed ? 0.06 : (reduceTransparency ? 1 : 0.84)
        panel.ignoresMouseEvents = model.whisperTyping && !isCollapsed
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
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
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
        let menu = NSMenu()
        for (index, action) in extraActions.enumerated() {
            let item = NSMenuItem(title: action.label, action: #selector(invokeExtra(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            item.setAccessibilityIdentifier(action.id); menu.addItem(item)
        }
        return menu
    }
    @objc private func invokeExtra(_ item: NSMenuItem) {
        guard extraActions.indices.contains(item.tag) else { return }; extraActions[item.tag].perform()
    }
    private func animateSnapshot(of window: NSWindow, toward rect: CGRect, expandingFrom origin: CGRect? = nil) {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size); image.addRepresentation(bitmap)
        let ghost = NSPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ghost.isReleasedWhenClosed = false; ghost.ignoresMouseEvents = true; ghost.level = .floating
        ghost.isOpaque = false; ghost.backgroundColor = .clear
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: window.frame.size))
        imageView.image = image; imageView.imageScaling = .scaleAxesIndependently
        transition?.orderOut(nil); transition?.close()
        ghost.contentView = imageView; transition = ghost
        if let origin { ghost.setFrame(origin, display: false); ghost.alphaValue = 0; window.alphaValue = 0 }
        ghost.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = origin == nil ? 0.36 : 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: origin == nil ? 0.4 : 0.25, 0, origin == nil ? 0.2 : 0.5, 1)
            ghost.animator().setFrame(rect, display: true); ghost.animator().alphaValue = origin == nil ? 0 : 1
        } completionHandler: { [weak self, weak ghost, weak window] in
            MainActor.assumeIsolated {
                window?.alphaValue = 1; ghost?.orderOut(nil); ghost?.close()
                if self?.transition === ghost { self?.transition = nil }
            }
        }
    }
}
