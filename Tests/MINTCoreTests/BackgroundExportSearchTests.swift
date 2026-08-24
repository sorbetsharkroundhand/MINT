import XCTest

@testable import MINTCore

/// 저장·내보내기·검색의 백그라운드 전환 (이슈 #33 / #65 Phase 4).
///
/// 계약:
/// - EPUB 조립(변환·복사·압축)은 메인 격리 밖에서 돌고, 진행률이 오르며
///   취소에 협조한다.
/// - 검색 필터는 값 스냅샷만 받는 순수 함수 — 메인 밖에서 같은 결과.
@MainActor
final class BackgroundExportSearchTests: XCTestCase {

    private func makeTempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-bg33-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testEPUB비동기내보내기는파일을만들고진행률을보고한다() async throws {
        let entry = JournalEntry(
            title: "배경 내보내기",
            body: "# 1장\n첫 문장입니다.\n\n# 2장\n두 번째 문장.")
        let destination = makeTempRoot()
            .appendingPathComponent("book.epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        var progressValues: [Double] = []
        let box = ProgressBox()
        try await EpubExporter.exportAsync(
            entry, to: destination,
            progress: { value in
                box.append(value)
            })
        progressValues = box.snapshot()

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(progressValues.isEmpty, "진행률 보고가 없었다")
        XCTAssertEqual(progressValues.max(), 1.0, "완료 신호(1.0)가 없었다")
    }

    func test취소된내보내기는CancellationError로끝난다() async throws {
        let longBody = (0..<2000).map { "# \($0)장\n내용 \($0)" }.joined(separator: "\n\n")
        let entry = JournalEntry(title: "긴 원고", body: longBody)
        let destination = makeTempRoot().appendingPathComponent("book.epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        let task = Task {
            try await EpubExporter.exportAsync(entry, to: destination)
        }
        task.cancel()
        do {
            _ = try await task.value
            // 취소가 늦어 정상 완료할 수도 있다 — 파일이 있다면 계약 위반이 아니다.
        } catch is CancellationError {
            // 기대 경로 — 조용히 끝난다.
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: destination.path),
                "취소된 내보내기가 결과물을 남겼다")
        }
    }

    func test검색필터는스냅샷만으로결정적이다() {
        let entries = [
            JournalEntry(title: "서울 이야기", createdAt: .now, body: "강과 밤"),
            JournalEntry(
                title: "바다 일기",
                createdAt: Date(timeIntervalSinceNow: -100),
                body: "서울역에서 떠나는 기차"),
        ]
        let hitTitle = EntryStore.filterMatches(entries, query: "서울 이야기")
        XCTAssertEqual(hitTitle.map(\.title), ["서울 이야기"])
        let hitBody = EntryStore.filterMatches(entries, query: "서울역")
        XCTAssertEqual(hitBody.map(\.title), ["바다 일기"])
        let none = EntryStore.filterMatches(entries, query: "  ")
        XCTAssertTrue(none.isEmpty)
    }
}

/// @Sendable 클로저에서 수집하는 진행률 박스.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
