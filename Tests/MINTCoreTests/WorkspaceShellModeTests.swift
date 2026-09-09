import Foundation
import XCTest
@testable import MINTCore

@MainActor
final class WorkspaceShellModeTests: XCTestCase {
    func testLivingMarginShowAndHideDoNotEmitEditorFocusRequests() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-LivingMarginFocus-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entryStore = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        let initialFocusRequests = entryStore.editorFocusRequests
        var section = SidebarSection.files.rawValue

        WorkspaceToolSelection.showLivingMargin(currentSection: &section)
        XCTAssertEqual(section, SidebarSection.margin.rawValue)
        WorkspaceToolSelection.hide(currentSection: &section)

        XCTAssertEqual(section, SidebarSection.files.rawValue)
        XCTAssertEqual(entryStore.editorFocusRequests, initialFocusRequests)
    }

    func testLivingMarginEvidenceJumpUsesLegacyDocumentIdentity() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-LivingMarginJump-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entryStore = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        entryStore.updateActiveBody("Before. The lantern was still lit. After.")
        let initialFocusRequests = entryStore.editorFocusRequests
        let anchor = EvidenceAnchor(
            documentID: WritingDocumentID(rawValue: entryStore.activeID),
            quote: "The lantern was still lit.")

        XCTAssertTrue(LivingMarginWorkspaceBridge.jump(to: anchor, in: entryStore))
        XCTAssertEqual(entryStore.searchJump?.entryID, entryStore.activeID)
        XCTAssertEqual(entryStore.searchJump?.query, "The lantern was still lit.")
        XCTAssertEqual(entryStore.editorFocusRequests, initialFocusRequests + 1)
    }

    func testLivingMarginRejectsUnknownOrStaleEvidenceWithoutMovingEditor() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-LivingMarginStale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entryStore = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        entryStore.updateActiveBody("Current manuscript text.")
        let initialFocusRequests = entryStore.editorFocusRequests
        let unknown = EvidenceAnchor(
            documentID: WritingDocumentID(),
            quote: "Current manuscript text.")
        let stale = EvidenceAnchor(
            documentID: WritingDocumentID(rawValue: entryStore.activeID),
            quote: "A vanished lantern sentence.")

        XCTAssertFalse(LivingMarginWorkspaceBridge.jump(to: unknown, in: entryStore))
        XCTAssertFalse(LivingMarginWorkspaceBridge.jump(to: stale, in: entryStore))
        XCTAssertNil(entryStore.searchJump)
        XCTAssertEqual(entryStore.editorFocusRequests, initialFocusRequests)
    }

    func testModeOptionsMatchTheActiveProjectType() {
        XCTAssertEqual(
            WorkspaceModePresentation.options(for: .fiction),
            [
                WorkspaceModeOption(mode: .write, label: "쓰기"),
                WorkspaceModeOption(mode: .map, label: "지도"),
                WorkspaceModeOption(mode: .review, label: "검토"),
            ])
        XCTAssertEqual(
            WorkspaceModePresentation.options(for: .general),
            [
                WorkspaceModeOption(mode: .write, label: "쓰기"),
                WorkspaceModeOption(mode: .outline, label: "개요"),
                WorkspaceModeOption(mode: .review, label: "검토"),
            ])
    }

    func testModeSelectionUpdatesSessionAndRestoresEditorFocus() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-WorkspaceMode-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "MINT.WorkspaceShellModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let projectStore = ProjectStore(root: root.appendingPathComponent("Projects"))
        let session = ProjectSession(store: projectStore, defaults: defaults)
        let project = WritingProject(
            id: WritingProjectID(),
            title: "Novel",
            mode: .fiction,
            documents: [
                WritingDocument(
                    id: WritingDocumentID(),
                    title: "Chapter 1",
                    body: "Draft",
                    kind: .manuscript)
            ])
        try await session.saveAndActivate(project)

        let entryStore = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        let focusRequestsBeforeSelection = entryStore.editorFocusRequests

        WorkspaceModeSelection.select(.map, session: session, editorStore: entryStore)

        XCTAssertEqual(session.workspaceMode, .map)
        XCTAssertEqual(entryStore.editorFocusRequests, focusRequestsBeforeSelection + 1)
    }
}
