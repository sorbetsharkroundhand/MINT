import AppKit
import SwiftUI

enum WorkspacePouchMetrics {
    static func indexWidth(for tile: WorkspaceTileID, available: CGFloat) -> CGFloat {
        min(tile.documentID == nil ? 148 : 260, max(68, available - 100))
    }
}

final class WorkspacePouchView: NSView {
    weak var controller: WorkspacePouchController?
    private let grip = WorkspacePouchButton(title: "", target: nil, action: nil)
    private var buttons: [WorkspacePouchButton] = []
    private var actions: [WorkspacePouchAction] = []
    private var orb = false, horizontal = false
    private var fused = false
    private var toolsHost: NSHostingView<AnyView>?
    private let dismissButton = WorkspacePouchButton(title: "", target: nil, action: nil)
    var placement: WorkspacePouchPlacement? { didSet { if placement != oldValue { needsLayout = true; needsDisplay = true } } }
    var baseSurface: NSColor = MintTheme.light.editorSurface
    var indexWidth: CGFloat = 276
    var toolsHeight: CGFloat = 300
    var toolsExpanded = false { didSet { needsLayout = true; needsDisplay = true } }
    var fusionProgress: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }
    private let contourMask = CAShapeLayer()
    private var theme: MintTheme = .light
    private(set) var hovered = false
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.mask = contourMask
        setAccessibilityElement(true); setAccessibilityRole(.group)
        grip.target = self; grip.action = #selector(activateGrip)
        grip.isBordered = false; grip.refusesFirstResponder = false; grip.draggable = true
        addSubview(grip)
        dismissButton.target = self; dismissButton.action = #selector(dismissTools)
        dismissButton.image = WorkspaceIcons.image("xmark", size: 11)
        dismissButton.refusesFirstResponder = false
        dismissButton.setAccessibilityIdentifier("mint.workspace.pouch.dismiss")
        dismissButton.setAccessibilityLabel("도구 닫기")
        dismissButton.toolTip = "도구 닫기 · Esc"
        addSubview(dismissButton)
    }
    required init?(coder: NSCoder) { nil }

    func setTools(_ root: AnyView) {
        if let toolsHost { toolsHost.rootView = root }
        else {
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []; host.wantsLayer = true
            addSubview(host, positioned: .below, relativeTo: dismissButton); toolsHost = host
        }
        needsLayout = true
    }
    func clearPressedState() { grip.highlight(false) }
    func revealControls(reduceMotion: Bool) {
        guard !reduceMotion else { return }
        for view in [grip] + buttons { reveal(view, from: 0.6) }
    }
    func revealTools(reduceMotion: Bool) {
        guard !reduceMotion, let toolsHost else { return }
        reveal(toolsHost, from: 0)
    }
    private func reveal(_ view: NSView, from opacity: Float) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = view.layer?.animation(forKey: "pouch.reveal") == nil ? opacity : (view.layer?.presentation()?.opacity ?? opacity)
        fade.toValue = 1; fade.duration = 0.12; fade.timingFunction = WorkspaceHTMLStyle.calm
        view.layer?.add(fade, forKey: "pouch.reveal")
    }

    var toolsOwnFirstResponder: Bool {
        guard let toolsHost, let responder = window?.firstResponder as? NSView else { return false }
        if responder.isDescendant(of: toolsHost) { return true }
        // AppKit's shared field editor lives outside its TextField's view hierarchy.
        return ((responder as? NSTextView)?.delegate as? NSView)?.isDescendant(of: toolsHost) == true
    }

    func configure(orb: Bool, horizontal: Bool, actions: [WorkspacePouchAction], theme: MintTheme, fused: Bool = false) {
        self.orb = orb; self.horizontal = horizontal; self.actions = actions; self.theme = theme; self.fused = fused
        dismissButton.theme = theme; dismissButton.refresh()
        if fused { fusionProgress = 1 } else if !orb { fusionProgress = 0 }
        layer?.cornerRadius = 0
        grip.controller = controller
        grip.title = orb ? "M" : ""
        grip.image = fused ? WorkspaceIcons.image("square.grid.2x2", size: 12) : nil
        grip.theme = theme; grip.selected = orb
        grip.font = MintFonts.serif(12, weight: .bold)
        grip.refresh()
        grip.setAccessibilityIdentifier(orb ? "mint.workspace.pouch.restore" : "mint.writer-tools.compatibility")
        grip.setAccessibilityLabel(orb ? "MINT 전체 창 펼치기" : "모든 도구 · 드래그하여 주머니 이동")
        grip.toolTip = orb ? "클릭하여 원고 펼치기 · 드래그하여 이동" : "모든 도구 · 이 손잡이로 주머니 이동"
        grip.menu = controller?.moreMenu()
        while buttons.count > actions.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < actions.count {
            let button = WorkspacePouchButton(title: "", target: self, action: #selector(invoke(_:)))
            button.isBordered = false; button.refusesFirstResponder = false; button.wantsLayer = true
            buttons.append(button); addSubview(button)
        }
        for (index, action) in actions.enumerated() {
            let button = buttons[index]; button.controller = controller; button.tag = index; button.isHidden = orb
            let compact = fused && (placement?.index.width ?? 260) < 240
            button.image = (!fused || compact || action.id == "mint.source-search.show") && !action.symbol.isEmpty
                ? WorkspaceIcons.image(action.symbol, size: compact ? 12 : 14) : nil
            button.title = fused && !compact && action.id != "mint.source-search.show" ? action.label : ""
            button.font = MintFonts.ui(11, weight: .medium)
            let selected = action.selected()
            button.setButtonType(.toggle); button.state = selected ? .on : .off
            button.isEnabled = action.enabled()
            button.contentTintColor = selected ? theme.blue : theme.ink2
            button.theme = theme; button.selected = selected; button.refresh()
            button.setAccessibilityIdentifier(action.id); button.setAccessibilityLabel(action.label)
            button.setAccessibilityValue(NSNumber(value: selected)); button.toolTip = action.label
        }
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        contourMask.frame = bounds; contourMask.path = contour
        CATransaction.commit()
        toolsHost?.isHidden = !fused || !toolsExpanded
        dismissButton.isHidden = !fused || !toolsExpanded
        if fused, let placement {
            let index = placement.index
            grip.frame = CGRect(x: index.minX, y: index.minY + 1, width: 24, height: 26)
            let width = max(1, (index.width - 26) / CGFloat(max(1, buttons.count)))
            for (i, button) in buttons.enumerated() {
                button.frame = CGRect(x: index.minX + 26 + CGFloat(i) * width, y: index.minY + 1, width: width - 1, height: 26)
            }
            dismissButton.frame = CGRect(x: bounds.width - 32, y: placement.tools.minY + 2, width: 24, height: 24)
            // Reveal a stable layout through the contour mask. Resizing text on
            // every animation frame makes controls swim under the pointer.
            toolsHost?.frame = CGRect(x: 0, y: placement.tools.minY + 26, width: bounds.width, height: max(0, placement.tools.height - 26))
            return
        }
        if orb {
            let p = fusionProgress
            grip.frame = CGRect(x: 10 * p, y: p,
                width: bounds.width * (1 - p) + 28 * p, height: bounds.height * (1 - p) + 26 * p)
            return
        }
        if fused {
            let inset = labelInset, width = labelWidth
            grip.frame = CGRect(x: inset + 10, y: 1, width: 28, height: 26)
            let actionWidth = max(0, width - 80) / CGFloat(max(1, buttons.count - 1))
            for (index, button) in buttons.enumerated() {
                if index == buttons.count - 1 {
                    button.frame = CGRect(x: inset + width - 38, y: 1, width: 28, height: 26)
                } else {
                    button.frame = CGRect(x: inset + 40 + CGFloat(index) * actionWidth, y: 1, width: actionWidth - 2, height: 26)
                }
            }
            return
        }
        grip.frame = horizontal ? CGRect(x: 4, y: 5, width: 12, height: 28) : CGRect(x: 5, y: 3, width: 28, height: 12)
        var position: CGFloat = 18
        for (index, button) in buttons.enumerated() {
            if index == 4 { position += 12 }
            button.frame = horizontal ? CGRect(x: position, y: 5, width: 28, height: 28)
                : CGRect(x: 5, y: position, width: 28, height: 28)
            position += 32
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        // Composite the accent into the actual paper. Forcing a translucent theme
        // token opaque used to turn custom dark palettes into a bright gray slab.
        let base = baseSurface.withAlphaComponent(1)
        let tint = base.blended(withFraction: 0.14, of: theme.novel.withAlphaComponent(1)) ?? base
        if fused, let placement, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState(); context.addPath(placement.contour); context.clip()
            if toolsExpanded { base.setFill(); placement.tools.fill() }
            let accent = CGRect(x: placement.index.minX - 10, y: 0, width: placement.index.width + 20, height: placement.bodyTop + 32)
            NSGradient(starting: tint, ending: base)?.draw(in: accent, relativeCenterPosition: CGPoint(x: 0, y: -0.5))
            context.restoreGState()
            return
        }
        (fused || fusionProgress > 0 ? base : tint).setFill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(contour); context.fillPath()
        if fused || fusionProgress > 0 {
            context.saveGState(); context.addPath(contour); context.clip()
            // One opaque surface meets the object with exactly the same color.
            // Only the protruding label carries the pouch tint; there is no skirt.
            NSGradient(starting: tint, ending: baseSurface.withAlphaComponent(1))?
                .draw(from: CGPoint(x: 0, y: 4), to: CGPoint(x: 0, y: 28), options: [.drawsBeforeStartingLocation])
            context.restoreGState()
            if fused { return }
        }
        theme.pillBorder.setStroke()
        if fusionProgress == 0 { NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: orb ? 14 : 12, yRadius: orb ? 14 : 12).stroke() }
        if orb {
            theme.novelBg.withAlphaComponent(1 - fusionProgress).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: hovered ? 6.6 : 8, dy: hovered ? 6.6 : 8), xRadius: 8, yRadius: 8).fill()
            theme.novel.withAlphaComponent(1 - fusionProgress).setFill(); NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 10, y: 4, width: 6, height: 6)).fill()
            return
        }
        theme.workspaceMuted.withAlphaComponent(0.35).setFill()
        let gripRect = horizontal ? CGRect(x: 8, y: 12, width: 3, height: 14) : CGRect(x: 12, y: 7, width: 14, height: 3)
        NSBezierPath(roundedRect: gripRect, xRadius: 1.5, yRadius: 1.5).fill()
        theme.sepStrong.setFill()
        if horizontal { CGRect(x: 151, y: 11, width: 1, height: 16).fill() }
        else { CGRect(x: 11, y: 151, width: 16, height: 1).fill() }
    }
    private var labelInset: CGFloat { fused && bounds.height > 36.5 ? 16 : 0 }
    private var labelWidth: CGFloat { min(indexWidth, bounds.width - labelInset * 2) }
    private var contour: CGPath {
        if fused, let placement { return placement.contour }
        let p = fusionProgress
        guard p > 0 else { return CGPath(roundedRect: bounds, cornerWidth: orb ? 14 : 12, cornerHeight: orb ? 14 : 12, transform: nil) }
        let w = bounds.width, h = bounds.height, shoulder = 8 * p
        let left = labelInset, right = fused ? left + labelWidth : w
        let radius = 14 - 6 * p, bottomRadius = 14 * (1 - p)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + shoulder + radius, y: 0))
        path.addLine(to: CGPoint(x: right - shoulder - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: right - shoulder, y: radius), control: CGPoint(x: right - shoulder, y: 0))
        path.addLine(to: CGPoint(x: right - shoulder, y: 20))
        path.addQuadCurve(to: CGPoint(x: right, y: 28), control: CGPoint(x: right - shoulder, y: 28))
        if labelInset > 0 {
            path.addLine(to: CGPoint(x: w - 13, y: 28))
            path.addQuadCurve(to: CGPoint(x: w, y: 41), control: CGPoint(x: w, y: 28))
        }
        path.addLine(to: CGPoint(x: w, y: h - bottomRadius))
        path.addQuadCurve(to: CGPoint(x: w - bottomRadius, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: bottomRadius, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - bottomRadius), control: CGPoint(x: 0, y: h))
        if labelInset > 0 {
            path.addLine(to: CGPoint(x: 0, y: 41))
            path.addQuadCurve(to: CGPoint(x: 13, y: 28), control: CGPoint(x: 0, y: 28))
        }
        path.addLine(to: CGPoint(x: left, y: 28))
        path.addQuadCurve(to: CGPoint(x: left + shoulder, y: 20), control: CGPoint(x: left + shoulder, y: 28))
        path.addLine(to: CGPoint(x: left + shoulder, y: radius))
        path.addQuadCurve(to: CGPoint(x: left + shoulder + radius, y: 0), control: CGPoint(x: left + shoulder, y: 0))
        path.closeSubpath(); return path
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard contour.contains(local) else { return nil }
        if fused, let placement, !placement.index.contains(local), !(toolsExpanded && placement.tools.contains(local)) { return nil }
        return super.hitTest(point)
    }
    override func accessibilityFrame() -> NSRect {
        guard fused, let placement, let window else { return super.accessibilityFrame() }
        let area = toolsExpanded ? placement.index.union(placement.tools) : placement.index
        return window.convertToScreen(convert(area, to: nil))
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea); super.updateTrackingAreas()
        addTrackingArea(.init(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; controller?.refresh() }
    override func mouseExited(with event: NSEvent) { hovered = false; controller?.refresh() }
    @objc private func activateGrip() {
        if orb { controller?.restore() } else { controller?.showMoreMenu(in: grip) }
    }
    @objc private func invoke(_ button: NSButton) {
        guard actions.indices.contains(button.tag) else { return }
        actions[button.tag].perform(); controller?.refresh()
    }
    @objc private func dismissTools() { controller?.dismissTools() }
    override func mouseDown(with event: NSEvent) {
        if !fused || convert(event.locationInWindow, from: nil).y < 32 {
            controller?.beginDrag(at: screenPoint(event))
        }
    }
    override func mouseDragged(with event: NSEvent) { controller?.updateDrag(to: screenPoint(event)) }
    override func mouseUp(with event: NSEvent) { _ = controller?.endDrag(at: screenPoint(event)) }
    override func rightMouseDown(with event: NSEvent) { controller?.showMoreMenu(in: self) }
    override func resetCursorRects() {
        addCursorRect(grip.frame, cursor: .openHand)
    }
    private func screenPoint(_ event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
}

final class WorkspacePouchButton: WorkspaceHTMLButton {
    weak var controller: WorkspacePouchController?
    var draggable = false
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        guard draggable else { super.mouseDown(with: event); return }
        highlight(true); controller?.beginDrag(at: screenPoint(event))
    }
    override func mouseDragged(with event: NSEvent) {
        if draggable { controller?.updateDrag(to: screenPoint(event)) }
    }
    override func mouseUp(with event: NSEvent) {
        guard draggable else { super.mouseUp(with: event); return }
        highlight(false)
        if controller?.endDrag(at: screenPoint(event)) != true { performClick(nil) }
    }
    override func highlight(_ flag: Bool) { super.highlight(flag); refresh() }
    override func refresh() {
        super.refresh()
        let active = selected || isHighlighted
        layer?.backgroundColor = (active ? theme.novel.withAlphaComponent(0.13) : (hovered ? theme.hover : .clear)).cgColor
        contentTintColor = isEnabled ? theme.ink : theme.ink2
        if !title.isEmpty {
            attributedTitle = NSAttributedString(string: title, attributes: [
                .font: font ?? MintFonts.ui(11, weight: .medium),
                .foregroundColor: isEnabled ? theme.ink : theme.ink2
            ])
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func screenPoint(_ event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
}

struct WorkspacePouchBridge: NSViewRepresentable {
    @ObservedObject var model: SpatialWorkspaceController
    let requests: ProjectEditorRequests
    let defaults: UserDefaults
    let theme: MintTheme
    let tools: AnyView
    let actions: [WorkspacePouchAction]
    let extraActions: [WorkspacePouchAction]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.mintWorkspaceAccessibilityOptions) private var accessibilityOptions

    func makeCoordinator() -> Coordinator { Coordinator(model: model, defaults: defaults) }
    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.coordinator = context.coordinator; view.controller = context.coordinator.controller
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        if let window = view.window { context.coordinator.attach(to: window, from: view) }
        let controller = context.coordinator.controller
        controller.reduceMotion = systemReduceMotion || accessibilityOptions.reduceMotion
        controller.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || accessibilityOptions.reduceTransparency
        controller.theme = theme; controller.actions = actions; controller.extraActions = extraActions
        controller.requests = requests
        controller.setTools(tools)
        requests.pouch = controller
    }
    static func dismantleNSView(_ view: Probe, coordinator: Coordinator) {
        coordinator.controller.detachFromWorkspaceView(view)
        view.coordinator = nil; view.controller = nil
    }
    @MainActor final class Coordinator {
        private(set) var controller: WorkspacePouchController
        init(model: SpatialWorkspaceController, defaults: UserDefaults) { controller = WorkspacePouchController(model: model, defaults: defaults) }
        func attach(to window: NSWindow, from view: Probe) {
            if let retained = WorkspacePouchLifetime.controller(for: window), retained !== controller {
                controller.detachFromWorkspaceView(view)
                controller = retained
            }
            view.controller = controller
            controller.attach(to: window, from: view)
        }
    }
    final class Probe: NSView {
        weak var coordinator: Coordinator?
        weak var controller: WorkspacePouchController?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { coordinator?.attach(to: window, from: self) }
            else { controller?.detachFromWorkspaceView(self) }
        }
    }
}
