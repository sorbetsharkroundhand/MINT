import AppKit
import XCTest
@testable import MINTCore

@MainActor final class WorkspacePouchTests: XCTestCase {
    func testAnimatedCollapseAndRestoreTravelThroughIntermediateFrames() async throws {
        let h = try await FramedWorkspaceHarness(width: 1000, reduceMotion: false)
        defer { h.close() }
        h.window.makeKeyAndOrderFront(nil)
        let editor = try await h.editor()
        h.window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 1, length: 2))
        let pouch = try XCTUnwrap(h.requests.pouch)
        let original = h.window.frame
        pouch.collapse()
        let shrinking = try XCTUnwrap(pouch.transition)
        XCTAssertFalse(h.window.isVisible)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(shrinking.frame.width, original.width * 0.03)
        XCTAssertLessThan(shrinking.frame.width, original.width)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(pouch.transition)
        XCTAssertTrue(try XCTUnwrap(pouch.panel).isVisible)
        pouch.restore()
        let expanding = try XCTUnwrap(pouch.transition)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertGreaterThan(expanding.frame.width, original.width * 0.03)
        XCTAssertLessThan(expanding.frame.width, original.width)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(pouch.transition)
        XCTAssertEqual(h.window.alphaValue, 1)
        XCTAssertTrue(h.window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 1, length: 2))
    }
    func testFourEdgesUseNativeWindowGeometryAndChangeOrientation() {
        let window = CGRect(x: 100, y: 200, width: 1000, height: 700)
        let left = WorkspacePouchGeometry.dockedFrame(window: window, edge: .left, ratio: 0.5)
        let right = WorkspacePouchGeometry.dockedFrame(window: window, edge: .right, ratio: 0.5)
        let top = WorkspacePouchGeometry.dockedFrame(window: window, edge: .top, ratio: 0.5)
        let bottom = WorkspacePouchGeometry.dockedFrame(window: window, edge: .bottom, ratio: 0.5)
        XCTAssertEqual(left.minX, 108); XCTAssertEqual(right.maxX, 1092)
        XCTAssertEqual(top.maxY, 856); XCTAssertEqual(bottom.minY, 208)
        XCTAssertEqual(left.size, CGSize(width: 38, height: 236))
        XCTAssertEqual(top.size, CGSize(width: 236, height: 38))
        XCTAssertEqual(WorkspacePouchGeometry.nearestEdge(point: CGPoint(x: 500, y: 899), window: window), .top)
        XCTAssertEqual(WorkspacePouchGeometry.nearestEdge(point: CGPoint(x: 1095, y: 500), window: window), .right)
    }

    func testOutsideDragCollapsesAndOrbRestoresTheSameNativeEditor() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = SpatialWorkspaceController(defaults: defaults)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = BlockTextView(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        editor.load(markdown: "Pouch synthetic text")
        window.contentView = editor; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 3, length: 4))
        let originalCloseAction = window.standardWindowButton(.closeButton)?.action
        let pouch = WorkspacePouchController(model: model, defaults: defaults)
        pouch.reduceMotion = true; pouch.attach(to: window)
        defer { pouch.detach(); window.contentView = nil; window.close() }
        let panel = try XCTUnwrap(pouch.panel)
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        pouch.beginDrag(at: start)
        pouch.updateDrag(to: CGPoint(x: start.x + 3, y: start.y))
        XCTAssertFalse(pouch.isDragging)
        pouch.updateDrag(to: CGPoint(x: 130, y: 500))
        XCTAssertTrue(pouch.isCollapsed); XCTAssertFalse(window.isVisible)
        _ = pouch.endDrag(at: CGPoint(x: 130, y: 500))
        XCTAssertEqual(panel.frame.size, CGSize(width: 44, height: 44))
        XCTAssertFalse(panel.hidesOnDeactivate, "The collapsed pouch must remain floating when another app is active")
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        pouch.restore()
        XCTAssertTrue(window.isVisible); XCTAssertFalse(pouch.isCollapsed)
        XCTAssertTrue(window.contentView === editor); XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 4))
        XCTAssertEqual(editor.serialize(), "Pouch synthetic text")
        pouch.detach()
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.action, originalCloseAction)
        XCTAssertNil(pouch.panel)
    }

    func testSpringSettlesWithoutOvershootAndStopsAtTheTarget() {
        var spring = WorkspaceSpringPoint(position: .zero)
        let target = CGPoint(x: 200, y: -130)
        var maximum: CGFloat = 0
        for _ in 0..<240 {
            spring.step(target: target, stiffness: 280, damping: 34, elapsed: 1 / 60)
            maximum = max(maximum, spring.position.x)
        }
        XCTAssertLessThanOrEqual(maximum, target.x + 0.001)
        XCTAssertEqual(spring.position.x, target.x, accuracy: 0.01)
        XCTAssertEqual(spring.position.y, target.y, accuracy: 0.01)
        XCTAssertTrue(spring.isSettled(at: target))
    }
}
