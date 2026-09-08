import Foundation
import XCTest
@testable import MINTCore

@MainActor
final class WorkspaceShellModeTests: XCTestCase {
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
