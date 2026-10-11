import AppKit
import SwiftUI
import XCTest
@testable import MINTCore

@MainActor
final class FramedWorkspaceTests: XCTestCase {
    func testSavedToolChoiceSurvivesWorkspaceAppearance() async throws {
        for section in ["bible", "timeline", "context"] {
            let h = try await FramedWorkspaceHarness(presentationDefaults: ["mint.sidebarSection": section])
            defer { h.close() }
            let project = h.initialProject
            let selected = h.initialDocumentID
            await h.layout()
            XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.sidebarSection"), section)
            let editor = try await h.editor()
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, 589, accuracy: 1,
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
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, 930, accuracy: 1,
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

    func close() {
        window.testUndo.removeAllActions(); window.contentView = nil; window.close()
        completion.shutdown(); indexer.shutdown(); fixture.cleanUp()
    }
}
