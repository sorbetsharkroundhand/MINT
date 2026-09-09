import XCTest
@testable import MINTCore

final class HierarchicalMemoryTests: XCTestCase {
    func testSceneContentVersionIsSeparateFromDurableScopeIdentity() {
        let projectID = WritingProjectID()
        let documentID = WritingDocumentID()
        let scope = StoryMemoryScope.project(projectID: projectID, documentID: documentID)
        let version = SceneContentVersion(rawValue: "content-digest")

        XCTAssertEqual(scope.projectID, projectID)
        XCTAssertEqual(scope.documentID, documentID)
        XCTAssertEqual(version.rawValue, "content-digest")
        XCTAssertNotEqual(StoryMemoryNodeID.chapter(path: ["Part", "Chapter"]).key, version.rawValue)
    }

    func testEditingOneSceneDirtiesOnlyItsDependentPath() {
        let original = outlineFixture(changedSecondScene: false)
        let edited = outlineFixture(changedSecondScene: true)
        var sidecar = completeSidecar(for: original)
        sidecar.chapterSummaries = chapterSummaries(for: original)
        sidecar.workSummary = .init(
            childrenHash: HierarchicalMemory.workChildrenHash(for: original),
            summary: "Work summary", updatedAt: .now)

        let changes = HierarchicalMemory.changes(previous: sidecar, outline: edited)

        XCTAssertEqual(changes.dirtyScenes, [edited.scenes[1].contentVersion])
        XCTAssertEqual(changes.dirtyChapters, [StoryMemoryNodeID.chapter(path: ["Part", "One"])])
        XCTAssertTrue(changes.workIsDirty)
        XCTAssertFalse(changes.dirtyChapters.contains(.chapter(path: ["Part", "Two"])))
        XCTAssertFalse(changes.dirtyScenes.contains(edited.scenes[2].contentVersion))
        XCTAssertFalse(changes.dirtyScenes.contains(edited.scenes[3].contentVersion))
    }

    func testUnchangedHierarchyIsFullyReusable() {
        let outline = outlineFixture(changedSecondScene: false)
        var sidecar = completeSidecar(for: outline)
        sidecar.chapterSummaries = chapterSummaries(for: outline)
        sidecar.workSummary = .init(
            childrenHash: HierarchicalMemory.workChildrenHash(for: outline),
            summary: "Work summary", updatedAt: .now)

        let changes = HierarchicalMemory.changes(previous: sidecar, outline: outline)

        XCTAssertTrue(changes.dirtyScenes.isEmpty)
        XCTAssertTrue(changes.dirtyChapters.isEmpty)
        XCTAssertFalse(changes.workIsDirty)
    }

    func testSnapshotExcludesStaleHierarchyAndDrillsDownToCurrentText() {
        let body = "Alpha opens the gate.\nBeta waits by the river.\nGamma lights a candle.\nDelta closes the door."
        let outline = sequentialOutline(for: body)
        let documentID = WritingDocumentID()
        let scope = StoryMemoryScope.project(projectID: WritingProjectID(), documentID: documentID)
        var sidecar = completeSidecar(for: outline)
        sidecar.sceneSummaries[outline.scenes[1].contentHash]?.contentHash = "stale-scene"
        sidecar.chapterSummaries = chapterSummaries(for: outline)
        sidecar.chapterSummaries[0].childrenHash = "stale-chapter"
        sidecar.workSummary = .init(
            childrenHash: "stale-work", summary: "Outdated work", updatedAt: .now)

        let snapshot = StoryMemorySnapshot.make(
            scope: scope, outline: outline, sidecar: sidecar, body: body)

        XCTAssertEqual(snapshot.sceneSummaries.count, 3)
        XCTAssertNil(snapshot.sceneSummaries[outline.scenes[1].contentVersion])
        XCTAssertNil(snapshot.chapterSummaries[.chapter(path: ["Part", "One"])])
        XCTAssertNil(snapshot.workSummary)

        let secondChapter = StoryMemoryNodeID.chapter(path: ["Part", "Two"])
        let evidence = snapshot.evidence(for: secondChapter)
        XCTAssertEqual(evidence.count, 2)
        XCTAssertTrue(evidence.allSatisfy { $0.documentID == documentID })
        XCTAssertTrue(evidence.allSatisfy { $0.resolvedQuery(in: body) != nil })
        XCTAssertEqual(evidence.map(\.sceneHash), Array(outline.scenes[2...3]).map(\.contentHash))
    }

    private func outlineFixture(changedSecondScene: Bool) -> DocumentOutline {
        let hashes = ["one-a", changedSecondScene ? "one-b-edited" : "one-b", "two-a", "two-b"]
        return DocumentOutline(scenes: [
            .init(level: 3, headingPath: ["Part", "One", "A"], utf16Range: 0..<10, contentHash: hashes[0]),
            .init(level: 3, headingPath: ["Part", "One", "B"], utf16Range: 10..<20, contentHash: hashes[1]),
            .init(level: 3, headingPath: ["Part", "Two", "A"], utf16Range: 20..<30, contentHash: hashes[2]),
            .init(level: 3, headingPath: ["Part", "Two", "B"], utf16Range: 30..<40, contentHash: hashes[3]),
        ])
    }

    private func sequentialOutline(for body: String) -> DocumentOutline {
        let text = body as NSString
        var start = 0
        let paths = [
            ["Part", "One", "A"], ["Part", "One", "B"],
            ["Part", "Two", "A"], ["Part", "Two", "B"],
        ]
        let lines = body.components(separatedBy: "\n")
        let scenes = lines.enumerated().map { index, line -> DocumentOutline.Scene in
            let length = (line as NSString).length
            defer { start += length + (index == lines.count - 1 ? 0 : 1) }
            return .init(
                level: 3, headingPath: paths[index], utf16Range: start..<(start + length),
                contentHash: DocumentOutline.stableHash(line))
        }
        XCTAssertEqual(start, text.length)
        return DocumentOutline(scenes: scenes)
    }

    private func completeSidecar(for outline: DocumentOutline) -> KnowledgeSidecar {
        var sidecar = KnowledgeSidecar(entryID: UUID())
        for scene in outline.scenes {
            sidecar.sceneSummaries[scene.contentHash] = .init(
                contentHash: scene.contentHash, headingPath: scene.headingPath,
                summary: "Summary for \(scene.contentHash)", updatedAt: .now)
        }
        return sidecar
    }

    private func chapterSummaries(
        for outline: DocumentOutline
    ) -> [KnowledgeSidecar.ChapterSummary] {
        HierarchicalMemory.chapterGroups(in: outline).map { chapter in
            .init(
                headingPath: chapter.path, childrenHash: chapter.childrenHash,
                summary: "Summary for \(chapter.path.joined(separator: " / "))", updatedAt: .now)
        }
    }
}
