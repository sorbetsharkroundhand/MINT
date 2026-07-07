import SwiftUI

/// 메뉴 막대 명령 (에디터 v3 — 상용 v1.0).
///
/// 단일 `Window` 씬으로 바꾸며 ⌘N을 "새 저널"로 되돌린다(예전엔 새 창을 열어
/// 같은 파일에 별도 저장소가 붙는 위험이 있었다). 서식·보기 명령은 뒤 커밋에서
/// 리스폰더 체인으로 확장한다.
public struct MintCommands: Commands {
    let store: EntryStore

    public init(store: EntryStore) {
        self.store = store
    }

    public var body: some Commands {
        // 파일 ▸ 새 저널/폴더 — ⌘N을 새 창이 아니라 새 저널에 묶는다.
        CommandGroup(replacing: .newItem) {
            Button("새 저널") { store.newEntry() }
                .keyboardShortcut("n", modifiers: .command)
            Button("새 폴더") { store.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
