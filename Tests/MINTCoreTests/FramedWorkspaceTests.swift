import AppKit
import SwiftUI
import XCTest
@testable import MINTCore

@MainActor
final class FramedWorkspaceTests: XCTestCase {
    func testFrameAndWindowTitleHaveSeparateSafeGeometry() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        var project = try XCTUnwrap(h.fixture.session.activeProject)
        project.title = String(repeating: "Long project title ", count: 30)
        try await h.fixture.session.saveAndActivate(project); await h.layout()
        let frame = try XCTUnwrap(h.element("mint.workspace.frame") as? NSView)
        let chrome = try XCTUnwrap(h.element("mint.workspace.chrome") as? NSView)
        let title = try XCTUnwrap(h.element("mint.workspace.chrome.title") as? NSTextField)
        XCTAssertEqual(chrome.bounds.height, 52, accuracy: 0.5)
        XCTAssertEqual(frame.layer?.backgroundColor?.alpha, 1)
        XCTAssertEqual(frame.layer?.cornerRadius, 12)
        XCTAssertEqual(frame.layer?.masksToBounds, false, "Decoration must not clip editor transients")
        XCTAssertTrue(chrome.mouseDownCanMoveWindow)
        XCTAssertEqual(title.stringValue, project.title)
        let buttonsMaxX = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { h.window.standardWindowButton($0) }
            .map { $0.convert($0.bounds, to: nil).maxX }.max() ?? 0
        let titleRect = title.convert(title.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(titleRect.minX, buttonsMaxX + 12)
        XCTAssertLessThanOrEqual(titleRect.maxX, chrome.convert(chrome.bounds, to: nil).maxX)
        XCTAssertEqual(title.maximumNumberOfLines, 1)
        XCTAssertEqual(title.lineBreakMode, .byTruncatingMiddle)
    }

    func testNavigatorLocalCloseReturnsToEditor() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let editor = try await h.editor()
        editor.setSelectedRange(NSRange(location: 3, length: 4))
        let before = h.fixture.session.activeProject
        let close = try XCTUnwrap(h.element("mint.navigator.close") as? NSButton)
        XCTAssertGreaterThanOrEqual(close.bounds.width, 32)
        XCTAssertGreaterThanOrEqual(close.bounds.height, 32)
        XCTAssertEqual(close.accessibilityLabel(), "파일 목록 숨기기")
        close.performClick(nil); await h.layout()
        XCTAssertFalse(h.fixture.defaults.bool(forKey: "mint.sidebarVisible"))
        XCTAssertTrue(h.window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 4))
        XCTAssertEqual(h.fixture.session.activeProject, before)
    }

    func testSavedToolChoiceSurvivesWorkspaceAppearance() async throws {
        for section in ["bible", "timeline", "context"] {
            let h = try await FramedWorkspaceHarness(presentationDefaults: ["mint.sidebarSection": section])
            defer { h.close() }
            let project = h.initialProject
            let selected = h.initialDocumentID
            await h.layout()
            XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.sidebarSection"), section)
            let editor = try await h.editor()
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, 569, accuracy: 1,
                "The saved tool must reserve its visible side pane")
            XCTAssertEqual(h.fixture.session.activeProject, project)
            XCTAssertEqual(h.fixture.session.selectedDocumentID, selected)
        }
    }

    func testUnknownAndDeferredToolChoicesRemainStoredAndQuiet() async throws {
        for section in ["margin", "unknown"] {
            let h = try await FramedWorkspaceHarness(presentationDefaults: ["mint.sidebarSection": section])
            defer { h.close() }
            let project = h.initialProject
            let selected = h.initialDocumentID
            await h.layout()
            XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.sidebarSection"), section)
            let editor = try await h.editor()
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, 910, accuracy: 1,
                "Deferred and unknown tools must leave all writing space available")
            XCTAssertEqual(h.fixture.session.activeProject, project)
            XCTAssertEqual(h.fixture.session.selectedDocumentID, selected)
        }
    }
}

/// Hosts only a synthetic project; never launches the MINT application.
@MainActor
final class FramedWorkspaceHarness {
    let fixture: LegacyBoundaryFixture
    let requests = ProjectEditorRequests()
    let initialProject: WritingProject?
    let initialDocumentID: WritingDocumentID?
    let window: LegacyUndoWindow
    let host: NSView
    let completion: CompletionController
    let indexer: BackgroundIndexer

    init(width: CGFloat = 1180, presentationDefaults: [String: Any] = [:],
         appearance: ColorScheme = .light, reduceMotion: Bool = false,
         reduceTransparency: Bool = false) async throws {
        fixture = try await LegacyBoundaryFixture()
        initialProject = fixture.session.activeProject
        initialDocumentID = fixture.session.selectedDocumentID
        for (key, value) in presentationDefaults { fixture.defaults.set(value, forKey: key) }
        let settings = CompletionSettings(defaults: fixture.defaults)
        settings.setCompletionEnabled(false)
        completion = CompletionController(settings: settings)
        indexer = BackgroundIndexer(engine: CompletionEngine(), settings: settings)
        window = LegacyUndoWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.testUndo.groupsByEvent = false
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        host = NSHostingView(rootView: ContentView(projectSession: fixture.session,
            legacyWorkspace: fixture.controller(), editorRequests: requests, completion: completion,
            indexer: indexer, livingMargin: LivingMarginModel(), firstRunFlow: FirstRunFlow(
                session: fixture.session, store: fixture.store, editorRequests: requests),
            positionStore: WritingPositionStore(defaults: fixture.defaults))
            .defaultAppStorage(fixture.defaults)
            .environment(\.colorScheme, appearance))
        window.contentView = host
        await layout()
    }

    func layout() async {
        for _ in 0..<25 { host.layoutSubtreeIfNeeded(); await Task.yield() }
    }

    func editor() async throws -> BlockTextView {
        await layout()
        func find(_ view: NSView) -> BlockTextView? {
            (view as? BlockTextView) ?? view.subviews.compactMap { find($0) }.first
        }
        return try XCTUnwrap(find(host))
    }

    func elements() -> [any NSAccessibilityProtocol] {
        var visited = Set<ObjectIdentifier>()
        func walk(_ object: AnyObject, depth: Int = 0) -> [any NSAccessibilityProtocol] {
            guard depth < 80, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            var result: [any NSAccessibilityProtocol] = []
            if let element = object as? any NSAccessibilityProtocol {
                result.append(element)
                for child in element.accessibilityChildren() ?? [] {
                    result += walk(child as AnyObject, depth: depth + 1)
                }
            }
            if let view = object as? NSView {
                for child in view.subviews { result += walk(child, depth: depth + 1) }
            }
            return result
        }
        return walk(host)
    }

    func element(_ identifier: String) -> (any NSAccessibilityProtocol)? {
        elements().first { $0.accessibilityIdentifier() == identifier }
    }

    func close() {
        window.testUndo.removeAllActions(); window.contentView = nil; window.close()
        completion.shutdown(); indexer.shutdown(); fixture.cleanUp()
    }
}
