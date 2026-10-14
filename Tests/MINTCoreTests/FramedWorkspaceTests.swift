import AppKit
import SwiftUI
import XCTest
@testable import MINTCore

@MainActor
final class FramedWorkspaceTests: XCTestCase {
    func testLongProjectTitleKeepsNavigatorCloseInsideCard() async throws {
        let title = "Synthetic framed workspace matrix · 아주 긴 프로젝트 이름과 최근 작품 목록"
        for navigatorWidth in [200.0, 250.0, 360.0] {
            let h = try await FramedWorkspaceHarness(
                presentationDefaults: ["mint.sidebarWidth": navigatorWidth], projectTitle: title)
            defer { h.close() }
            let editor = try await h.editor()
            for width: CGFloat in [860, 1180, 1440] {
                h.window.setContentSize(NSSize(width: width, height: 760)); await h.layout()
                let rail = try XCTUnwrap(h.element("mint.workspace.rail") as? NSView)
                let close = try XCTUnwrap(h.element("mint.navigator.close") as? NSButton)
                let navigatorLeading = rail.convert(rail.bounds, to: nil).maxX + 10
                let closeRect = close.convert(close.bounds, to: nil)
                XCTAssertGreaterThanOrEqual(closeRect.minX, navigatorLeading + 12)
                XCTAssertLessThanOrEqual(closeRect.maxX, navigatorLeading + navigatorWidth,
                    "Long titles must not push the close button outside the clipped navigator")
                XCTAssertEqual(close.bounds.width, 32, accuracy: 0.5)
                XCTAssertEqual(h.fixture.session.activeProject?.title, title)
            }
            try XCTUnwrap(h.element("mint.navigator.close") as? NSButton).performClick(nil)
            await h.layout()
            XCTAssertTrue(h.window.firstResponder === editor)
        }
    }

