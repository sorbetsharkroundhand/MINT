import AppKit
import XCTest
@testable import MINTCore

@MainActor final class WorkspaceAssistanceTests: XCTestCase {
    func testEditingDuringAStreamCancelsTheProducerAndClearsTheBusyState() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let editor = try await h.editor()
        let model = WorkspaceAssistance(session: h.fixture.session, requests: h.requests, margin: LivingMarginModel()) { _, _ in
            AskAnswerGeneration { emit in
                try emit("Partial result")
                try await Task.sleep(for: .seconds(10))
                try emit(" must never publish")
            }
        }
        try model.capture(.coauthor, editor: editor)
        let work = Task { await model.generate(prompt: "Continue") }
        for _ in 0..<100 where model.result.isEmpty { await Task.yield() }
        XCTAssertTrue(model.generating)
        h.fixture.session.updateSelectedDocumentBody("Changed original")
        XCTAssertFalse(model.generating)
        XCTAssertTrue(model.result.isEmpty)
        XCTAssertFalse(model.insert())
        model.cancel(); await work.value
    }
    func testGeneratedTextRequiresExplicitInsertAndRejectsChangedOriginal() async throws {
        let h = try await FramedWorkspaceHarness(reduceMotion: true)
        defer { h.close() }
        let editor = try await h.editor()
        let model = WorkspaceAssistance(session: h.fixture.session, requests: h.requests, margin: LivingMarginModel(), generate: { _, _ in
            AskAnswerGeneration { emit in try emit("A local continuation.") }
        })
        try model.capture(.coauthor, editor: editor)
        let before = h.fixture.session.selectedDocument?.body
        await model.generate(prompt: "Continue")
        XCTAssertEqual(model.result, "A local continuation.")
        XCTAssertEqual(h.fixture.session.selectedDocument?.body, before)
        XCTAssertTrue(model.insert())
        XCTAssertTrue(h.fixture.session.selectedDocument?.body.contains("A local continuation.") == true)
        try model.capture(.coauthor, editor: editor)
        await model.generate(prompt: "Continue")
        h.fixture.session.updateSelectedDocumentBody("Changed while reading result")
        XCTAssertFalse(model.insert())
        XCTAssertEqual(h.fixture.session.selectedDocument?.body, "Changed while reading result")
    }

    func testUnavailableLocalModelLeavesOriginalUntouchedAndExcerptPreservesSource() async throws {
        let h = try await FramedWorkspaceHarness(reduceMotion: true)
        defer { h.close() }
        h.fixture.session.updateSelectedDocumentBody("Before **한글🙂** after")
        let editor = try await h.editor()
        editor.setSelectedRange((editor.string as NSString).range(of: "한글🙂"))
        let before = h.fixture.session.selectedDocument?.body
        let model = WorkspaceAssistance(session: h.fixture.session, requests: h.requests, margin: LivingMarginModel(), generate: { _, _ in
            throw CompletionEngine.ReadyInstructionError.modelUnavailable
        })
        try model.capture(.polish, editor: editor)
        await model.generate(prompt: "")
        XCTAssertFalse(model.errorMessage?.isEmpty ?? true)
        XCTAssertEqual(h.fixture.session.selectedDocument?.body, before)
        let note = try model.excerpt(editor: editor)
        XCTAssertTrue(h.fixture.session.document(note)?.body.contains("**한글🙂**") == true)
        XCTAssertEqual(h.fixture.session.document(editor.writingDocumentIdentity!.documentID)?.body, before)
        await h.layout()
        let noteEditor = try await h.editor()
        XCTAssertEqual(noteEditor.writingDocumentIdentity?.documentID, note)
        XCTAssertEqual((noteEditor.string as NSString).substring(with: noteEditor.selectedRange()), "한글🙂")
    }
    func testSourceABACannotReviveACompletedResult() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let editor = try await h.editor()
        let model = WorkspaceAssistance(session: h.fixture.session, requests: h.requests, margin: LivingMarginModel()) { _, _ in
            AskAnswerGeneration { emit in try emit("Proposed continuation") }
        }
        try model.capture(.coauthor, editor: editor); await model.generate(prompt: "Continue")
        let before = try XCTUnwrap(h.fixture.session.selectedDocument?.body)
        h.fixture.session.updateSelectedDocumentBody(before + "!")
        h.fixture.session.updateSelectedDocumentBody(before)
        XCTAssertFalse(model.insert())
        XCTAssertEqual(h.fixture.session.selectedDocument?.body, before)
        XCTAssertTrue(model.result.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }
    func testExplicitCoauthorReadsTheDocumentAndAppendsAfterItsEnd() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        h.fixture.session.updateSelectedDocumentBody("First paragraph.\n\nLast paragraph.")
        let editor = try await h.editor()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        var suppliedContext = ""
        let model = WorkspaceAssistance(session: h.fixture.session, requests: h.requests, margin: LivingMarginModel()) { _, prompt in
            suppliedContext = prompt
            return AskAnswerGeneration { emit in try emit("Next paragraph.") }
        }
        try model.capture(.coauthor, editor: editor); await model.generate(prompt: "Continue")
        XCTAssertTrue(suppliedContext.contains("First paragraph.\n\nLast paragraph."))
        XCTAssertTrue(model.insert())
        XCTAssertEqual(h.fixture.session.selectedDocument?.body, "First paragraph.\n\nLast paragraph.\n\nNext paragraph.")
    }
}
