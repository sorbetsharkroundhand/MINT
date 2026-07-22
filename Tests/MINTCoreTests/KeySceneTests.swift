@testable import MINTCore
import XCTest

final class KeySceneTests: XCTestCase {
    func test레거시JSON과_핵심장면_왕복() throws {
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","title":"옛 원고","createdAt":"2026-07-21T00:00:00Z","body":"본문"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(JournalEntry.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.keyScenes)

        let scene = KeyScene(title: "문이 열린다", summary: "서연이 문을 연다")
        let entry = JournalEntry(title: "원고", body: "본문", kind: .novel, keyScenes: [scene])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let roundTrip = try decoder.decode(JournalEntry.self, from: encoder.encode(entry))
        XCTAssertEqual(roundTrip.keyScenes?.first?.id, scene.id)
        XCTAssertEqual(roundTrip.keyScenes?.first?.title, scene.title)
        XCTAssertEqual(roundTrip.keyScenes?.first?.status, .planned)
    }

    func test앞부분삽입_뒤에도_UUID를_유지하며_재앵커() {
        let original = "# 1장\n서연은 잠긴 문을 힘껏 열었다.\n뒤 문장"
        let ns = original as NSString
        let found = ns.range(of: "서연은 잠긴 문을 힘껏 열었다.")
        let id = UUID()
        let scene = KeyScene(
            id: id, title: "문", summary: "문을 연다",
            sourceRange: found.location ..< (found.location + found.length),
            anchorSnippet: "서연은 잠긴 문을 힘껏 열었다.", status: .drafted
        )

        let inserted = "프롤로그\n" + original
        let result = KeySceneReconciler.reconcile([scene], in: inserted)
        XCTAssertEqual(result.scenes[0].id, id)
        XCTAssertEqual(result.scenes[0].sourceRange?.lowerBound, found.location + 5)
        XCTAssertTrue(result.staleIDs.isEmpty)
    }

    func test재앵커실패는_삭제하지_않고_stale로_보존() {
        let scene = KeyScene(
            title: "사라진 근거", sourceRange: 0 ..< 4,
            anchorSnippet: "없는 문장", status: .drafted
        )
        let result = KeySceneReconciler.reconcile([scene], in: "다른 본문")
        XCTAssertEqual(result.scenes, [scene])
        XCTAssertEqual(result.staleIDs, [scene.id])
    }

    func test계획형은_범위없이_저장되고_재앵커대상이_아님() {
        let scene = KeyScene(title: "결전", status: .planned, authorConfirmed: true)
        let result = KeySceneReconciler.reconcile([scene], in: "아직 쓰지 않은 원고")
        XCTAssertNil(result.scenes[0].sourceRange)
        XCTAssertTrue(result.staleIDs.isEmpty)
        XCTAssertTrue(result.scenes[0].authorConfirmed)
    }

    func test규칙후보는_중요사건만_결정적으로_제안하고_등록분은_제외() {
        let body = "# 1장\n서연은 돌아오지 않기로 결정했다."
        let outline = DocumentOutline.parse(body)
        let event = StoryEvent(
            sceneHash: outline.scenes[0].contentHash, participants: [],
            summary: "서연이 떠나기로 결정한다", importance: 5,
            quote: "서연은 돌아오지 않기로 결정했다."
        )
        let first = KeySceneCandidateDetector.detect(
            outline: outline, events: [event], body: body, existing: []
        )
        let second = KeySceneCandidateDetector.detect(
            outline: outline, events: [event], body: body, existing: []
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(KeySceneCandidateDetector.detect(
            outline: outline, events: [event], body: body, existing: [],
            ignoredInputHashes: [first[0].inputHash]
        ).isEmpty)

        let registered = KeyScene(
            title: first[0].proposedTitle, summary: event.summary,
            sourceRange: outline.scenes[0].utf16Range, status: .drafted
        )
        XCTAssertTrue(KeySceneCandidateDetector.detect(
            outline: outline, events: [event], body: body, existing: [registered]
        ).isEmpty)
    }
}
