import AppKit
import SwiftUI

final class WorkspacePouchView: NSView {
    weak var controller: WorkspacePouchController?
    private let grip = WorkspacePouchButton(title: "", target: nil, action: nil)
    private var buttons: [WorkspacePouchButton] = []
    private var actions: [WorkspacePouchAction] = []
    private var orb = false, horizontal = false
    private var theme: MintTheme = .light
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        grip.target = self; grip.action = #selector(activateGrip)
        grip.isBordered = false; grip.refusesFirstResponder = false
        addSubview(grip)
    }
    required init?(coder: NSCoder) { nil }

    func configure(orb: Bool, horizontal: Bool, actions: [WorkspacePouchAction], theme: MintTheme) {
        self.orb = orb; self.horizontal = horizontal; self.actions = actions; self.theme = theme
        grip.controller = controller
        grip.title = orb ? "M" : ""
        grip.font = MintFonts.serif(14, weight: .bold); grip.contentTintColor = theme.blue
        grip.setAccessibilityIdentifier(orb ? "mint.workspace.pouch.restore" : "mint.writer-tools.compatibility")
        grip.setAccessibilityLabel(orb ? "MINT 전체 창 펼치기" : "도구 더 보기 · 드래그하여 주머니 이동")
        grip.menu = controller?.moreMenu()
        while buttons.count > actions.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < actions.count {
            let button = WorkspacePouchButton(title: "", target: self, action: #selector(invoke(_:)))
            button.isBordered = false; button.refusesFirstResponder = true; button.wantsLayer = true
            buttons.append(button); addSubview(button)
        }
        for (index, action) in actions.enumerated() {
            let button = buttons[index]; button.controller = controller; button.tag = index; button.isHidden = orb
            button.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.label)
            let selected = action.selected()
            button.setButtonType(.toggle); button.state = selected ? .on : .off
            button.isEnabled = action.enabled()
            button.contentTintColor = selected ? theme.blue : theme.ink2
            button.layer?.backgroundColor = (selected ? theme.activeBg : NSColor.clear).cgColor
            button.layer?.cornerRadius = MintRadius.sm
            button.setAccessibilityIdentifier(action.id); button.setAccessibilityLabel(action.label)
            button.setAccessibilityValue(NSNumber(value: selected)); button.toolTip = action.label
        }
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        if orb { grip.frame = bounds; return }
        grip.frame = horizontal ? CGRect(x: 4, y: 5, width: 12, height: 28) : CGRect(x: 5, y: 3, width: 28, height: 12)
        var position: CGFloat = 18
        for (index, button) in buttons.enumerated() {
            if index == 4 { position += 12 }
            button.frame = horizontal ? CGRect(x: position - 2, y: 3, width: 32, height: 32)
                : CGRect(x: 3, y: position - 2, width: 32, height: 32)
            position += 32
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        (controller?.reduceTransparency == true ? theme.pill.withAlphaComponent(1) : theme.pill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: orb ? 14 : 12, yRadius: orb ? 14 : 12).fill()
        guard !orb else { return }
        theme.ink3.withAlphaComponent(0.35).setFill()
        let gripRect = horizontal ? CGRect(x: 8, y: 12, width: 3, height: 14) : CGRect(x: 12, y: 7, width: 14, height: 3)
        NSBezierPath(roundedRect: gripRect, xRadius: 1.5, yRadius: 1.5).fill()
        theme.sepStrong.setFill()
        if horizontal { CGRect(x: 151, y: 11, width: 1, height: 16).fill() }
        else { CGRect(x: 11, y: 151, width: 16, height: 1).fill() }
    }
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

final class WorkspacePouchButton: NSButton {
    weak var controller: WorkspacePouchController?
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
        let view = Probe(); view.controller = context.coordinator.controller; return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        let controller = context.coordinator.controller
        controller.reduceMotion = systemReduceMotion || accessibilityOptions.reduceMotion
        controller.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || accessibilityOptions.reduceTransparency
        controller.theme = theme; controller.actions = actions; controller.extraActions = extraActions
        requests.pouch = controller
        if let window = view.window { controller.attach(to: window) }
    }
    static func dismantleNSView(_ view: Probe, coordinator: Coordinator) { coordinator.controller.detach() }
    @MainActor final class Coordinator {
        let controller: WorkspacePouchController
        init(model: SpatialWorkspaceController, defaults: UserDefaults) { controller = WorkspacePouchController(model: model, defaults: defaults) }
    }
    final class Probe: NSView {
        weak var controller: WorkspacePouchController?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { controller?.attach(to: window) }
            else { controller?.detach() }
        }
    }
}
