import AppKit

enum SpatialResizeAxis: Equatable {
    case column(Int)
    case row(Int, Int)
}

final class SpatialResizeHandle: NSView {
    weak var canvas: SpatialWorkspaceCanvasView?
    var axis: SpatialResizeAxis = .column(0)
    var theme: MintTheme = .light
    private var hovered = false
    private var area: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityPerformIncrement() -> Bool { adjust(1) }
    override func accessibilityPerformDecrement() -> Bool { adjust(-1) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 124 || event.keyCode == 125 { _ = adjust(1) }
        else if event.keyCode == 123 || event.keyCode == 126 { _ = adjust(-1) }
        else { super.keyDown(with: event) }
    }
    private func adjust(_ direction: Double) -> Bool {
        guard let canvas, let model = canvas.model, !model.isDragging else { return false }
        var layout = model.layout
        switch axis {
        case .column(let left):
            guard layout.columns.indices.contains(left + 1) else { return false }
            let rightFixed = layout.columns[left].width == nil && layout.columns[left + 1].width != nil
            let index = rightFixed ? left + 1 : left
            layout.setColumnWidth(index, width: (layout.columns[index].width ?? canvas.geometry.columns[index].width) + 16 * direction * (rightFixed ? -1 : 1))
        case .row(let column, let row):
            guard canvas.geometry.columns.indices.contains(column) else { return false }
            let height = canvas.geometry.columns[column].height
            layout.resizeRows(column: column, row: row, delta: height * 0.05 * direction, height: height)
        }
        model.setLayout(layout); canvas.layoutTiles(); return true
    }
    override func resetCursorRects() {
        let cursor: NSCursor
        if case .column = axis { cursor = .resizeLeftRight } else { cursor = .resizeUpDown }
        addCursorRect(bounds, cursor: cursor)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area); self.area = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard hovered else { return }
        theme.ink2.setFill()
        let rect: CGRect
        if case .column = axis { rect = CGRect(x: bounds.midX - 1, y: bounds.midY - 21, width: 2, height: 42) }
        else { rect = CGRect(x: bounds.midX - 21, y: bounds.midY - 1, width: 42, height: 2) }
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, case .row(let column, let row) = axis, let model = canvas?.model {
            var layout = model.layout; layout.equalizeRows(column: column, row: row); model.setLayout(layout)
            canvas?.layoutTiles(); return
        }
        canvas?.beginResize(axis, event: event)
    }
    override func mouseDragged(with event: NSEvent) { canvas?.continueResize(event) }
    override func mouseUp(with event: NSEvent) { canvas?.finishResize() }
    override func cancelOperation(_ sender: Any?) { canvas?.cancelInteraction() }
}
