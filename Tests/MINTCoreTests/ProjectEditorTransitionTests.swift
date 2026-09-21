import AppKit
import SwiftUI
import XCTest
@testable import MINTCore

@MainActor
final class ProjectEditorTransitionTests: XCTestCase {
    // Exercises the real ContentView callback and EditorPane binding while durable I/O is held.
    func testProjectSaveCommitsIMEAndFencesNativeEditorUntilFailedSaveRestoresIt() async throws {
        try await verifyProjectTransition(fails: true, suspending: false)
    }

    func testSuccessfulProjectTerminationKeepsEditorFencedAndPersistsCommittedIME() async throws {
        try await verifyProjectTransition(fails: false, suspending: false)
    }

    func testFailedProjectSuspensionRestoresNativeEditingAndAcceptedIME() async throws {
        try await verifyProjectTransition(fails: true, suspending: true)
    }

    private func verifyProjectTransition(fails: Bool, suspending: Bool) async throws {
        let fixture = try await LegacyBoundaryFixture()
        defer { fixture.cleanUp() }
        let writing = expectation(description: "Real project save is suspended")
        let files = SuspendedEditorProjectFiles(fails: fails, started: { writing.fulfill() })
        defer { files.release() }
        let store = ProjectStore(root: fixture.root.appendingPathComponent("Projects"), fileSystem: files)
        let session = ProjectSession(store: store, defaults: fixture.defaults, autosaveDelay: .seconds(3600))
        try await session.bootstrap()
        let settings = CompletionSettings(defaults: fixture.defaults)
        let completion = CompletionController(settings: settings)
        let indexer = BackgroundIndexer(engine: CompletionEngine(), settings: settings)
        let requests = ProjectEditorRequests()
        let window = LegacyUndoWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.testUndo.groupsByEvent = false
        let host = NSHostingView(rootView: ContentView(projectSession: session,
            legacyWorkspace: LegacyWorkspaceController(session: session), editorRequests: requests,
            completion: completion, indexer: indexer, livingMargin: LivingMarginModel(),
            firstRunFlow: FirstRunFlow(session: session, store: store, editorRequests: requests)))
        window.contentView = host
        defer {
            window.testUndo.removeAllActions()
            window.contentView = nil
            window.close()
            completion.shutdown()
            indexer.shutdown()
        }
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        let editor = try XCTUnwrap(findEditor(host))
        window.makeFirstResponder(editor)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(editor.isEditable, "Ordinary ready project editing must remain enabled")
        let manager = try XCTUnwrap(editor.undoManager)
        manager.beginUndoGrouping()
        editor.insertText("!", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        manager.endUndoGrouping()
        XCTAssertEqual(session.selectedDocument?.body, "original project!")
        manager.beginUndoGrouping()
        editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        let accepted = editor.serialize()
        let selection = editor.selectedRange()
        let transition = try XCTUnwrap(session.willTransition)
        session.willTransition = {
            transition()
            XCTAssertEqual(session.selectedDocument?.body, accepted, "IME must publish before mutation acceptance closes")
            XCTAssertFalse(editor.isEditable, "Fence must close synchronously before any save await")
        }
        let save = Task {
            if suspending { try await session.suspend() }
            else { try await session.flushForTermination() }
        }
        await fulfillment(of: [writing], timeout: 3)
        manager.endUndoGrouping()
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertFalse(editor.isEditable)
        for _ in 0..<5 { requests.focusEditor(); host.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertFalse(editor.isEditable, "SwiftUI must not reopen the editor while persistence is pending")
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertTrue(window.firstResponder === editor)
        files.release()
        do {
            try await save.value
            XCTAssertFalse(fails, "Expected injected durable write failure")
        } catch {
            XCTAssertTrue(fails, "Unexpected save error: \(error)")
        }
        for _ in 0..<5 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertEqual(editor.isEditable, fails)
        XCTAssertEqual(editor.serialize(), accepted)
        XCTAssertEqual(session.selectedDocument?.body, accepted)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(manager.canUndo)
        if fails {
            manager.undo()
            XCTAssertEqual(session.selectedDocument?.body, editor.serialize())
            XCTAssertEqual(editor.serialize(), "original project!")
        } else {
            let durable = try await store.activeProject()
            XCTAssertEqual(durable?.documents[0].body, accepted)
        }
    }

    private func findEditor(_ view: NSView) -> BlockTextView? {
        if let editor = view as? BlockTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor($0) }.first
    }
}

private final class SuspendedEditorProjectFiles: ProjectFileSystem, @unchecked Sendable {
    private let real = LocalProjectFileSystem()
    private let condition = NSCondition()
    private var released = false
    private let fails: Bool
    private let started: @Sendable () -> Void

    init(fails: Bool, started: @escaping @Sendable () -> Void) {
        self.fails = fails
        self.started = started
    }
    func createDirectory(at url: URL) throws { try real.createDirectory(at: url) }
    func read(_ url: URL) throws -> Data { try real.read(url) }
    func fileExists(at url: URL) -> Bool { real.fileExists(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws {
        guard url.path.contains("/Documents/") else { return try real.writeAtomically(data, to: url) }
        condition.lock()
        started()
        while !released { condition.wait() }
        condition.unlock()
        if fails { throw CocoaError(.fileWriteNoPermission) }
        try real.writeAtomically(data, to: url)
    }
    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
