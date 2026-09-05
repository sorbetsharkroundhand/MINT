import XCTest

@testable import MINTCore

/// 구조 변경 Undo와 휴지통 (이슈 #9).
///
/// 계약: 저널·폴더 삭제/이동/재정렬, 종류 전환, 바이블 메타(인물·분석 결과)
/// 변경이 ⌘Z/⇧⌘Z로 복원되고, 삭제는 휴지통에 남아 나중에도 복구되며,
/// asset은 유예 기간(AssetJanitor) 동안 절대 지워지지 않는다.
final class StructureUndoTests: XCTestCase {

    private var root: URL!
    private var store: EntryStore!
    private var windows: [NSWindow] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MINT-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        windows.removeAll()
        try? FileManager.default.removeItem(at: root)
    }

    /// 창의 undo manager를 배선한다 — 베어 UndoManager()는 첫 등록 때 유령
    /// 외부 그룹을 만들어 그룹 경계가 무너진다(실앱은 창이 관리).

    @MainActor
    private func makeStore() -> EntryStore {
        let store = EntryStore(directory: root, autosaveDelay: .seconds(3600))
        let storage = NSTextStorage()
        let layoutManager = MintLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = BlockTextView(
            frame: NSRect(x: 0, y: 0, width: 700, height: 900), textContainer: container)
        view.allowsUndo = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(view)
        window.makeFirstResponder(view)
        windows.append(window)
        guard let um = view.undoManager else {
            fatalError("창 기반 undo manager 없음")
        }
        store.structureUndoManager = um
        self.store = store
        self.undoManager = um
        return store
    }

    private var undoManager: UndoManager!

    /// 헤드리스에선 이벤트 주기가 undo 그룹을 열어주지 않는다 — 연산별로
    /// 명시 묶어 앱의 "사용자 동작 1회 = undo 1단계"를 재현한다.
    @MainActor
    private func grouped(_ body: () -> Void) {
        // 텍스트 시스템이 선(先)으로 열어 둔 그룹이 있을 수 있으므로, 연산 후
        // 레벨 0까지 전부 닫는다 — 이 연산만이 하나의 undo 단위가 된다.
        undoManager.beginUndoGrouping()
        body()
        while undoManager.groupingLevel > 0 {
            undoManager.endUndoGrouping()
        }
    }

    // MARK: - 저널 삭제 · undo

    @MainActor
    func test저널삭제는undo로본문째복원된다() throws {
        let store = makeStore()
        let id = store.newEntry()
        store.updateActiveBody("1장\n\n주인공이 말했다.")
        store.flush()

        store.delete(id)
        XCTAssertFalse(store.entries.contains { $0.id == id })

        undoManager.undo()
        let restored = try XCTUnwrap(store.entries.first { $0.id == id })
        XCTAssertEqual(restored.body, "1장\n\n주인공이 말했다.")

        // redo — ⇧⌘Z
        undoManager.redo()
        XCTAssertFalse(store.entries.contains { $0.id == id })

        // 휴지통에는 내구 사본이 남는다 — 앱을 다시 열어도 복구 가능.
        XCTAssertEqual(store.trash.items.count, 1)
        XCTAssertEqual(store.trash.items[0].entries.first?.id, id)
    }

    @MainActor
    func test폴더삭제는하위트리째undo된다() throws {
        let store = makeStore()
        let folder = store.newFolder()
        let child = store.newEntry(in: folder)
        XCTAssertNotNil(store.entries.first { $0.id == child })
        store.flush()

        store.deleteFolder(folder)
        XCTAssertFalse(store.folders.contains { $0.id == folder })
        XCTAssertFalse(store.entries.contains { $0.id == child })

        undoManager.undo()
        XCTAssertTrue(store.folders.contains { $0.id == folder }, "폴더가 복원됐다")
        XCTAssertTrue(store.entries.contains { $0.id == child }, "폴더 안 저널이 함께 복원됐다")

        // 휴지통 묶음 — 폴더 + 저널이 한 항목으로.
        let item = store.trash.items.first
        XCTAssertEqual(item?.folders.first?.id, folder)
        XCTAssertEqual(item?.entries.first?.id, child)
    }

    @MainActor
    func test이동과재정렬이undo_redo된다() throws {
        let store = makeStore()
        let folder = store.newFolder()
        let a = store.newEntry()  // 루트
        _ = store.newEntry()      // 루트
        let b = store.newEntry(in: folder)

        // 폴더 → 루트 이동
        store.move(b, toFolder: nil)
        XCTAssertEqual(store.entries.first { $0.id == b }?.folderID, nil)

        undoManager.undo()
        XCTAssertEqual(store.entries.first { $0.id == b }?.folderID, folder)

        undoManager.redo()
        XCTAssertEqual(store.entries.first { $0.id == b }?.folderID, nil)
        _ = a
    }

    // MARK: - 바이블 메타 · 종류 전환

    @MainActor
    func test인물삭제와종류전환은undo된다() throws {
        let store = makeStore()
        let id = store.newEntry(kind: .novel)
        let card = CharacterCard(name: "한결", note: "주인공")
        grouped { store.upsertCharacter(card, in: id) }

        grouped { store.removeCharacter(card.id, from: id) }
        XCTAssertTrue(store.entries.first { $0.id == id }?.characters?.isEmpty ?? true)

        undoManager.undo()
        XCTAssertEqual(
            store.entries.first { $0.id == id }?.characters?.first?.name, "한결")

        grouped { store.setKind(.journal, for: id) }
        XCTAssertEqual(store.entries.first { $0.id == id }?.kind, .journal)

        undoManager.undo()
        XCTAssertEqual(store.entries.first { $0.id == id }?.resolvedKind, .novel)
    }

    // MARK: - 휴지통 복원

    @MainActor
    func test휴지통에서복구하면문서로돌아온다() throws {
        let store = makeStore()
        let id = store.newEntry()
        store.updateActiveBody("영원히 잃지 않을 원고")

        store.delete(id)
        XCTAssertNil(store.entries.first { $0.id == id })
        guard let itemID = store.trash.items.first?.id else {
            return XCTFail("휴지통 항목 없음")
        }
        store.restoreFromTrash(itemID: itemID)

        let restored = try XCTUnwrap(store.entries.first { $0.id == id })
        XCTAssertEqual(restored.body, "영원히 잃지 않을 원고")
        XCTAssertTrue(store.trash.items.isEmpty, "복원 후엔 휴지통에서 사라진다")
    }

    // MARK: - GC 유예 (#9 완료 조건 3 — AssetJanitor와의 승계)

    @MainActor
    func test삭제후유예기간에는asset이살아있다() throws {
        let imagesDir = root.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try Data([0x89]).write(to: imagesDir.appendingPathComponent("cover.png"))
        MainActor.assumeIsolated { MintImageStore.setDirectoryOverride(root) }
        defer { MainActor.assumeIsolated { MintImageStore.setDirectoryOverride(nil) } }

        let store = makeStore()
        let id = store.newEntry()
        store.updateActiveBody("![표지](images/cover.png)")
        AssetJanitor.record("images/cover.png")

        store.delete(id)  // 문단 삭제 — asset은 장부 후보일 뿐

        // 유예 기간 안의 청소는 아무것도 지우지 않는다 (redo 가능 기간).
        let removedNow = AssetJanitor.sweepAll(bodies: store.entries.map(\.body))
        XCTAssertTrue(removedNow.isEmpty, "유예 중인데 지웠다: \(removedNow)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesDir.appendingPathComponent("cover.png").path))
    }
}
