import XCTest
@testable import MINTCore

final class ProjectStoreTests: XCTestCase {
    func testRoundTripKeepsBodiesOutsideManifestAndSurvivesCacheDeletion() async throws {
        let root = try temporaryProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let project = projectFixture()
        try await store.save(project)
        let folder = root.appendingPathComponent(project.id.rawValue.uuidString)
        let manifest = try String(contentsOf: folder.appendingPathComponent("project.json"), encoding: .utf8)
        XCTAssertFalse(manifest.contains("원고 고유 문장"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Intelligence"))
        let reopened = try await ProjectStore(root: root).load(id: project.id)
        XCTAssertEqual(reopened, project)
        for (actual, expected) in zip(reopened.documents, project.documents) {
            XCTAssertEqual(Data(actual.body.utf8), Data(expected.body.utf8))
        }
    }

    func testFailedSaveKeepsEntirePreviousRevisionAndActiveSelection() async throws {
        let root = try temporaryProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = projectFixture()
        let store = ProjectStore(root: root)
        try await store.save(original)
        try await store.activate(id: original.id)
        var edited = original
        edited.documents[0].body = "첫 문서 수정"
        edited.documents[1].body = "둘째 문서 수정"
        for failure in ["Notes/", "project.json"] {
            let failing = ProjectStore(root: root, fileSystem: FailingProjectFiles(fragment: failure))
            do {
                try await failing.save(edited)
                XCTFail("쓰기 실패가 성공으로 보고됨")
            } catch {}
            let actual = try await store.activeProject()
            XCTAssertEqual(actual, original)
        }
    }

    func testRejectsTraversalAndSymlinkWithoutReadingOutsideProject() async throws {
        let root = try temporaryProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = projectFixture()
        let store = ProjectStore(root: root)
        try await store.save(project)
        let folder = root.appendingPathComponent(project.id.rawValue.uuidString)
        let manifestURL = folder.appendingPathComponent("project.json")
        let original = try Data(contentsOf: manifestURL)
        for path in ["../outside.md", "/tmp/outside.md"] {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            var documents = try XCTUnwrap(json["documents"] as? [[String: Any]])
            documents[0]["relativePath"] = path
            json["documents"] = documents
            try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
            do { _ = try await store.load(id: project.id); XCTFail("프로젝트 밖 경로 허용") } catch {}
        }
        try original.write(to: manifestURL)
        let documentsURL = folder.appendingPathComponent("Documents")
        try FileManager.default.removeItem(at: documentsURL)
        try FileManager.default.createSymbolicLink(at: documentsURL, withDestinationURL: root)
        do { try await store.save(project); XCTFail("심볼릭 링크 경유 저장 허용") } catch {}
    }

    func testCorruptCurrentRevisionCanReadPreviousWithoutMutatingEither() async throws {
        let root = try temporaryProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let original = projectFixture()
        try await store.save(original)
        var edited = original
        edited.documents[0].body = "수정본"
        try await store.save(edited)
        let manifest = root.appendingPathComponent("\(original.id.rawValue.uuidString)/project.json")
        let broken = Data("broken".utf8)
        try broken.write(to: manifest)
        do { _ = try await store.load(id: original.id); XCTFail("손상 파일을 정상으로 표시") } catch {}
        let recovered = try await store.previousProject(id: original.id)
        XCTAssertEqual(recovered, original)
        XCTAssertEqual(try Data(contentsOf: manifest), broken)
    }
}

func temporaryProjectRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mint-project-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func projectFixture() -> WritingProject {
    WritingProject(id: WritingProjectID(), title: "글 모음", mode: .general, documents: [
        WritingDocument(id: WritingDocumentID(), title: "초안", body: "원고 고유 문장\r\n\u{1100}\u{1161} 👩🏽‍💻\n![그림](images/a.png)\n$E=mc^2$\n", kind: .manuscript),
        WritingDocument(id: WritingDocumentID(), title: "메모", body: " \t\r\n", kind: .note)
    ])
}

struct FailingProjectFiles: ProjectFileSystem {
    let fragment: String
    let real = LocalProjectFileSystem()
    func createDirectory(at url: URL) throws { try real.createDirectory(at: url) }
    func read(_ url: URL) throws -> Data { try real.read(url) }
    func fileExists(at url: URL) -> Bool { real.fileExists(at: url) }
    func writeAtomically(_ data: Data, to url: URL) throws {
        if fragment.hasSuffix("/") ? url.path.contains(fragment) : url.lastPathComponent == fragment {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try real.writeAtomically(data, to: url)
    }
}