    func testRailExposesFunctionalActionsAndSelectedNavigatorState() async throws {
        let h = try await FramedWorkspaceHarness(presentationDefaults: ["mint.sidebarVisible": true])
        defer { h.close() }
        XCTAssertEqual(h.elements().filter { $0.accessibilityIdentifier() == "mint.workspace.rail" }.count, 1)
        let rail = try XCTUnwrap(h.element("mint.workspace.rail") as? NSView)
        XCTAssertEqual(rail.bounds.width, 56, accuracy: 0.5)
        for identifier in ["mint.workspace.navigator-toggle", "mint.source-search.show",
                           "mint.writer-tools.compatibility", "mint.workspace.settings"] {
            let button = try XCTUnwrap(h.element(identifier) as? NSButton)
            XCTAssertGreaterThanOrEqual(button.bounds.width, 32)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 32)
            if let menu = (button as? NSPopUpButton)?.menu {
                for item in menu.items.dropFirst() { XCTAssertNotNil(item.target); XCTAssertNotNil(item.action) }
            } else { XCTAssertNotNil(button.target, identifier); XCTAssertNotNil(button.action, identifier) }
            XCTAssertEqual(h.elements().filter { $0.accessibilityIdentifier() == identifier }.count, 1)
        }
        let files = try XCTUnwrap(h.element("mint.workspace.navigator-toggle") as? NSButton)
        XCTAssertEqual(files.accessibilityLabel(), "파일 목록 숨기기")
        XCTAssertEqual((files.accessibilityValue() as? NSNumber)?.boolValue, true)
        files.performClick(nil); await h.layout()
        XCTAssertEqual(files.accessibilityLabel(), "파일 목록 보이기")
        XCTAssertEqual((files.accessibilityValue() as? NSNumber)?.boolValue, false)
        XCTAssertFalse(h.elements().contains { $0.accessibilityLabel() == "리빙 마진" })
    }

    func testRailToggleAndResizePreserveEditorAndPreferences() async throws {
        let h = try await FramedWorkspaceHarness(presentationDefaults: [
            "mint.sidebarVisible": true, "mint.sidebarWidth": 275.0, "mint.toolDockPosition": "floating"])
        defer { h.close() }
        let editor = try await h.editor(), manager = try XCTUnwrap(editor.undoManager)
        manager.beginUndoGrouping(); editor.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        manager.endUndoGrouping(); editor.setSelectedRange(NSRange(location: 3, length: 4)); await h.layout()
        let key = h.requests.nativeEditorKey, project = h.fixture.session.activeProject, text = editor.string
        XCTAssertTrue(h.window.makeFirstResponder(editor))
        for width: CGFloat in [860, 1180, 1440] {
            h.window.setContentSize(NSSize(width: width, height: 760)); await h.layout()
            for _ in 0..<2 {
                try XCTUnwrap(h.element("mint.workspace.navigator-toggle") as? NSButton).performClick(nil)
                await h.layout()
                let current = try await h.editor(); XCTAssertTrue(current === editor)
                XCTAssertTrue(h.window.firstResponder === editor)
                XCTAssertTrue(editor.undoManager === manager); XCTAssertTrue(manager.canUndo)
                XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 4))
                XCTAssertEqual(editor.string, text); XCTAssertEqual(h.requests.nativeEditorKey, key)
                XCTAssertEqual(h.fixture.session.activeProject, project)
            }
        }
        XCTAssertEqual(h.fixture.defaults.double(forKey: "mint.sidebarWidth"), 275)
        XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.toolDockPosition"), "floating")
    }

    func testHiddenNavigatorSearchRequestIsConsumedOnce() async throws {
        let h = try await FramedWorkspaceHarness(presentationDefaults: ["mint.sidebarVisible": false])
        defer { h.close() }
        let editor = try await h.editor()
        h.fixture.defaults.set(true, forKey: "mint.sidebarVisible"); h.requests.focusSearch(); await h.layout()
        let search = try XCTUnwrap(h.field("프로젝트 검색"))
        let fieldEditor = try XCTUnwrap(search.currentEditor())
        XCTAssertTrue(h.window.firstResponder === fieldEditor)
        try XCTUnwrap(h.element("mint.navigator.close") as? NSButton).performClick(nil); await h.layout()
        XCTAssertTrue(h.window.firstResponder === editor)
        h.fixture.defaults.set(true, forKey: "mint.sidebarVisible"); await h.layout()
        XCTAssertNotNil(h.field("프로젝트 검색"))
        XCTAssertTrue(h.window.firstResponder === editor)
    }

    func testRailSearchHonorsMarkedTextAndEditability() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let editor = try await h.editor(), search = try XCTUnwrap(h.element("mint.source-search.show") as? NSButton)
        let manager = try XCTUnwrap(editor.undoManager)
        manager.beginUndoGrouping()
        editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 0))
        let selection = editor.selectedRange()
        let panels = NSApp.windows.filter { $0.title == "원문 검색" && $0.isVisible }.count
        search.performClick(nil); await h.layout()
        XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(NSApp.windows.filter { $0.title == "원문 검색" && $0.isVisible }.count, panels)
        editor.unmarkText(); editor.didChangeText(); manager.endUndoGrouping()
        h.fixture.session.selectDocument(nil); await h.layout()
        XCTAssertFalse(search.isEnabled)
    }

    func testDocumentToolbarRetainsLocalControlsWithoutDuplicateGlobalActions() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let host = NSHostingView(rootView: EditorToolbar(projectSession: h.fixture.session,
            editorRequests: h.requests, completion: h.completion, settings: h.completion.settings,
            theme: .light).defaultAppStorage(h.fixture.defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 52),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<25 { host.layoutSubtreeIfNeeded(); await Task.yield() }
        let controls = h.elements(in: host)
        for identifier in ["mint.source-search.show", "mint.writer-tools.compatibility",
                           "mint.workspace.navigator-toggle", "mint.workspace.settings"] {
            XCTAssertFalse(controls.contains { $0.accessibilityIdentifier() == identifier })
        }
        XCTAssertEqual(host.bounds.height, 52, accuracy: 0.5)
        // SwiftUI-only title/model/notice visibility is verified in the integrated app batch.

    }

    func testNavigatorOverlayAnchorsToManuscriptBesideLeftTool() async throws {
        let h = try await FramedWorkspaceHarness(width: 1000, presentationDefaults: [
            "mint.sidebarSection": "bible", "mint.toolDockPosition": "left"])
        defer { h.close() }
        let editor = try await h.editor(), scroll = try XCTUnwrap(editor.enclosingScrollView)
        XCTAssertEqual(scroll.bounds.width, 573, accuracy: 1)
        let close = try XCTUnwrap(h.element("mint.navigator.close") as? NSButton)
        let manuscriptRect = scroll.convert(scroll.bounds, to: nil)
        let closeRect = close.convert(close.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(closeRect.minX, manuscriptRect.minX)
        XCTAssertLessThanOrEqual(closeRect.maxX, manuscriptRect.minX + 250)
        XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.toolDockPosition"), "left")
    }

    func testNavigatorOverlayKeepsEditorAllocationAtNarrowWidths() async throws {
        let h = try await FramedWorkspaceHarness(presentationDefaults: [
            "mint.sidebarVisible": true, "mint.sidebarWidth": 250.0, "mint.toolDockPosition": "left"])
        defer { h.close() }
        let editor = try await h.editor()
        for (width, expected): (CGFloat, CGFloat) in [(860, 774), (1023, 937),
                                                      (1024, 678), (1180, 834), (1440, 1094)] {
            h.window.setContentSize(NSSize(width: width, height: 760)); await h.layout()
            let current = try await h.editor(); XCTAssertTrue(current === editor)
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, expected, accuracy: 1)
            try XCTUnwrap(h.element("mint.navigator.close") as? NSButton).performClick(nil)
            await h.layout()
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, width - 86, accuracy: 1)
            h.fixture.defaults.set(true, forKey: "mint.sidebarVisible"); await h.layout()
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, expected, accuracy: 1)
        }
        XCTAssertEqual(h.fixture.defaults.double(forKey: "mint.sidebarWidth"), 250)
        XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.toolDockPosition"), "left")
        XCTAssertEqual(h.fixture.session.activeProject, h.initialProject)
    }

    func testResizePreservesEditorSelectionUndoAndMarkedText() async throws {
        for marked in [false, true] {
            let h = try await FramedWorkspaceHarness(); defer { h.close() }
            let editor = try await h.editor(), manager = try XCTUnwrap(editor.undoManager)
            let key = h.requests.nativeEditorKey
            manager.beginUndoGrouping()
            if marked {
                editor.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0),
                    replacementRange: NSRange(location: 0, length: 0))
            } else {
                editor.insertText("!", replacementRange: NSRange(location: 0, length: 0))
                manager.endUndoGrouping(); editor.setSelectedRange(NSRange(location: 3, length: 4))
            }
            defer { while manager.groupingLevel > 0 { manager.endUndoGrouping() } }
            let text = editor.string, selection = editor.selectedRange()
            XCTAssertTrue(h.window.makeFirstResponder(editor))
            for width: CGFloat in [860, 1023, 1024, 1180, 1440] {
                h.window.setContentSize(NSSize(width: width, height: 760)); await h.layout()
                let current = try await h.editor(); XCTAssertTrue(current === editor)
                XCTAssertTrue(editor.undoManager === manager)
                XCTAssertTrue(h.window.firstResponder === editor)
                XCTAssertEqual(h.requests.nativeEditorKey, key)
                XCTAssertEqual(editor.selectedRange(), selection)
                XCTAssertEqual(editor.string, text)
                XCTAssertEqual(editor.hasMarkedText(), marked)
            }
            if marked { editor.unmarkText(); editor.didChangeText(); manager.endUndoGrouping() }
            else { XCTAssertTrue(manager.canUndo); manager.undo(); XCTAssertFalse(editor.string.hasPrefix("!")) }
        }
    }

    func testResizePreservesNavigatorSearchAndPendingRename() async throws {
        let h = try await FramedWorkspaceHarness(width: 1023); defer { h.close() }
        h.requests.focusSearch(); await h.layout()
        let search = try XCTUnwrap(h.field("프로젝트 검색"))
        let searchEditor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        searchEditor.insertText("original", replacementRange: NSRange(location: 0, length: 0))
        await h.layout()
        for width: CGFloat in [1024, 1023, 1180] {
            h.window.setContentSize(NSSize(width: width, height: 760)); await h.layout()
            XCTAssertTrue(h.field("프로젝트 검색") === search)
            XCTAssertEqual(searchEditor.string, "original")
        }
        searchEditor.insertText("", replacementRange: NSRange(location: 0, length: searchEditor.string.utf16.count))
        await h.layout(); h.requests.beginRename(); await h.layout()
        let rename = try XCTUnwrap(h.field("문서 이름"))
        let renameEditor = try XCTUnwrap(rename.currentEditor() as? NSTextView)
        renameEditor.insertText("Pending title", replacementRange: NSRange(location: 0, length: renameEditor.string.utf16.count))
        for width: CGFloat in [1023, 1024, 1180] {
            h.window.setContentSize(NSSize(width: width, height: 760)); await h.layout()
            XCTAssertTrue(h.field("문서 이름") === rename)
            XCTAssertEqual(renameEditor.string, "Pending title")
            XCTAssertEqual(h.fixture.session.selectedDocument?.title, "Manuscript")
        }
    }

    func testFrameSupportsDisplayAccessibilityOptions() async throws {
        let palette = PaletteSettings.shared
        let saved = (palette.enabled, palette.light, palette.dark)
        defer { palette.light = saved.1; palette.dark = saved.2; palette.enabled = saved.0 }
        for (scheme, motion, transparency, custom) in [(ColorScheme.light, false, false, false),
                (.dark, true, false, false), (.light, false, true, true), (.dark, true, true, true)] {
            palette.enabled = custom
            if custom { var light = palette.light; light.hexes[0] = 0xDDEEDD; palette.light = light }
            let h = try await FramedWorkspaceHarness(appearance: scheme,
                reduceMotion: motion, reduceTransparency: transparency); defer { h.close() }
            let editor = try await h.editor(), manager = try XCTUnwrap(editor.undoManager)
            manager.beginUndoGrouping(); editor.insertText("!", replacementRange: NSRange(location: 0, length: 0))
            manager.endUndoGrouping()
            let frame = try XCTUnwrap(h.element("mint.workspace.frame") as? NSView)
            XCTAssertEqual(frame.layer?.backgroundColor, palette.theme(for: scheme).editorSurface.cgColor)
            XCTAssertEqual(frame.layer?.backgroundColor?.alpha, 1)
            try XCTUnwrap(h.element("mint.navigator.close") as? NSButton).performClick(nil); await h.layout()
            let current = try await h.editor(); XCTAssertTrue(current === editor)
            XCTAssertTrue(h.window.firstResponder === editor)
            XCTAssertTrue(editor.undoManager === manager)
            XCTAssertTrue(manager.canUndo)
        }
    }

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

    func testWindowTitleHitTestingReachesNativeDragRegion() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let chrome = try XCTUnwrap(h.element("mint.workspace.chrome") as? NSView)
        let title = try XCTUnwrap(h.element("mint.workspace.chrome.title") as? NSTextField)
        for view in [chrome, title] {
            let center = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            let point = view.convert(center, to: h.host.superview)
            let receiver = h.host.hitTest(point)
            XCTAssertTrue(receiver === chrome,
                "Title pointer must reach the native drag view, got \(String(describing: receiver))")
        }
    }

    func testWindowTitlePressDelegatesToNativeWindowDragging() async throws {
        let h = try await FramedWorkspaceHarness(); defer { h.close() }
        let chrome = try XCTUnwrap(h.element("mint.workspace.chrome") as? NSView)
        let editor = try await h.editor()
        editor.setSelectedRange(NSRange(location: 3, length: 4))
        let originalStyle = h.window.styleMask
        let originalBackgroundDragging = h.window.isMovableByWindowBackground
        h.window.makeKeyAndOrderFront(nil)
        h.window.makeFirstResponder(editor)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: chrome.convert(NSPoint(x: chrome.bounds.midX, y: chrome.bounds.midY), to: nil),
            modifierFlags: [], timestamp: 1, windowNumber: h.window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertTrue(chrome.acceptsFirstMouse(for: event),
            "An inactive title region must accept the first press")
        h.window.sendEvent(event)
        XCTAssertTrue(h.window.lastDragEvent === event,
            "A title press must hand the original event to native window dragging")
        XCTAssertEqual(h.window.styleMask, originalStyle)
        XCTAssertEqual(h.window.isMovableByWindowBackground, originalBackgroundDragging)
        XCTAssertTrue(h.window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 4))
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
            let h = try await FramedWorkspaceHarness(width: 1440, presentationDefaults: ["mint.sidebarSection": section])
            defer { h.close() }
            let project = h.initialProject
            let selected = h.initialDocumentID
            await h.layout()
            XCTAssertEqual(h.fixture.defaults.string(forKey: "mint.sidebarSection"), section)
            let editor = try await h.editor()
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, 753, accuracy: 1,
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
            XCTAssertEqual(try XCTUnwrap(editor.enclosingScrollView).bounds.width, 834, accuracy: 1,
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
    let window: FramedWorkspaceWindow
    let host: NSView
    let completion: CompletionController
    let indexer: BackgroundIndexer

    init(width: CGFloat = 1180, presentationDefaults: [String: Any] = [:],
         appearance: ColorScheme = .light, reduceMotion: Bool = false,
         reduceTransparency: Bool = false, projectTitle: String = "Project") async throws {
        fixture = try await LegacyBoundaryFixture(projectTitle: projectTitle)
        initialProject = fixture.session.activeProject
        initialDocumentID = fixture.session.selectedDocumentID
        for (key, value) in presentationDefaults { fixture.defaults.set(value, forKey: key) }
        let settings = CompletionSettings(defaults: fixture.defaults)
        settings.setCompletionEnabled(false)
        completion = CompletionController(settings: settings)
        indexer = BackgroundIndexer(engine: CompletionEngine(), settings: settings)
        window = FramedWorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 760),
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
            .environment(\.colorScheme, appearance)
            .environment(\.mintWorkspaceAccessibilityOptions, WorkspaceAccessibilityOptions(
                reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)))
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

    func elements(in root: NSView? = nil) -> [any NSAccessibilityProtocol] {
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
        return walk(root ?? host)
    }

    func element(_ identifier: String) -> (any NSAccessibilityProtocol)? {
        elements().first { $0.accessibilityIdentifier() == identifier }
    }

    func field(_ placeholder: String) -> NSTextField? {
        elements().compactMap { $0 as? NSTextField }.first { $0.placeholderString == placeholder }
    }

    func close() {
        window.testUndo.removeAllActions(); window.contentView = nil; window.close()
        completion.shutdown(); indexer.shutdown(); fixture.cleanUp()
    }
}

@MainActor
final class FramedWorkspaceWindow: NSWindow {
    let testUndo = UndoManager()
    var lastDragEvent: NSEvent?
    override var undoManager: UndoManager? { testUndo }
    override func performDrag(with event: NSEvent) { lastDragEvent = event }
}
