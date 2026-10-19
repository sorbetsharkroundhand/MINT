import AppKit
import XCTest
@testable import MINTCore

@MainActor final class SpatialWorkspaceControllerTests: XCTestCase {
    func testWhisperTypingWakesAfterEightPointsOfPointerMovement() {
        let model = SpatialWorkspaceController()
        model.noteTyping(at: CGPoint(x: 100, y: 100))
        XCTAssertTrue(model.whisperTyping)
        model.notePointer(at: CGPoint(x: 107, y: 100)); XCTAssertTrue(model.whisperTyping)
        model.notePointer(at: CGPoint(x: 109, y: 100)); XCTAssertFalse(model.whisperTyping)
    }
    func testDragThresholdAndCancellationRestoreTheExactOrigin() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let a = WritingDocumentID(), b = WritingDocumentID()
        let project = project([a, b])
        let model = SpatialWorkspaceController(defaults: defaults)
        model.configure(project: project, selected: a)
        let original = model.layout
        let geometry = SpatialWorkspaceGeometry(layout: original, viewport: CGSize(width: 1200, height: 700))
        model.beginDrag(.document(a), at: CGPoint(x: 400, y: 30))
        model.updateDrag(to: CGPoint(x: 404, y: 30), geometry: geometry)
        XCTAssertFalse(model.isDragging); XCTAssertEqual(model.layout, original)
        let destination = try XCTUnwrap(geometry.tiles[.document(b)])
        model.updateDrag(to: CGPoint(x: destination.midX, y: 600), geometry: geometry)
        XCTAssertTrue(model.isDragging); XCTAssertFalse(model.layout.contains(.document(a)))
        XCTAssertNotNil(model.previewTarget)
        model.cancelDrag()
        XCTAssertFalse(model.isDragging); XCTAssertNil(model.previewTarget)
        XCTAssertEqual(model.layout, original)
    }

    func testDropCommitsOnceAndPreferencesStayProjectScoped() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let a = WritingDocumentID(), b = WritingDocumentID(), first = project([a, b])
        let model = SpatialWorkspaceController(defaults: defaults)
        model.configure(project: first, selected: a)
        let geometry = SpatialWorkspaceGeometry(layout: model.layout, viewport: CGSize(width: 1200, height: 700))
        let target = try XCTUnwrap(geometry.tiles[.document(b)])
        model.beginDrag(.document(a), at: CGPoint(x: 400, y: 30))
        model.updateDrag(to: CGPoint(x: target.midX, y: target.maxY - 10), geometry: geometry)
        model.endDrag()
        XCTAssertEqual(model.layout.columns.last?.slots.map(\.tile), [.document(b), .document(a)])
        let afterDrop = SpatialWorkspaceController(defaults: defaults)
        afterDrop.configure(project: first, selected: a)
        XCTAssertEqual(afterDrop.layout, model.layout)
        model.toggle(.characters); model.toggle(.margin)
        let saved = model.layout
        let reopened = SpatialWorkspaceController(defaults: defaults)
        reopened.configure(project: first, selected: a)
        XCTAssertEqual(reopened.layout, saved)
        reopened.configure(project: project([a]), selected: a)
        XCTAssertFalse(reopened.layout.contains(.margin))
        model.beginDrag(.document(a), at: .zero)
        model.configure(project: project([b]), selected: b)
        model.endDrag()
        XCTAssertEqual(model.layout.openDocuments, [b])
    }

    private func project(_ ids: [WritingDocumentID]) -> WritingProject {
        WritingProject(id: WritingProjectID(), title: "Spatial fixture", mode: .general,
            documents: ids.map { WritingDocument(id: $0, title: $0.rawValue.uuidString, body: "fixture", kind: .manuscript) })
    }
}
