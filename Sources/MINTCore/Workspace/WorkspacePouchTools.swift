import AppKit
import SwiftUI

enum WorkspacePouchSection: String, CaseIterable {
    case format, ai, view, object

    static func sections(for tile: WorkspaceTileID?) -> [Self] {
        tile?.documentID == nil ? [.object] : [.format, .ai, .view, .object]
    }

    func title(for tile: WorkspaceTileID?) -> String {
        switch self {
        case .format: return "서식"
        case .ai: return "AI"
        case .view: return "보기"
        case .object:
            switch tile {
            case .characters: return "인물·작품"
            case .narrative: return "서사"
            case .margin: return "마진 노트"
            case .navigator: return "문서"
            case .search: return "검색"
            case .context: return "AI 문맥"
            case .map: return "지도"
            case .outline: return "개요"
            default: return "객체"
            }
        }
    }
}

/// The index tab owns these controls. It is hosted in the pouch itself, never a tile or window.
struct WorkspacePouchTools: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var requests: ProjectEditorRequests
    @ObservedObject var model: SpatialWorkspaceController
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    let assistance: WorkspaceAssistance?
    let generateMargin: () -> Void
    let openSettings: () -> Void
    @State private var style = SelectionStyleState()
    @State private var hasSelection = false
    @State private var markedText = false
    @State private var coauthorVisible = false

    private var target: WorkspaceTileID? { model.selectedTile }
    private var editor: BlockTextView? {
        guard let id = target?.documentID, let project = session.activeProject else { return nil }
        return requests.editor(for: .init(projectID: project.id, documentID: id))
    }
    private var canGenerate: Bool {
        session.isEditorEditable && !markedText && completion.engineState == .ready
            && settings.authorization == .enabled && settings.autocompleteEnabled
    }

    var body: some View {
        Group {
            if model.pouchSection == .object && (target == .characters || target == .narrative || target == .context) {
                VStack(spacing: 0) {
                    ProjectWriterToolsView(session: session, completion: completion, editorRequests: requests,
                        section: target == .characters ? .bible : (target == .narrative ? .narrative : .context),
                        theme: theme, spatial: model)
                    objectActions.padding(12)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch model.pouchSection {
                        case .format: formatting
                        case .ai: aiTools
                        case .view: viewing
                        case .object: contextualTools; objectActions
                        case nil: EmptyView()
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .mintUIFont(11).foregroundStyle(theme.inkC).tint(theme.novelC)
        .controlSize(.small)
        .accessibilityIdentifier("mint.workspace.pouch.tools")
        .onAppear(perform: updateSelection)
        .onChange(of: target) { _, _ in endCoauthor(); updateSelection() }
        .onChange(of: model.pouchSection) { _, _ in endCoauthor(); updateSelection() }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            if note.object as? BlockTextView === editor { updateSelection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { note in
            if note.object as? BlockTextView === editor { updateSelection() }
        }
        .onDisappear(perform: endCoauthor)
    }

    private var formatting: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hasSelection ? "선택한 글자" : "글자를 선택하면 서식을 바꿀 수 있어요.")
                .foregroundStyle(theme.ink2C)
            HStack(spacing: 8) {
                formatButton("굵게", active: style.bold, action: .toggleBold)
                formatButton("기울임", active: style.italic, action: .toggleItalic)
                formatButton("코드", active: style.code, action: .toggleCode)
            }.disabled(!hasSelection || markedText || !session.isEditorEditable)
            HStack(spacing: 9) {
                colorButton(nil)
                ForEach(SelectionToolbarView.colorPresets, id: \.self) { colorButton($0) }
            }.disabled(!hasSelection || markedText || !session.isEditorEditable)
            Stepper("글자 크기 · \(Int(style.fontSize)) pt", value: Binding(
                get: { style.fontSize }, set: { apply(.fontSize($0)) }),
                in: SelectionToolbarView.minFontSize...SelectionToolbarView.maxFontSize)
                .disabled(!hasSelection || markedText || !session.isEditorEditable)
            Divider()
            Text("현재 문단").foregroundStyle(theme.ink2C)
            Menu("본문 · 제목 · 목록") {
                Button("본문") { apply(.block(.p)) }
                Button("제목 1") { apply(.block(.h1)) }
                Button("제목 2") { apply(.block(.h2)) }
                Button("제목 3") { apply(.block(.h3)) }
                Button("인용") { apply(.block(.quote)) }
                Button("글머리 목록") { apply(.block(.bullet)) }
                Button("번호 목록") { apply(.block(.number)) }
                Button("체크 목록") { apply(.block(.todo)) }
                Button("코드 블록") { apply(.block(.code)) }
            }
            HStack {
                Button("왼쪽") { apply(.align(nil)) }
                Button("가운데") { apply(.align("center")) }
                Button("오른쪽") { apply(.align("right")) }
            }
            Stepper("문단 줄 간격 · \(Int(style.lineSpacing)) pt", value: Binding(
                get: { style.lineSpacing }, set: { apply(.lineSpacing($0)) }), in: 0...20)
            Button("선택한 글을 메모로 발췌") {
                guard let editor = focusEditor() else { return }
                editor.workspaceInteraction?.excerptSelection()
            }.disabled(!hasSelection)
        }.disabled(markedText || !session.isEditorEditable)
    }

    private var viewing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("타자기 중앙 스크롤", isOn: $model.typewriter)
            Toggle("현재 문단에 집중", isOn: $model.focusDimming)
            Text("기본 본문 크기 · \(Int(settings.editorFontSize)) pt")
            Slider(value: $settings.editorFontSize,
                in: CompletionSettings.minFontSize...CompletionSettings.maxFontSize, step: 1)
            Text("기본 줄 간격 · \(Int(settings.lineSpacing)) pt")
            Slider(value: $settings.lineSpacing, in: 0...20, step: 1)
            Text("기본 크기와 간격은 모든 원고에 적용됩니다.")
                .foregroundStyle(theme.ink2C)
        }
    }

    private var aiTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelChip(completion: completion, settings: settings, theme: theme)
            Button("커서에서 이어쓰기") {
                endCoauthor()
                guard let editor = focusEditor() else { return }
                (editor.delegate as? MintBlockEditor.Coordinator)?.requestExplicitCompletion(editor)
            }.disabled(!canGenerate)
            Button("선택한 문장 다듬기") {
                endCoauthor()
                guard let editor = focusEditor() else { return }
                editor.workspaceInteraction?.polishSelection()
            }.disabled(!canGenerate || !hasSelection)
            if let assistance {
                if coauthorVisible {
                    WorkspaceAssistanceView(model: assistance, theme: theme, close: {
                        endCoauthor(); _ = focusEditor()
                    })
                } else {
                    Button("공동 집필") {
                        guard let editor = focusEditor() else { return }
                        do { try assistance.capture(.coauthor, editor: editor); coauthorVisible = true }
                        catch { model.showToast("현재 원고에서 다시 실행해 주세요.") }
                    }.disabled(!canGenerate)
                }
            }
            Button("제안에 쓰인 내용 보기") {
                if !model.layout.contains(.context) { model.toggle(.context) }
                else { model.selectTile(.context) }
            }
            Text("자동완성: Tab 수락 · → 일부 수락 · Esc 거절")
                .foregroundStyle(theme.ink2C).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var contextualTools: some View {
        switch target {
        case .margin:
            Button("로컬 AI로 마진 노트 생성", action: generateMargin)
                .disabled(!canGenerate)
        case .search:
            ForEach(WorkspaceSearchScope.allCases, id: \.self) { scope in
                Button(scope.rawValue + " 찾기") { model.openSearch(scope: scope) }
            }
        case .navigator:
            Button("문서 나란히 펼치기") { model.openAll() }
        case .map, .outline:
            Button("글쓰기로 돌아가기") { session.selectWorkspaceMode(.write); requests.focusEditor() }
        default: EmptyView()
        }
    }

    private var objectActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let target {
                Button("이 객체를 주머니에 넣기") {
                    if model.close(target) {
                        if target == .map || target == .outline { session.selectWorkspaceMode(.write) }
                        requests.focusEditor()
                    }
                }.disabled(target.documentID != nil && model.layout.openDocuments.count <= 1)
                    .accessibilityIdentifier(target == .map ? "mint.story-map.close" : "mint.tile.close.\(target.id)")
            }
            Button("주머니 떼어 놓기") { model.selectTile(nil) }
            Button("MINT 전체 설정…", action: openSettings)
        }
    }

    private func formatButton(_ title: String, active: Bool, action: SelectionToolbarAction) -> some View {
        Button(title) { apply(action) }.tint(active ? theme.novelC : theme.ink2C)
    }
    private func colorButton(_ hex: String?) -> some View {
        let color = hex.flatMap { NSColor(inlineHex: $0) } ?? theme.ink
        return Button { apply(.color(hex)) } label: {
            Circle().fill(Color(nsColor: color)).frame(width: 17, height: 17)
                .padding(3).overlay(Circle().stroke(style.colorHex == hex ? theme.inkC : .clear, lineWidth: 1))
        }.buttonStyle(.plain).help(hex.map { "글자색 #" + $0 } ?? "기본 글자색")
            .accessibilityLabel(hex.map { "글자색 #" + $0 } ?? "기본 글자색")
    }
    private func apply(_ action: SelectionToolbarAction) {
        guard session.isEditorEditable, let editor, !editor.hasMarkedText() else { return }
        editor.perform(action); updateSelection()
    }
    private func updateSelection() {
        guard model.pouchSection != nil else { return }
        guard let editor else { hasSelection = false; markedText = false; return }
        markedText = editor.hasMarkedText()
        hasSelection = editor.selectedRange().length > 0
        if !markedText { style = editor.currentSelectionState() }
    }
    private func focusEditor() -> BlockTextView? {
        guard session.isEditorEditable, let editor, !editor.hasMarkedText(),
              editor.window?.makeFirstResponder(editor) == true else { return nil }
        return editor
    }
    private func endCoauthor() {
        if coauthorVisible { assistance?.cancel(); coauthorVisible = false }
    }
}
