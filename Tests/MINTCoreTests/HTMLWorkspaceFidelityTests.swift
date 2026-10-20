import AppKit
import XCTest
@testable import MINTCore

@MainActor final class HTMLWorkspaceFidelityTests: XCTestCase {
    func testSelectionToolbarFloatsAboveTileClippingAndKeepsEditorFocus() async throws {
        let h = try await FramedWorkspaceHarness(width: 860, reduceMotion: true)
        defer { h.close() }
        h.window.makeKeyAndOrderFront(nil)
        h.fixture.session.updateSelectedDocumentBody("서식을 적용할 문장.")
        let editor = try await h.editor(); h.window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 3)); editor.updateSelectionToolbar()
        try await Task.sleep(for: .milliseconds(300))
        let panel = try XCTUnwrap(editor.workspaceSelectionPanel)
        XCTAssertTrue(panel.parent === h.window)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertTrue(h.window.firstResponder === editor)
        editor.hideSelectionToolbar()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(editor.workspaceSelectionPanel)
    }
    func testSecondaryMenuKeepsModesAndAIStateAccessible() async throws {
        let h = try await FramedWorkspaceHarness(mode: .fiction); defer { h.close() }
        let pouch = try XCTUnwrap(h.requests.pouch)
        let menu = pouch.moreMenu()
        XCTAssertTrue(menu.items.contains { $0.accessibilityIdentifier() == "mint.workspace.mode.map" })
        let write = try XCTUnwrap(menu.items.first { $0.accessibilityIdentifier() == "mint.workspace.mode.write" })
        XCTAssertEqual(write.state, .on)
        let ai = try XCTUnwrap(menu.items.first { $0.accessibilityIdentifier() == "mint.workspace.autocomplete" })
        XCTAssertEqual(ai.title, "자동완성 꺼짐")
        XCTAssertEqual(ai.state, .off)
        let details = try XCTUnwrap(menu.items.firstIndex { $0.accessibilityIdentifier() == "mint.workspace.more.characters" })
        menu.performActionForItem(at: details); await h.layout()
        XCTAssertTrue(h.requests.spatialWorkspace?.writerDetailsVisible == true)
    }
    func testDocumentHeaderExposesTheSourceTextControls() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        let id = try XCTUnwrap(h.fixture.session.selectedDocumentID).rawValue.uuidString
        let typewriter = try XCTUnwrap(h.element("mint.tile.typewriter.\(id)") as? NSButton)
        let focus = try XCTUnwrap(h.element("mint.tile.focus.\(id)") as? NSButton)
        let continuation = try XCTUnwrap(h.element("mint.tile.continue.\(id)") as? NSButton)
        XCTAssertEqual(typewriter.title, "타자기")
        XCTAssertEqual(focus.title, "집중")
        XCTAssertEqual(continuation.title, "이어쓰기")
    }

    func testPaletteShowsCategoryTitleAndDetailWithoutNativeWindowChrome() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        let editor = try await h.editor(); h.window.makeFirstResponder(editor)
        let panel = try XCTUnwrap(WorkspaceQuickCommandPanel.present(session: h.fixture.session, requests: h.requests, theme: .light, toggleTheme: {}))
        defer { panel.close() }
        await h.layout()
        let window = try XCTUnwrap(panel.window)
        XCTAssertFalse(window.styleMask.contains(.titled))
        let labels = descendants(try XCTUnwrap(window.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains("현재 문단을 화면 눈높이 중앙에 유지"), "Result descriptions must be visible, not only searchable")
        XCTAssertTrue(labels.contains("명령"))
        XCTAssertTrue(labels.contains("ESC"))
    }

    func testWorkspaceSubtitleUsesSourceScaleAndMutedInk() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true)
        defer { h.close() }
        h.fixture.session.updateSelectedDocumentBody("# 제목\n\n## 부제\n\n원고 본문")
        await h.layout()
        let editor = try await h.editor()
        let attrs = editor.styleAttributes(for: .h2, checked: false)
        XCTAssertEqual(try XCTUnwrap(attrs[.font] as? NSFont).pointSize, editor.baseFontSize * 1.12, accuracy: 0.01)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, editor.palette.workspaceMuted)
    }

    private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }

    func testCharacterCardsRemainVisibleWhenAnotherDocumentIsActive() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: true, mode: .fiction)
        defer { h.close() }
        h.window.makeKeyAndOrderFront(nil)
        let card = CharacterCard(name: "도경", aliases: "등대지기", note: "면장갑을 낀다.")
        try ProjectWriterEditing.perform(.character(card), in: h.fixture.session, identity: XCTUnwrap(h.fixture.session.runtimeIdentity))
        _ = h.fixture.session.createDocument(title: "다른 문서")
        await h.layout()
        h.requests.spatialWorkspace?.toggle(.characters); await h.layout()
        try await Task.sleep(for: .milliseconds(400)); h.host.displayIfNeeded(); await h.layout()
        XCTAssertNotNil(h.element("mint.card.\(card.id.uuidString)"), "Visible elements: \(h.elements().map { ($0.accessibilityIdentifier() ?? "") + ":" + ($0.accessibilityLabel() ?? "") }.joined(separator: " | "))")
    }

    func testOldCharacterDataDecodesWithoutNewEditorialFields() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","name":"도경","aliases":"","note":"원래 기록"}"#
        let card = try JSONDecoder().decode(CharacterCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.note, "원래 기록"); XCTAssertNil(card.role); XCTAssertNil(card.traits)
    }

    func testOpeningAToolProportionsNeighborFramesOverTime() async throws {
        let h = try await FramedWorkspaceHarness(width: 1440, reduceMotion: false)
        defer { h.close() }
        h.window.makeKeyAndOrderFront(nil)
        let model = try XCTUnwrap(h.requests.spatialWorkspace)
        let canvas = try XCTUnwrap(descendants(h.host).compactMap { $0 as? SpatialWorkspaceCanvasView }.first)
        let id = try XCTUnwrap(h.fixture.session.selectedDocumentID)
        let host = try XCTUnwrap(canvas.hosts[.document(id)])
        let original = host.frame
        let originalEditor = try await h.editor()
        model.toggle(.characters); await h.layout()
        let destination = try XCTUnwrap(canvas.geometry.tiles[.document(id)])
        XCTAssertLessThan(destination.width, original.width)
        XCTAssertGreaterThan(host.frame.width, destination.width + 1, "Opening must animate the neighboring document instead of teleporting")
        try await Task.sleep(for: .milliseconds(400)); await h.layout()
        XCTAssertEqual(host.frame.width, destination.width, accuracy: 1)
        let retained = try await h.editor()
        XCTAssertTrue(retained === originalEditor)
    }
}
