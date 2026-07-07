import AppKit
import SwiftUI

/// 메뉴 막대 명령 (에디터 v3 — 상용 v1.0).
///
/// 단일 `Window` 씬으로 바꾸며 ⌘N을 "새 저널"로 되돌린다. 서식·정렬·목록 명령은
/// 리스폰더 체인(NSApp.sendAction)으로 포커스된 `BlockTextView`에 도달한다 —
/// 단축키의 단일 소스라 에디터의 performKeyEquivalent과 이중 처리되지 않는다.
public struct MintCommands: Commands {
    let store: EntryStore
    @AppStorage("mint.appearance") private var appearance = ""
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true

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

        // 서식 ▸ 텍스트 스타일 · 블록 · 정렬 · 이미지.
        CommandMenu("서식") {
            Button("굵게") { send(#selector(BlockTextView.mintFormatBold(_:))) }
                .keyboardShortcut("b", modifiers: .command)
            Button("기울임") { send(#selector(BlockTextView.mintFormatItalic(_:))) }
                .keyboardShortcut("i", modifiers: .command)
            Button("인라인 코드") { send(#selector(BlockTextView.mintFormatCode(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("본문") { send(#selector(BlockTextView.mintBodyText(_:))) }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Button("제목 1") { send(#selector(BlockTextView.mintHeading1(_:))) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("제목 2") { send(#selector(BlockTextView.mintHeading2(_:))) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("제목 3") { send(#selector(BlockTextView.mintHeading3(_:))) }
                .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Button("글머리 목록") { send(#selector(BlockTextView.mintBulletList(_:))) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("번호 목록") { send(#selector(BlockTextView.mintNumberedList(_:))) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("인용") { send(#selector(BlockTextView.mintQuoteBlock(_:))) }
            Button("코드 블록") { send(#selector(BlockTextView.mintCodeBlock(_:))) }

            Divider()

            Button("왼쪽 정렬") { send(#selector(BlockTextView.mintAlignLeft(_:))) }
            Button("가운데 정렬") { send(#selector(BlockTextView.mintAlignCenter(_:))) }
            Button("오른쪽 정렬") { send(#selector(BlockTextView.mintAlignRight(_:))) }

            Divider()

            Button("이미지 삽입…") { send(#selector(BlockTextView.insertImageFromMenu(_:))) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        // 보기 ▸ 검색 · 사이드바 · 외형.
        CommandMenu("보기") {
            Button("저널 검색") {
                sidebarVisible = true
                store.requestSearchFocus()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button(sidebarVisible ? "파일 목록 숨기기" : "파일 목록 보이기") {
                sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button(effectiveDark ? "라이트 모드" : "다크 모드") {
                appearance = effectiveDark ? "light" : "dark"
            }
            Button("시스템 외형 따르기") { appearance = "" }
        }
    }

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    /// 현재 유효 외형이 다크인가 — 명시값이 있으면 그대로, "시스템 따름"이면 실제
    /// 시스템 외형으로 판단한다.
    private var effectiveDark: Bool {
        switch appearance {
        case "dark": return true
        case "light": return false
        default:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}
