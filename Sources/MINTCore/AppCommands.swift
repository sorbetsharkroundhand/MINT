import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 메뉴 막대 명령 (에디터 v3 — 상용 v1.0).
///
/// 단일 `Window` 씬으로 바꾸며 ⌘N을 "새 저널"로 되돌린다. 서식·정렬·목록 명령은
/// 리스폰더 체인(NSApp.sendAction)으로 포커스된 `BlockTextView`에 도달한다 —
/// 단축키의 단일 소스라 에디터의 performKeyEquivalent과 이중 처리되지 않는다.
/// 에디터(BlockTextView 서브트리)에 포커스가 있는가 — 서식·찾기 명령의
/// 실행 가능 판정용 (이슈 #26). 사용처는 ContentView의 에디터 체인.
struct HasMintEditorKey: FocusedValueKey {
    typealias Value = Bool
}
extension FocusedValues {
    var hasMintEditor: Bool? {
        get { self[HasMintEditorKey.self] }
        set { self[HasMintEditorKey.self] = newValue }
    }
}

public struct MintCommands: Commands {
    let store: EntryStore
    /// 에디터 포커스 여부 — 없으면 서식·찾기 명령을 비활성화해 "눌러도 무반응"을
    /// 없앤다 (이슈 #26).
    @FocusedValue(\.hasMintEditor) private var hasMintEditor
    @AppStorage("mint.appearance") private var appearance = ""
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @AppStorage("mint.chromeHidden") private var chromeHidden = false

    public init(store: EntryStore) {
        self.store = store
    }

