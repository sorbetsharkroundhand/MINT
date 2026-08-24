import XCTest

@testable import MINTCore

/// 동일 값 `@Published` 쓰기 가드 (이슈 #51 / #65 Phase 4).
///
/// 계약: 값이 실제로 바뀌지 않으면 objectWillChange가 발생하지 않는다 — 특히
/// noteChange(키 입력당)의 isIndexing 해제와 타이핑 중 isPredicting 토글이
/// ModelChip 애니메이션을 잘못 진동시키지 않게 한다.
@MainActor
final class PublishedWriteGuardTests: XCTestCase {

    func test유휴상태선점은published변화를만들지않는다() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-pub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        let settings = CompletionSettings()
        settings.autocompleteEnabled = false
        let indexer = BackgroundIndexer(engine: CompletionEngine(), settings: settings)
        indexer.attach(store: store)

        var willChangeCount = 0
        let token = indexer.objectWillChange.sink { willChangeCount += 1 }

        // 패스가 도는 중이 아닐 때의 연속 선점 — 상태 변화가 없어야 한다.
        let id = store.newEntry(kind: .novel)
        indexer.noteChange(entryID: id)
        indexer.noteChange(entryID: id)

        XCTAssertEqual(willChangeCount, 0, "동일 값 쓰기가 \(willChangeCount)번 발행됐다")
        XCTAssertFalse(indexer.isIndexing)
        token.cancel()
    }
}
