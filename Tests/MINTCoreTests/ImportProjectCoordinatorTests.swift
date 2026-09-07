import Foundation
import XCTest
@testable import MINTCore

@MainActor
final class ImportProjectCoordinatorTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-OnboardingImport-\(UUID().uuidString)", isDirectory: true)
    }

    private func defaults() -> (UserDefaults, String) {
        let name = "MINT.OnboardingImportTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func writeLegacyFixture(at root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data(#"{"entries":[{"id":"00000000-0000-0000-0000-000000000201","title":"Draft","createdAt":"2026-09-01T00:00:00Z","body":"한글\r\n가\n![그림](images/a.png)\n","kind":"novel","characters":[]}],"activeID":"00000000-0000-0000-0000-000000000201","folders":[],"expandedFolderIDs":[]}"#.utf8)
        let source = root.appendingPathComponent("entries.json")
        try data.write(to: source)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("images"),
            withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("images/a.png"))
        return source
    }

    func testImportPreservesSourceAndPublishesVerifiedProject() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try writeLegacyFixture(at: url)
        let original = try Data(contentsOf: source)
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProjectStore(root: url.appendingPathComponent("Projects"))
        let session = ProjectSession(store: store, defaults: defaults)
        let coordinator = ImportProjectCoordinator(store: store, session: session)

        let result = try await coordinator.importLegacy(
            from: source,
            mode: .fiction,
            title: "Imported Novel")

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(session.activeProject?.id, result.projectID)
        XCTAssertEqual(session.activeProject?.mode, .fiction)
        XCTAssertEqual(session.activeProject?.documents.first?.body,
            "한글\r\n가\n![그림](images/a.png)\n")
        XCTAssertEqual(
            try await FirstRunStateResolver.resolve(using: store),
            .ready(result.projectID))
    }

    func testFailedImportLeavesCurrentSessionAndSourceUntouched() async throws {
        let url = root()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let broken = url.appendingPathComponent("broken.json")
        let original = Data("not-json".utf8)
        try original.write(to: broken)

        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProjectStore(root: url.appendingPathComponent("Projects"))
        let session = ProjectSession(store: store, defaults: defaults)
        let created = try await ProjectCreationCoordinator(session: session)
            .createProject(title: "Current", mode: .general)

        let coordinator = ImportProjectCoordinator(store: store, session: session)
        do {
            _ = try await coordinator.importLegacy(
                from: broken,
                mode: .fiction,
                title: "Broken")
            XCTFail("Malformed import unexpectedly succeeded")
        } catch {}

        XCTAssertEqual(session.activeProject?.id, created.projectID)
        XCTAssertEqual(try Data(contentsOf: broken), original)
        XCTAssertEqual(try await store.activeProject()?.id, created.projectID)
    }
}
