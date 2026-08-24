import XCTest

@testable import MINTCore

/// BackgroundIndexer 작업 소유권 — stale 작업이 최신 상태를 덮지 못하게 (#82 / #65 H3).
///
/// 계약: 선점(noteChange·전체 다시 읽기)마다 세대가 올라가고, 늦게 끝난 이전
/// 작업은 ① 핸들 정리(finishPass)도 ② 발행(canPublish)도 하지 못한다.
@MainActor
final class IndexerOwnershipTests: XCTestCase {

    private var root: URL!
    private var store: EntryStore!
    private var indexer: BackgroundIndexer!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-own-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        let settings = CompletionSettings()
        settings.autocompleteEnabled = false  // 네트워크 유발 방지
        indexer = BackgroundIndexer(engine: CompletionEngine(), settings: settings)
        indexer.attach(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeNovel() -> UUID {
        let id = store.newEntry(kind: .novel)
        store.select(id)
        return id
    }

    // MARK: - 세대 증가 (선점)

    func test선점마다세대가올라간다() {
        let id = store.newEntry(kind: .novel)
        let before = indexer.passGeneration

        indexer.noteChange(entryID: id)
        XCTAssertEqual(indexer.passGeneration, before + 1)

        indexer.requestFullPass()
        XCTAssertGreaterThanOrEqual(indexer.passGeneration, before + 1)
    }

    // MARK: - 늦은 이전 작업의 핸들 정리 차단 (#82 게이트 1)

    func test늦은이전작업은핸들정리와상태해제를못한다() {
        let a = makeNovel()
        indexer.noteChange(entryID: a)
        let tokenA = indexer.passGeneration

        // B가 선점 — 새 세대.
        let b = makeNovel()
        indexer.noteChange(entryID: b)
        let tokenB = indexer.passGeneration
        XCTAssertNotEqual(tokenA, tokenB)

        // B의 패스가 도는 중 상태를 주입한 뒤, A(늦은 이전)가 종료를 시도한다.
        let canary = Task<Void, Never> {}
        indexer._testInjectPassState(task: canary, indexing: true)

        indexer.finishPass(token: tokenA)
        // A 토큰 정리 후에도 B가 여전히 진행 중(isIndexing true)이어야 한다 —
        // 늦은 이전 작업이 B의 상태를 지우면 false로 떨어진다.
        if indexer.passGeneration == tokenB {
            XCTAssertTrue(indexer.isIndexing, "늦은 이전 작업이 B의 상태를 해제했다")
        }

        // B 자신의 정리는 정상 동작 — 취소 가능성 보존 (#82 회귀 마지막 조항).
        indexer.finishPass(token: tokenB)
        XCTAssertFalse(indexer.isIndexing)

        _ = canary
    }

    // MARK: - 발행 가드 (토큰·문서 일치)

    func test발행가드는토큰과문서일치를요구한다() {
        let a = makeNovel()
        let bodyA = "# 1장\n내용"
        let tokenA = indexer._testBeginPassForOwnership(entryID: a, body: bodyA)

        XCTAssertTrue(indexer.canPublish(token: tokenA, entryID: a))
        XCTAssertEqual(indexer.passBodyHash, BackgroundIndexer.contentFingerprint(bodyA))

        // 문서 전환(B 선점) → A 토큰·A 문서 발행 모두 거부.
        let b = makeNovel()
        indexer.noteChange(entryID: b)
        XCTAssertFalse(indexer.canPublish(token: tokenA, entryID: a), "stale 토큰이 통과됐다")
        XCTAssertFalse(indexer.canPublish(token: tokenA, entryID: b))

        // B 토큰으로 A 문서에 발행하는 것도 거부 — entryID 가드 (#82).
        let tokenB = indexer.passGeneration
        XCTAssertFalse(indexer.canPublish(token: tokenB, entryID: a))
        XCTAssertTrue(indexer.canPublish(token: tokenB, entryID: b) || indexer.passEntryID != b)
    }

    func test같은문서v1_v2편집은v1발행을막는다() {
        let id = makeNovel()
        let v1 = "# 1장\n초판"
        let token1 = indexer._testBeginPassForOwnership(entryID: id, body: v1)
        let hashV1 = indexer.passBodyHash

        // 본문 편집 → noteChange 재진입 (실제 편집 경로).
        store.updateActiveBody("# 1장\n개정판")
        indexer.noteChange(entryID: id)
        let token2 = indexer._testBeginPassForOwnership(entryID: id, body: "# 1장\n개정판")

        XCTAssertNotEqual(hashV1, indexer.passBodyHash, "본문 지문이 갱신돼야 한다")
        XCTAssertFalse(indexer.canPublish(token: token1, entryID: id),
                       "v1 시점 작업이 v2 위에 발행할 수 있다")
        XCTAssertTrue(indexer.canPublish(token: token2, entryID: id))
    }

    // MARK: - hydrate 소유권

    func testhydrate세대도요청마다올라간다() {
        let id = makeNovel()
        store.updateActiveBody("# 1장\n내용이 충분히 긴 본문")
        let before = indexer.hydrateGeneration
        indexer.rehydrate(entryID: id)
        XCTAssertEqual(indexer.hydrateGeneration, before + 1)
    }
}
