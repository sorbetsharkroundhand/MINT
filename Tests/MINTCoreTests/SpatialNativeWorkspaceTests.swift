import AppKit
import XCTest
@testable import MINTCore

@MainActor final class SpatialNativeWorkspaceTests: XCTestCase {
    func testNavigatorNativeDragReordersWithoutReplacingOrClosingEditors() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        let a = try XCTUnwrap(h.fixture.session.selectedDocumentID)
        let b = try XCTUnwrap(h.fixture.session.createDocument(title: "Move before first"))
        await h.layout()
        let before = allEditors(h.host)
        let source = try XCTUnwrap(h.element("mint.navigator.drag.\(b.rawValue.uuidString)") as? NSView)
        let target = try XCTUnwrap(h.element("mint.navigator.drag.\(a.rawValue.uuidString)") as? NSView)
        func event(_ type: NSEvent.EventType, location: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 1,
                windowNumber: h.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        source.mouseDown(with: try event(.leftMouseDown, location: source.convert(CGPoint(x: 50, y: source.bounds.midY), to: nil)))
        source.mouseDragged(with: try event(.leftMouseDragged, location: target.convert(CGPoint(x: 50, y: 1), to: nil)))
        source.mouseUp(with: try event(.leftMouseUp, location: target.convert(CGPoint(x: 50, y: 1), to: nil)))
        await h.layout()
        XCTAssertEqual(h.fixture.session.activeProject?.documents.map(\.id), [b, a])
        XCTAssertEqual(allEditors(h.host).count, 2)
        for editor in before { XCTAssertTrue(allEditors(h.host).contains { $0 === editor }) }
    }

    func testNativeDividersResizeColumnsAndAdjacentRows() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        let a = try XCTUnwrap(h.fixture.session.selectedDocumentID)
        let b = try XCTUnwrap(h.fixture.session.createDocument(title: "Lower"))
        await h.layout()
        let canvas = try XCTUnwrap(descendant(h.host, SpatialWorkspaceCanvasView.self))
        let model = try XCTUnwrap(canvas.model)
        var stacked = model.layout; stacked.move(.document(b), to: .below(.document(a)))
        model.setLayout(stacked); await h.layout()
        let column = try XCTUnwrap(h.element("mint.tile.column-resize.0") as? NSView)
        func event(_ type: NSEvent.EventType, _ view: NSView, _ offset: CGPoint, clicks: Int = 1) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(offset, to: nil), modifierFlags: [],
                timestamp: 1, windowNumber: h.window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1))
        }
        column.mouseDown(with: try event(.leftMouseDown, column, .zero))
        column.mouseDragged(with: try event(.leftMouseDragged, column, CGPoint(x: 80, y: 0)))
        column.mouseUp(with: try event(.leftMouseUp, column, .zero)); await h.layout()
        XCTAssertEqual(model.layout.columns[0].width, 284)
        let row = try XCTUnwrap(h.element("mint.tile.row-resize.1.0") as? NSView)
        row.mouseDown(with: try event(.leftMouseDown, row, .zero))
        row.mouseDragged(with: try event(.leftMouseDragged, row, CGPoint(x: 0, y: 10_000)))
        row.mouseUp(with: try event(.leftMouseUp, row, .zero)); await h.layout()
        XCTAssertEqual(model.layout.columns[1].slots[0].weight, 0.8, accuracy: 0.001)
        row.mouseDown(with: try event(.leftMouseDown, row, .zero, clicks: 2)); await h.layout()
        XCTAssertEqual(model.layout.columns[1].slots.map(\.weight), [0.5, 0.5])
    }

    func testNativeHeaderDragStacksTilesAndEscapeRestoresExactOrigin() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        let a = try XCTUnwrap(h.fixture.session.selectedDocumentID)
        let b = try XCTUnwrap(h.fixture.session.createDocument(title: "Target"))
        await h.layout()
        let canvas = try XCTUnwrap(descendant(h.host, SpatialWorkspaceCanvasView.self))
        let model = try XCTUnwrap(canvas.model)
        let header = try XCTUnwrap(h.element("mint.tile.header.document.\(a.rawValue.uuidString)") as? NSView)
        let source = try XCTUnwrap(canvas.geometry.tiles[.document(a)])
        let destination = try XCTUnwrap(canvas.geometry.tiles[.document(b)])
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                modifierFlags: [], timestamp: 1, windowNumber: h.window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let origin = model.layout
        header.mouseDown(with: try event(.leftMouseDown, CGPoint(x: source.midX, y: source.minY + 12)))
        header.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: destination.midX, y: destination.minY + 10)))
        XCTAssertTrue(model.isDragging)
        XCTAssertEqual(model.previewTarget, .above(.document(b)))
        header.cancelOperation(nil)
        XCTAssertEqual(model.layout, origin)
        header.mouseDown(with: try event(.leftMouseDown, CGPoint(x: source.midX, y: source.minY + 12)))
        header.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: destination.midX, y: destination.minY + 10)))
        header.mouseUp(with: try event(.leftMouseUp, CGPoint(x: destination.midX, y: destination.minY + 10)))
        await h.layout()
        XCTAssertEqual(model.layout.columns.last?.slots.map(\.tile), [.document(a), .document(b)])
        XCTAssertEqual(allEditors(h.host).count, 2)
    }

    func testMultipleLiveEditorsKeepIndependentUndoAndCompositionWhileTilesMove() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        let a = try XCTUnwrap(h.fixture.session.selectedDocumentID)
        let b = try XCTUnwrap(h.fixture.session.createDocument(title: "Second live tile"))
        await h.layout()
        let editors = allEditors(h.host)
        XCTAssertEqual(editors.count, 2, "The executable HTML requires simultaneous native editors")
        let aEditor = try XCTUnwrap(editors.first { $0.writingDocumentIdentity?.documentID == a })
        let bEditor = try XCTUnwrap(editors.first { $0.writingDocumentIdentity?.documentID == b })
        XCTAssertFalse(aEditor === bEditor)
        XCTAssertFalse(aEditor.undoManager === bEditor.undoManager)
        h.window.makeFirstResponder(bEditor)
        bEditor.insertText("Second body", replacementRange: NSRange(location: 0, length: 0))
        h.window.makeFirstResponder(aEditor)
        aEditor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 0))
        let before = aEditor.string, selection = aEditor.selectedRange()
        let canvas = try XCTUnwrap(descendant(h.host, SpatialWorkspaceCanvasView.self))
        let model = try XCTUnwrap(canvas.model)
        var moved = model.layout
        moved.move(.document(a), to: .above(.document(b)))
        model.setLayout(moved); await h.layout()
        h.window.setContentSize(CGSize(width: 900, height: 650)); await h.layout()
        XCTAssertTrue(allEditors(h.host).contains { $0 === aEditor })
        XCTAssertTrue(aEditor.hasMarkedText()); XCTAssertEqual(aEditor.string, before)
        XCTAssertEqual(aEditor.selectedRange(), selection)
        XCTAssertTrue(h.window.firstResponder === aEditor)
        XCTAssertEqual(h.fixture.session.document(b)?.body, "Second body")
        aEditor.unmarkText(); aEditor.didChangeText()
    }

    private func allEditors(_ root: NSView) -> [BlockTextView] {
        (root as? BlockTextView).map { [$0] } ?? root.subviews.flatMap(allEditors)
    }
    private func descendant<T: NSView>(_ root: NSView, _ type: T.Type) -> T? {
        (root as? T) ?? root.subviews.compactMap { descendant($0, type) }.first
    }
}
