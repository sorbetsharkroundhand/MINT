import AppKit
import SwiftUI

final class WorkspacePouchView: NSVisualEffectView {
    weak var controller: WorkspacePouchController?
    private let grip = WorkspacePouchButton(title: "", target: nil, action: nil)
    private var buttons: [WorkspacePouchButton] = []
    private var actions: [WorkspacePouchAction] = []
    private var orb = false, horizontal = false
    private var fused = false
    var fusionProgress: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }
    private let contourMask = CAShapeLayer()
    private var theme: MintTheme = .light
    private(set) var hovered = false
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover; blendingMode = .behindWindow; state = .active; wantsLayer = true
        layer?.masksToBounds = true
        layer?.mask = contourMask
        setAccessibilityElement(true); setAccessibilityRole(.group)
        grip.target = self; grip.action = #selector(activateGrip)
        grip.isBordered = false; grip.refusesFirstResponder = false
        addSubview(grip)
    }
    required init?(coder: NSCoder) { nil }

    func configure(orb: Bool, horizontal: Bool, actions: [WorkspacePouchAction], theme: MintTheme, fused: Bool = false) {
        self.orb = orb; self.horizontal = horizontal; self.actions = actions; self.theme = theme; self.fused = fused
        if fused { fusionProgress = 1 } else if !orb { fusionProgress = 0 }
        layer?.cornerRadius = 0
        grip.controller = controller
        grip.title = orb || fused ? "M" : ""
        grip.theme = theme; grip.selected = orb
        grip.font = MintFonts.serif(12, weight: .bold)
        grip.refresh()
        grip.setAccessibilityIdentifier(orb ? "mint.workspace.pouch.restore" : "mint.writer-tools.compatibility")
        grip.setAccessibilityLabel(orb ? "MINT 전체 창 펼치기" : "주머니의 모든 도구 · 드래그하여 떼어 놓기")
        grip.menu = controller?.moreMenu()
        while buttons.count > actions.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < actions.count {
            let button = WorkspacePouchButton(title: "", target: self, action: #selector(invoke(_:)))
            button.isBordered = false; button.refusesFirstResponder = true; button.wantsLayer = true
            buttons.append(button); addSubview(button)
        }
        for (index, action) in actions.enumerated() {
            let button = buttons[index]; button.controller = controller; button.tag = index; button.isHidden = orb
            button.image = WorkspaceIcons.image(action.symbol, size: 14)
            let selected = action.selected()
            button.setButtonType(.toggle); button.state = selected ? .on : .off
            button.isEnabled = action.enabled()
            button.contentTintColor = selected ? theme.blue : theme.ink2
            button.theme = theme; button.selected = selected; button.refresh()
            button.layer?.backgroundColor = (selected ? theme.activeBg : NSColor.clear).cgColor
            button.layer?.cornerRadius = MintRadius.sm
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
        if orb {
            let p = fusionProgress
            grip.frame = CGRect(x: 15 * p, y: 7 * p,
                width: bounds.width * (1 - p) + 22 * p, height: bounds.height * (1 - p) + 25 * p)
            return
        }
        if fused {
            grip.frame = CGRect(x: 15, y: 7, width: 22, height: 25)
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: 39 + CGFloat(index) * 28, y: 7, width: 26, height: 25)
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
        let tint = theme.novelBg.blended(withFraction: 0.35, of: theme.pill) ?? theme.pill
        (fused || fusionProgress > 0 ? tint.withAlphaComponent(1) : (controller?.reduceTransparency == true ? theme.pill.withAlphaComponent(1) : theme.pill)).setFill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(contour); context.fillPath()
        if fused { return }
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
    private var contour: CGPath {
        let p = fusionProgress
        guard p > 0 else { return CGPath(roundedRect: bounds, cornerWidth: orb ? 14 : 12, cornerHeight: orb ? 14 : 12, transform: nil) }
        let w = bounds.width, h = bounds.height, shoulder = 12 * p, radius = 14.0, corner = 14 * (1 - p)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: corner, y: 0)); path.addLine(to: CGPoint(x: w - corner, y: 0))
        path.addCurve(to: CGPoint(x: w - shoulder, y: corner + shoulder), control1: CGPoint(x: w - corner * 0.448 - shoulder * 0.8, y: 0), control2: CGPoint(x: w - shoulder, y: corner * 0.448 + shoulder * 0.3))
        path.addLine(to: CGPoint(x: w - shoulder, y: h - radius))
        path.addQuadCurve(to: CGPoint(x: w - shoulder - radius, y: h), control: CGPoint(x: w - shoulder, y: h))
        path.addLine(to: CGPoint(x: shoulder + radius, y: h))
        path.addQuadCurve(to: CGPoint(x: shoulder, y: h - radius), control: CGPoint(x: shoulder, y: h))
        path.addLine(to: CGPoint(x: shoulder, y: corner + shoulder))
        path.addCurve(to: CGPoint(x: corner, y: 0), control1: CGPoint(x: shoulder, y: corner * 0.448 + shoulder * 0.3), control2: CGPoint(x: corner * 0.448 + shoulder * 0.8, y: 0))
        path.closeSubpath(); return path
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard contour.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
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
    override func mouseDown(with event: NSEvent) { controller?.beginDrag(at: screenPoint(event)) }
    override func mouseDragged(with event: NSEvent) { controller?.updateDrag(to: screenPoint(event)) }
    override func mouseUp(with event: NSEvent) { _ = controller?.endDrag(at: screenPoint(event)) }
    override func rightMouseDown(with event: NSEvent) { controller?.showMoreMenu(in: self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    private func screenPoint(_ event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
}

final class WorkspacePouchButton: WorkspaceHTMLButton {
    weak var controller: WorkspacePouchController?
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { controller?.beginDrag(at: screenPoint(event)) }
    override func mouseDragged(with event: NSEvent) { controller?.updateDrag(to: screenPoint(event)) }
    override func mouseUp(with event: NSEvent) {
        if controller?.endDrag(at: screenPoint(event)) != true { performClick(nil) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func screenPoint(_ event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
}

struct WorkspacePouchBridge: NSViewRepresentable {
    @ObservedObject var model: SpatialWorkspaceController
    let requests: ProjectEditorRequests
    let defaults: UserDefaults
    let theme: MintTheme
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
