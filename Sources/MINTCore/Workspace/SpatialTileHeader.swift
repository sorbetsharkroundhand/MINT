import AppKit
import SwiftUI

struct SpatialHeaderAction {
    let id: String
    let label: String
    let symbol: String
    var selected = false
    let perform: () -> Void
}

struct SpatialTileHeader: NSViewRepresentable {
    let tile: WorkspaceTileID
    let title: String
    let theme: MintTheme
    var active = false
    var actions: [SpatialHeaderAction] = []

    func makeNSView(context: Context) -> SpatialTileHeaderView { SpatialTileHeaderView() }
    func updateNSView(_ view: SpatialTileHeaderView, context: Context) {
        view.tile = tile; view.title.stringValue = title; view.theme = theme; view.active = active
        view.title.textColor = active ? theme.ink : theme.ink3
        view.title.font = MintFonts.ui(11, weight: active ? .semibold : .medium)
        view.setAccessibilityIdentifier("mint.tile.header.\(tile.id)")
        view.setAccessibilityLabel(title + " — 드래그하여 배치")
        view.configure(actions); view.needsLayout = true; view.needsDisplay = true
    }
}

final class SpatialTileHeaderView: NSView {
    var tile: WorkspaceTileID = .navigator
    var theme: MintTheme = .light
    var active = false
    let title = PassthroughTitle(labelWithString: "")
    private var buttons: [NSButton] = []
    private var actions: [SpatialHeaderAction] = []
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail; title.maximumNumberOfLines = 1
        title.setAccessibilityElement(false); addSubview(title)
    }
    required init?(coder: NSCoder) { nil }
    func configure(_ actions: [SpatialHeaderAction]) {
        self.actions = actions
        while buttons.count > actions.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < actions.count {
            let button = NSButton(title: "", target: self, action: #selector(invoke(_:)))
            button.isBordered = false; button.refusesFirstResponder = true
            buttons.append(button); addSubview(button)
        }
        for (index, action) in actions.enumerated() {
            let button = buttons[index]
            button.tag = index; button.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.label)
            button.toolTip = action.label; button.setAccessibilityLabel(action.label)
            button.setAccessibilityIdentifier(action.id)
            button.contentTintColor = action.selected ? theme.blue : theme.ink3
            button.setAccessibilityValue(NSNumber(value: action.selected))
        }
    }
    @objc private func invoke(_ button: NSButton) {
        guard actions.indices.contains(button.tag) else { return }
        actions[button.tag].perform()
    }
    override func layout() {
        super.layout()
        let leading: CGFloat = tile.documentID == nil ? 12 : 24
        var x = bounds.width - 6
        for button in buttons.reversed() { x -= 26; button.frame = CGRect(x: x, y: 3, width: 26, height: 26) }
        title.frame = CGRect(x: leading, y: 8, width: max(0, x - leading - 5), height: 18)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if tile.documentID != nil {
            (active ? theme.ink.withAlphaComponent(0.75) : theme.ink3.withAlphaComponent(0.25)).setFill()
            NSBezierPath(ovalIn: CGRect(x: 12, y: 13, width: 6, height: 6)).fill()
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { canvas?.beginPanelDrag(tile, event: event) }
    override func mouseDragged(with event: NSEvent) { canvas?.continuePanelDrag(event) }
    override func mouseUp(with event: NSEvent) { canvas?.finishPanelDrag(event) }
    override func cancelOperation(_ sender: Any?) { canvas?.cancelInteraction() }
    private var canvas: SpatialWorkspaceCanvasView? { enclosingSpatialCanvas }
    final class PassthroughTitle: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension NSView {
    var enclosingSpatialCanvas: SpatialWorkspaceCanvasView? {
        var next: NSView? = self
        while let view = next {
            if let canvas = view as? SpatialWorkspaceCanvasView { return canvas }
            next = view.superview
        }
        return nil
    }
}
