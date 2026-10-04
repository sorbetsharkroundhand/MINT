import AppKit
import SwiftUI
import XCTest
@testable import MINTCore

@MainActor
final class WriterCompatibilityTests: XCTestCase {
    func testToolbarExposesAccessibleSearchAndCompatibilityMenuInGeneral() async throws {
        let h = try await SourceNavigationHarness(short: true); defer { h.close() }
        let host = NSHostingView(rootView: EditorToolbar(projectSession: h.fixture.session,
            editorRequests: h.requests, completion: h.completion, settings: h.completion.settings,
            theme: .light).defaultAppStorage(h.fixture.defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 52),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        func elements(_ value: Any, depth: Int = 0) -> [any NSAccessibilityProtocol] {
            guard depth < 20, let node = value as? any NSAccessibilityProtocol else { return [] }
            let children = (node.accessibilityChildren() ?? []) + ((value as? NSView)?.subviews ?? [])
            return [node] + children.flatMap { elements($0, depth: depth + 1) }
        }
        let controls = elements(window)
        let search = try XCTUnwrap(controls.first { $0.accessibilityIdentifier() == "mint.source-search.show" })
        let compatibility = try XCTUnwrap(controls.first { $0.accessibilityIdentifier() == "mint.writer-tools.compatibility" })
        XCTAssertEqual(search.accessibilityLabel(), "원문 검색")
        XCTAssertEqual(compatibility.accessibilityLabel(), "저장된 설정과 기록")
        XCTAssertFalse(controls.contains { $0.accessibilityLabel() == "리빙 마진" })
        let menu = try XCTUnwrap((compatibility as? NSPopUpButton)?.menu)
        XCTAssertEqual(menu.items.dropFirst().map(\.title), ["인물과 작품 정보", "작가 수정과 기록", "제안에 쓰인 내용"])
        XCTAssertNotNil(menu.items.first?.image)
        XCTAssertTrue(try XCTUnwrap(search as? NSButton).refusesFirstResponder)
        XCTAssertTrue(window.makeFirstResponder(try XCTUnwrap(compatibility as? NSPopUpButton)),
            "The compatibility route must support native keyboard focus")
        let view = try await h.editor(), before = h.fixture.session.activeProject
        view.setSelectedRange(NSRange(location: 3, length: 4))
        let selection = view.selectedRange()
        for (item, target) in zip(menu.items.dropFirst(), [SidebarSection.bible, .narrative, .context]) {
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
            await h.layout()
            XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.sidebarSection"), target.rawValue)
            XCTAssertEqual(view.selectedRange(), selection)
            XCTAssertEqual(h.fixture.session.activeProject, before)
        }
        window.setContentSize(NSSize(width: 420, height: 52))
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertEqual((search as? NSButton)?.title, "")
        _ = search.accessibilityPerformPress()
        await h.layout()
        let panel = try XCTUnwrap(NSApp.windows.first { $0.title == "원문 검색" && $0.isVisible })
        panel.performClose(nil); await h.layout()
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(h.fixture.session.activeProject, before)
        XCTAssertTrue(h.window.firstResponder === view)
    }

    func testGeneralStillShowsExistingGenreAndCharacterFieldsWithoutChangingUserData() async throws {
        let h = try await SourceNavigationHarness(short: true); defer { h.close() }
        let identity = try XCTUnwrap(h.fixture.session.runtimeIdentity)
        let writer = WriterDocumentData(documentID: identity.key.documentID, genre: "Saved genre",
            characters: [CharacterCard(name: "미나", aliases: "민아", note: "Saved decisions")])
        let bytes = try writer.encoded()
        try h.fixture.session.updateUserData(bytes, for: WriterDocumentData.key(for: writer.documentID), identity: identity)
        let before = h.fixture.session.activeProject
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ProjectWriterToolsView(session: h.fixture.session,
            completion: h.completion, editorRequests: h.requests, section: .bible, theme: .light))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<20 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        func fields(_ view: NSView) -> [String] {
            (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(fields)
        }
        let visible = fields(host)
        XCTAssertTrue(visible.contains("Saved genre"), "Existing genre must remain editable in the compatibility route")
        XCTAssertTrue(visible.contains("미나"), "Existing character must remain reachable after switching to General")
        XCTAssertEqual(h.fixture.session.activeProject, before)
        XCTAssertEqual(h.fixture.session.selectedDocumentSnapshot?.userData[WriterDocumentData.key(for: writer.documentID)], bytes)
    }
}