    public var body: some Commands {
        // 파일 ▸ 새 저널/폴더 — ⌘N을 새 창이 아니라 새 저널에 묶는다.
        CommandGroup(replacing: .newItem) {
            Button("새 저널") { store.newEntry() }
                .keyboardShortcut("n", modifiers: .command)
            Button("새 소설") { store.newEntry(kind: .novel) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("새 폴더") { store.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        // 파일 저장 영역 옆에 이름 바꾸기 · 내보내기 · 인쇄.
        CommandGroup(after: .saveItem) {
            Button("저널 이름 바꾸기") {
                sidebarVisible = true
                store.requestRename()
            }

            Divider()

            Button("Markdown으로 내보내기…") { exportMarkdown() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            // 소설을 전자책으로 (요구 7) — 소설이 아닌 저널도 내보낼 수는 있다.
            Button("EPUB으로 내보내기…") { exportEpub() }
            // 인쇄는 first responder가 아니라 **현재 저널 전용 뷰**로 — 검색창·
            // 사이드바 포커스에서 엉뚱한 대상을 찍지 않게 (이슈 #26).
            Button("인쇄…") { printActiveManuscript() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(store.activeEntry == nil)
        }

        // 서식 ▸ 텍스트 스타일 · 블록 · 정렬 · 이미지.
        // 편집 대상 명령이므로 에디터 포커스가 없으면 메뉴째 비활성 (이슈 #26).
        CommandMenu("서식") {
            Group {
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
            .disabled(hasMintEditor != true)
        }

        // 보기 ▸ 검색 · 사이드바 · 외형.
        CommandMenu("보기") {
            // 문서 내 검색 — 에디터의 performKeyEquivalent(⌘F)가 우선 처리하고,
            // 한글 IME 등으로 뷰에 닿지 못한 경우 이 메뉴가 안전망이 된다.
            Group {
                Button("문서에서 찾기") { send(#selector(BlockTextView.mintFindInDocument(_:))) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("다음 찾기") { send(#selector(BlockTextView.mintFindNext(_:))) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("이전 찾기") { send(#selector(BlockTextView.mintFindPrevious(_:))) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            .disabled(hasMintEditor != true)

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

            Button(chromeHidden ? "집중 모드 끄기" : "집중 모드") {
                chromeHidden.toggle()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("글자 크게") { CompletionSettings.shared.editorFontSize += 1 }
                .keyboardShortcut("+", modifiers: .command)
            Button("글자 작게") { CompletionSettings.shared.editorFontSize -= 1 }
                .keyboardShortcut("-", modifiers: .command)
            Button("기본 글자 크기") {
                CompletionSettings.shared.editorFontSize = CompletionSettings.defaultFontSize
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button(effectiveDark ? "라이트 모드" : "다크 모드") {
                appearance = effectiveDark ? "light" : "dark"
            }
            Button("시스템 외형 따르기") { appearance = "" }
        }
    }

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    /// 편집 대상 명령 공통 — 에디터 포커스가 없으면 비활성(무반응 제거, 이슈 #26).
    @ViewBuilder
    private func editCommand<Content: View>(_ title: String, shortcut: KeyEquivalent? = nil,
        modifiers: EventModifiers = [.command], _ action: @escaping () -> Void,
        @ViewBuilder content: () -> Content) -> some View {
        Button(title, action: action)
            .modifier(OptionalShortcut(shortcut: shortcut, modifiers: modifiers))
            .disabled(hasMintEditor != true)
        content()
    }

    struct OptionalShortcut: ViewModifier {
        let shortcut: KeyEquivalent?
        let modifiers: EventModifiers
        func body(content: Content) -> some View {
            if let shortcut {
                content.keyboardShortcut(shortcut, modifiers: modifiers)
            } else {
                content
            }
        }
    }

    /// 현재 저널을 일반 Markdown(.md)으로 내보낸다 — 이미지 asset을 목적지 옆
    /// `images/`로 복사하고 상대경로를 고쳐 외부 편집기에서도 이미지가 살아
    /// 있게 한다 (이슈 #13).
    private func exportMarkdown() {
        guard let entry = store.activeEntry else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(sanitizedFileName(entry.title)).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // 누락 asset을 미리 검증해 명시적 계속을 받는다 (이슈 #15) —
            // 조용히 깨진 참조만 남은 결과물을 만들지 않는다.
            guard ImageAssetScanner.confirmContinueDespiteMissing(in: entry.body) else {
                return
            }
            let report = try MarkdownExporter.export(entry, to: url)
            // 성공 위치를 명시한다 — 어디에 저장됐는지 사용자가 바로 확인 (이슈 #10).
            NSWorkspace.shared.activateFileViewerSelecting([url])
            // 소스 정책 경고 (이슈 #13) — 복사 못 한/안 한 참조가 있으면 조용한
            // 성공으로 오해하지 않게 알려준다.
            var notes: [String] = []
            if !report.missingSources.isEmpty {
                notes.append("원본 파일을 찾지 못한 이미지 \(report.missingSources.count)건은 참조를 그대로 남겼어요:\n\(report.missingSources.joined(separator: ", "))")
            }
            if report.remoteCount > 0 {
                notes.append("웹 이미지 \(report.remoteCount)건은 주소 그대로 내보냈어요 — 오프라인에서는 안 보일 수 있어요.")
            }
            if report.blockedCount > 0 {
                notes.append("해석할 수 없는 참조 \(report.blockedCount)건은 그대로 남겼어요.")
            }
            if !notes.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Markdown 내보내기 완료"
                alert.informativeText = notes.joined(separator: "\n\n")
                alert.alertStyle = .warning
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Markdown 내보내기 실패"
            alert.informativeText = "대상: \(url.path)\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// 현재 저널을 EPUB 3 전자책으로 저장한다 (요구 7 — 소설 내보내기).
    private func exportEpub() {
        guard let entry = store.activeEntry else { return }
        EpubExporter.exportWithPanel(entry)
    }

    /// 현재 저널을 전용 뷰로 조립해 인쇄한다 — 포커스와 무관하게 항상 같은
    /// 원고가 나온다 (이슈 #26). 마크다운 마커는 그대로 두되 세리프 본문으로.
    private func printActiveManuscript() {
        guard let entry = store.activeEntry else { return }
        let page = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 620, height: 792))
        page.textStorage?.setAttributedString(NSAttributedString(
            string: entry.body.isEmpty ? "(빈 원고)" : entry.body,
            attributes: [
                .font: MintFonts.serif(12),
                .foregroundColor: NSColor.black,
                .paragraphStyle: {
                    let ps = NSMutableParagraphStyle()
                    ps.lineSpacing = 6
                    return ps
                }(),
            ]))
        page.printView(nil)
    }

    /// 파일 이름에 쓸 수 없는 문자를 정리한다.
    private func sanitizedFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "저널" : String(cleaned.prefix(60))
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
