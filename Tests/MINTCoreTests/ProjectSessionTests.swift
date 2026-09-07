import Foundation
import XCTest
@testable import MINTCore

@MainActor
final class ProjectSessionTests: XCTestCase {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-ProjectSession-\(UUID().uuidString)", isDirectory: true)
    }

    private func defaultsSuite() -> (UserDefaults, String) {
        let name = "MINT.ProjectSessionTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func fictionProject() -> WritingProject {
        WritingProject(
            id: WritingProjectID(),
            title: "Novel",
            mode: .fiction,
            documents: [
                WritingDocument(
                    id: WritingDocumentID(), title: "Chapter 1", body: "A", kind: .manuscript),
                WritingDocument(
                    id: WritingDocumentID(), title: "Chapter 2", body: "B", kind: .manuscript),
            ])
    }

    private func generalProject() -> WritingProject {
        WritingProject(
            id: WritingProjectID(),
            title: "Essay",
            mode: .general,
            documents: [
                WritingDocument(
                    id: WritingDocumentID(), title: "Draft", body: "C", kind: .manuscript)
            ])
    }

    func testProjectSwitchIsolatesDocumentAndWorkspaceSelection() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (defaults, suite) = defaultsSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProjectStore(root: root)
        let fiction = fictionProject()
        let general = generalProject()
        try await store.save(fiction)
        try await store.save(general)

        let session = ProjectSession(store: store, defaults: defaults)
        try await session.activateProject(id: fiction.id)
        session.selectDocument(fiction.documents[1].id)
        session.selectWorkspaceMode(.map)

        XCTAssertEqual(session.selectedDocumentID, fiction.documents[1].id)
        XCTAssertEqual(session.workspaceMode, .map)

        try await session.activateProject(id: general.id)

        XCTAssertEqual(session.activeProject?.id, general.id)
        XCTAssertEqual(session.selectedDocumentID, general.documents[0].id)
        XCTAssertNotEqual(session.selectedDocumentID, fiction.documents[1].id)
        XCTAssertEqual(session.workspaceMode, .write)
        XCTAssertEqual(session.availableWorkspaceModes, [.write, .outline, .review])

        try await session.activateProject(id: fiction.id)
        XCTAssertEqual(session.selectedDocumentID, fiction.documents[1].id)
        XCTAssertEqual(session.workspaceMode, .map)
    }

    func testStaleGeneralMapPreferenceNormalizesAndPersistsWrite() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (defaults, suite) = defaultsSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProjectStore(root: root)
        let general = generalProject()
        try await store.save(general)
        defaults.set(
            WorkspaceMode.map.rawValue,
            forKey: "mint.workspaceMode.\(general.id.rawValue.uuidString)")

        let session = ProjectSession(store: store, defaults: defaults)
        try await session.activateProject(id: general.id)

        XCTAssertEqual(session.workspaceMode, .write)
        XCTAssertEqual(
            defaults.string(
                forKey: "mint.workspaceMode.\(general.id.rawValue.uuidString)"),
            WorkspaceMode.write.rawValue)
    }

    func testSaveAndActivatePublishesOnlyVerifiedProject() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (defaults, suite) = defaultsSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProjectStore(root: root)
        let session = ProjectSession(store: store, defaults: defaults)
        let project = fictionProject()

        try await session.saveAndActivate(project)

        XCTAssertEqual(session.activeProject, project)
        XCTAssertEqual(session.selectedDocumentID, project.documents.first?.id)
        let active = try await store.activeProject()
        XCTAssertEqual(active, project)
    }
}
