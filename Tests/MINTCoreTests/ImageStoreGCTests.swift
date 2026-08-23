import XCTest

@testable import MINTCore

/// 이미지 GC 금지 회귀 (이슈 #7).
///
/// 과거 정규식 기반 `pruneUnreferenced`는 title·angle destination·괄호·
/// reference 문법을 참조로 인정하지 않아, 다른 저널을 삭제하는 것만으로
/// 실제 사용 중인 asset을 영구 삭제했다. 파서 기반 참조 모델(#12)과 지연
/// GC(#17)가 오기 전까지 **자동 삭제 자체가 없어야 한다** — 이 테스트는
/// 그 불변조건을 모든 지원 문법에 대해 고정해, 삭제 로직의 재도입을 막는다.
final class ImageStoreGCTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-gc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("images"), withIntermediateDirectories: true)
        MintImageStore.setDirectoryOverride(root)
    }

    override func tearDownWithError() throws {
        MintImageStore.setDirectoryOverride(nil)
        try? FileManager.default.removeItem(at: root)
    }

    /// (asset 파일명, 그 asset을 심는 본문) 목록 — 과거 GC가 오판했던 문법 하나씩.
    private var cases: [(file: String, body: String)] {
        [
            ("cover.png", "![표지](images/cover.png)"),
            ("titled.png", #"![표지](images/titled.png "첫 장면")"#),
            ("with space.png", "![]( <images/with space.png> )"),
            ("frame(1).png", "![](images/frame(1).png)"),
            ("ref.png", "![표지][r1]\n\n[r1]: images/ref.png"),
            ("dotted.png", "![](./images/dotted.png)"),
        ]
    }

    @MainActor
    func test다른저널삭제는모든문법의참조이미지를살려둔다() throws {
        let store = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        var expectedFiles: Set<String> = []
        var createdIDs: [UUID] = []

        for (file, template) in cases {
            let id = store.newEntry()
            store.updateActiveBody(template)
            createdIDs.append(id)
            try Data([0x89]).write(to: root.appendingPathComponent("images").appendingPathComponent(file))
            expectedFiles.insert(file)
        }
        XCTAssertEqual(store.entries.count, createdIDs.count + 1)

        // 마지막 저널 하나만 남긴다 — 과거엔 이 동작이 참조 이미지를 지웠다.
        for id in createdIDs {
            if store.entries.count > 1 { store.delete(id) }
        }
        XCTAssertEqual(store.entries.count, 1)

        let survivors = Set(try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("images"), includingPropertiesForKeys: nil)
            .map(\.lastPathComponent))
        XCTAssertEqual(survivors, expectedFiles, "참조 중인 asset이 삭제됐다 — GC 재도입 의심")
    }

    @MainActor
    func test고아이미지도자동삭제되지않는다() throws {
        // 고아 정리는 #12/#17의 지연 GC 몫 — 그때까지는 아무도 지우지 않는다.
        let orphan = root.appendingPathComponent("images").appendingPathComponent("orphan.png")
        try Data([0x89]).write(to: orphan)

        let store = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        store.newEntry()
        store.delete(store.entries[0].id)
        store.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    }
}
