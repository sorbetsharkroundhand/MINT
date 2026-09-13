import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 메뉴 막대 명령 (에디터 v3 — 상용 v1.0).
///
/// 단일 `Window` 씬에서 ⌘N은 활성 프로젝트의 새 문서를 만든다. 서식·정렬·목록 명령은
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

/// Testable command routing for mutations owned by the active project session.
@MainActor
public struct ProjectCommandActions {
    public let newDocument: (WritingDocument.Kind) -> Void
    public let renameDocument: (String) -> Void
    public let trashDocument: () -> Void
    public let restoreDocument: (WritingDocumentID) -> Void
    public let save: () async throws -> Void

    public init(session: ProjectSession) {
        newDocument = { kind in
            session.createDocument(kind: kind)
        }
        renameDocument = { title in
            session.renameSelectedDocument(to: title)
        }
        trashDocument = {
            session.trashSelectedDocument()
        }
        restoreDocument = { id in
            session.restoreDocument(id)
        }
        save = {
            try await session.flush()
        }
    }
}

public struct MintCommands: Commands {
    @ObservedObject private var session: ProjectSession
    @ObservedObject private var editorRequests: ProjectEditorRequests
    private let projectStore: ProjectStore
    /// 에디터 포커스 여부 — 없으면 서식·찾기 명령을 비활성화해 "눌러도 무반응"을
    /// 없앤다 (이슈 #26).
    @FocusedValue(\.hasMintEditor) private var hasMintEditor
    @AppStorage("mint.appearance") private var appearance = ""
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @AppStorage("mint.chromeHidden") private var chromeHidden = false

    public init(
        session: ProjectSession,
        projectStore: ProjectStore,
        editorRequests: ProjectEditorRequests
    ) {
        self._session = ObservedObject(wrappedValue: session)
        self.projectStore = projectStore
        self._editorRequests = ObservedObject(wrappedValue: editorRequests)
    }

    public var body: some Commands {
        // 파일 ▸ 프로젝트 문서와 verified project creation/import flows.
        CommandGroup(replacing: .newItem) {
            Button("새 문서") {
                ProjectCommandActions(session: session).newDocument(.manuscript)
                editorRequests.focusEditor()
            }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(session.activeProject == nil)

            Divider()

            Button("새 Fiction 프로젝트…") { presentNewProject(mode: .fiction) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("새 General 프로젝트…") { presentNewProject(mode: .general) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("레거시 라이브러리 가져오기…") { presentLegacyImport() }
        }

        CommandGroup(replacing: .saveItem) {
            Button("저장") {
                Task { try? await ProjectCommandActions(session: session).save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(session.activeProject == nil)
        }

        // 파일 저장 영역 옆에 이름 바꾸기 · 내보내기 · 인쇄.
        CommandGroup(after: .saveItem) {
            Button("문서 이름 바꾸기") {
                sidebarVisible = true
                editorRequests.beginRename()
            }

            Button("문서를 휴지통으로 이동", role: .destructive) {
                ProjectCommandActions(session: session).trashDocument()
                editorRequests.focusEditor()
            }
            .disabled(session.selectedDocument == nil)

            Divider()

            Button("Markdown으로 내보내기…") { presentProjectExportUnavailable() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("EPUB으로 내보내기…") { presentProjectExportUnavailable() }
            Button("인쇄…") { printActiveManuscript() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(session.selectedDocument == nil)
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

            Button("프로젝트 검색") {
                sidebarVisible = true
                editorRequests.focusSearch()
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

    private func presentNewProject(mode: WritingMode) {
        let alert = NSAlert()
        alert.messageText = mode == .fiction ? "새 Fiction 프로젝트" : "새 General 프로젝트"
        alert.informativeText = "프로젝트 이름을 입력하세요."
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        titleField.placeholderString = "프로젝트 이름"
        alert.accessoryView = titleField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                try await ProjectCreationCoordinator(session: session)
                    .createProject(title: titleField.stringValue, mode: mode)
                editorRequests.focusEditor()
            } catch {
                presentError(title: "프로젝트를 만들지 못했습니다", error: error)
            }
        }
    }

    private func presentLegacyImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "가져올 레거시 entries.json을 선택하세요. 원본은 변경되지 않습니다."
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let modeAlert = NSAlert()
        modeAlert.messageText = "가져올 프로젝트 종류"
        modeAlert.informativeText = "원고에 맞는 작업 공간을 선택하세요."
        modeAlert.addButton(withTitle: "Fiction")
        modeAlert.addButton(withTitle: "General")
        modeAlert.addButton(withTitle: "취소")
        let response = modeAlert.runModal()
        guard response != .alertThirdButtonReturn else { return }
        let mode: WritingMode = response == .alertFirstButtonReturn ? .fiction : .general
        let sourceTitle = sourceURL.deletingPathExtension().lastPathComponent
        let title = sourceTitle == "entries" ? "Imported Project" : sourceTitle

        Task { @MainActor in
            do {
                try await ImportProjectCoordinator(store: projectStore, session: session)
                    .importLegacy(from: sourceURL, mode: mode, title: title)
                editorRequests.focusEditor()
            } catch {
                presentError(title: "가져오지 못했습니다", error: error)
            }
        }
    }

    /// Project export is intentionally unavailable until the project-aware exporter lands.
    private func presentProjectExportUnavailable() {
        let alert = NSAlert()
        alert.messageText = "프로젝트 내보내기 준비 중"
        alert.informativeText = "현재 프로젝트를 레거시 저널로 변환하지 않고 내보내는 기능을 준비하고 있습니다."
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    private func printActiveManuscript() {
        guard let document = session.selectedDocument else { return }
        let page = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 620, height: 792))
        page.textStorage?.setAttributedString(NSAttributedString(
            string: document.body.isEmpty ? "(빈 원고)" : document.body,
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

    private func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "확인")
        alert.runModal()
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
