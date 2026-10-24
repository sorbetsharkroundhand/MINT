import AppKit
import SwiftUI

enum WorkspacePouchSection: String, CaseIterable {
    case overview, format, ai, view, object
    // Retained as command destinations; these are no longer visual tabs.
    func title(for tile: WorkspaceTileID?) -> String {
        switch self {
        case .overview: return "MINT"
        case .format: return "서식"
        case .ai: return "AI"
        case .view: return "환경"
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
            default: return "원고"
            }
        }
    }
}

/// One scrollable card exposes all core actions together. Detailed editors
/// expand in place only after an explicit action, without replacing the list.
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
    @State private var showsModels = false
    @State private var showsCoauthor = false
    @State private var showsWriter = false
    @State private var contentHeight: CGFloat = 0

    private var target: WorkspaceTileID? { model.selectedTile }
    private var editor: BlockTextView? {
        guard let id = target?.documentID, let project = session.activeProject else { return nil }
        return requests.editor(for: .init(projectID: project.id, documentID: id))
    }
    private var canGenerate: Bool {
        session.isEditorEditable && !markedText && completion.engineState == .ready
            && settings.authorization == .enabled && settings.autocompleteEnabled && !completion.isMemoryPressurePaused
    }
    private var generationStatus: String {
        if markedText { return "입력 중" }
        if !settings.autocompleteEnabled { return "자동완성 꺼짐" }
        if settings.authorization != .enabled { return "AI 사용 꺼짐" }
        if completion.isMemoryPressurePaused { return "메모리 부족" }
        switch completion.engineState {
        case .ready: return ""
        case .loading: return "모델 로드 중"
        case .downloading: return "모델 받는 중"
        case .failed: return "모델 확인 필요"
        case .idle: return "모델 대기"
        }
    }
    private var canFormat: Bool { session.isEditorEditable && !markedText && editor != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if target?.documentID != nil {
                    aiSection
                    divider
                    formatSection
                    divider
                } else {
                    contextualSection
                    divider
                }
                manuscriptSection
            }.padding(.horizontal, 4).padding(.bottom, 6)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: PouchContentHeightKey.self, value: geometry.size.height)
                })
        }
        .mintUIFont(12).foregroundStyle(theme.inkC).tint(theme.inkC)
        .controlSize(.small).preferredColorScheme(theme.editorSurface.relativeLuminance < 0.5 ? .dark : .light)
        .accessibilityIdentifier("mint.workspace.pouch.tools")
        .onPreferenceChange(PouchContentHeightKey.self) { height in
            contentHeight = height
            model.setPouchContentHeight(height, for: target)
        }
        .onAppear { updateSelection(); receiveCommand() }
        .onChange(of: target) { _, _ in
            showsModels = false; showsCoauthor = false; showsWriter = false
            updateSelection(); receiveCommand()
        }
        .onChange(of: model.pouchSection) { _, _ in
            updateSelection(); receiveCommand(); model.setPouchContentHeight(contentHeight, for: target)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            if note.object as? BlockTextView === editor { updateSelection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { note in
            if note.object as? BlockTextView === editor { updateSelection() }
        }
    }

    private var divider: some View { theme.sepStrongC.frame(height: 1).padding(.horizontal, 8).padding(.vertical, 7) }

    private func heading(_ title: String, actionLabel: String? = nil, symbol: String = "plus",
                         enabled: Bool = true, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title).mintUIFont(10.5, .semibold).foregroundStyle(theme.ink2C)
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
                }.buttonStyle(PouchRowButtonStyle()).help(actionLabel ?? title)
                    .accessibilityLabel(actionLabel ?? title).disabled(!enabled)
            }
        }.frame(height: 26).padding(.horizontal, 8)
    }
    private func row(_ title: String, _ symbol: String, status: String = "", id: String? = nil,
                     enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { PouchActionLabel(title: title, symbol: symbol, status: status, theme: theme) }
            .buttonStyle(PouchRowButtonStyle()).disabled(!enabled)
            .accessibilityIdentifier(id ?? "mint.workspace.pouch.\(symbol)")
            .accessibilityLabel(title).accessibilityValue(status)
            .help(status.isEmpty ? title : title + " · " + status)
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            heading("AI 집필", actionLabel: "공동 집필 열기", enabled: editor != nil && !markedText, action: openCoauthor)
            toggleRow("자동완성", symbol: "text.cursor", isOn: Binding(
                get: { settings.autocompleteEnabled }, set: { completion.setAutocompleteEnabled($0) }),
                id: "mint.workspace.pouch.autocomplete").disabled(completion.isManagingModel)
            row("로컬 모델", "cpu", status: ModelChip.displayName(settings.modelID), id: "mint.workspace.pouch.model") {
                showsModels.toggle()
            }
            if showsModels {
                ModelChip(completion: completion, settings: settings, theme: theme, embedded: true)
                    .padding(.vertical, 4)
            }
            row("커서에서 이어쓰기", "sparkles", status: generationStatus, enabled: canGenerate) {
                guard let editor = focusEditor() else { return }
                model.pouchSection = nil
                (editor.delegate as? MintBlockEditor.Coordinator)?.requestExplicitCompletion(editor)
            }
            row("선택한 문장 다듬기", "wand.and.stars", status: !hasSelection ? "선택 필요" : generationStatus,
                enabled: canGenerate && hasSelection) {
                guard let editor = focusEditor() else { return }
                model.pouchSection = nil; editor.workspaceInteraction?.polishSelection()
            }
            row("공동 집필", "square.and.pencil", status: showsCoauthor ? "접기" : "열기",
                id: "mint.workspace.pouch.coauthor", enabled: editor != nil && !markedText) {
                if showsCoauthor { showsCoauthor = false } else { openCoauthor() }
            }
            if showsCoauthor, let assistance {
                WorkspacePouchCoauthor(assistance: assistance, workspace: model, theme: theme,
                    editor: editor, canGenerate: canGenerate).padding(8)
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading("서식·문단")
            HStack(spacing: 4) {
                formatIcon("굵게", symbol: "bold", active: style.bold) { apply(.toggleBold) }
                formatIcon("기울임", symbol: "italic", active: style.italic) { apply(.toggleItalic) }
                formatIcon("인라인 코드", symbol: "chevron.left.forwardslash.chevron.right", active: style.code) { apply(.toggleCode) }
                Spacer(minLength: 4)
                Button { apply(.fontSize(max(SelectionToolbarView.minFontSize, style.fontSize - 1))) } label: {
                    Image(systemName: "minus").frame(width: 26, height: 28)
                }.help("글자 크기 1 pt 줄이기").accessibilityLabel("글자 크기 줄이기")
                Text("\(Int(style.fontSize))").font(MintFonts.monoUI(11)).frame(width: 26)
                Button { apply(.fontSize(min(SelectionToolbarView.maxFontSize, style.fontSize + 1))) } label: {
                    Image(systemName: "plus").frame(width: 26, height: 28)
                }.help("글자 크기 1 pt 키우기").accessibilityLabel("글자 크기 키우기")
            }.buttonStyle(PouchRowButtonStyle()).padding(.horizontal, 8)
                .disabled(!canFormat || !hasSelection)
                .accessibilityIdentifier("mint.workspace.pouch.character-format")
            HStack(spacing: 4) {
                blockButton("본문", block: .p)
                blockButton("H1", block: .h1)
                blockButton("H2", block: .h2)
                blockButton("H3", block: .h3)
                blockButton("인용", block: .quote)
            }.padding(.horizontal, 8).disabled(!canFormat)
            HStack(spacing: 9) {
                Text("글자색").mintUIFont(10.5).foregroundStyle(theme.ink2C)
                Spacer(minLength: 4)
                colorButton(nil, label: "기본 잉크색")
                ForEach(Array(zip(["빨강", "주황", "초록", "파랑", "보라"], SelectionToolbarView.colorPresets)), id: \.1) { name, hex in
                    colorButton(hex, label: name)
                }
            }.frame(height: 28).padding(.horizontal, 8).disabled(!canFormat || !hasSelection)
            Menu {
                Button("글머리 목록") { apply(.block(.bullet)) }
                Button("번호 목록") { apply(.block(.number)) }
                Button("체크 목록") { apply(.block(.todo)) }
                Button("코드 블록") { apply(.block(.code)) }
                Divider()
                Button("왼쪽 정렬") { apply(.align(nil)) }
                Button("가운데 정렬") { apply(.align("center")) }
                Button("오른쪽 정렬") { apply(.align("right")) }
                Menu("문단 줄 간격 · \(Int(style.lineSpacing)) pt") {
                    ForEach(0...20, id: \.self) { spacing in
                        Button("\(spacing) pt") { apply(.lineSpacing(Double(spacing))) }
                    }
                }
                Divider()
                Button("선택한 글을 메모로 발췌") {
                    guard let editor = focusEditor() else { return }
                    editor.workspaceInteraction?.excerptSelection()
                }.disabled(!hasSelection)
            } label: {
                PouchActionLabel(title: "목록·정렬·간격", symbol: "text.alignleft", status: blockTitle, theme: theme, submenu: true)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(!canFormat)
            toggleRow("타자기 중앙 스크롤", symbol: "text.line.first.and.arrowtriangle.forward", isOn: $model.typewriter,
                id: "mint.workspace.pouch.typewriter")
            toggleRow("현재 문단에 집중", symbol: "viewfinder", isOn: $model.focusDimming,
                id: "mint.workspace.pouch.focus")
            Menu {
                Menu("기본 글자 크기 · \(Int(settings.editorFontSize)) pt") {
                    ForEach(Int(CompletionSettings.minFontSize)...Int(CompletionSettings.maxFontSize), id: \.self) { size in
                        Button("\(size) pt") { settings.editorFontSize = Double(size) }
                    }
                }
                Menu("기본 줄 간격 · \(Int(settings.lineSpacing)) pt") {
                    ForEach(0...20, id: \.self) { spacing in
                        Button("\(spacing) pt") { settings.lineSpacing = Double(spacing) }
                    }
                }
            } label: {
                PouchActionLabel(title: "기본 조판", symbol: "textformat.size", status: "모든 원고", theme: theme, submenu: true)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
    }
    private func formatIcon(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 32, height: 28)
                .foregroundStyle(active ? theme.novelC : theme.inkC)
                .background(active ? theme.activeBgC : theme.hoverC, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(PouchRowButtonStyle()).help(title).accessibilityLabel(title)
            .accessibilityValue(active ? "켜짐" : "꺼짐")
    }
    private func blockButton(_ title: String, block: MintBlock) -> some View {
        Button { apply(.block(block)) } label: {
            Text(title).mintUIFont(11, .medium).frame(maxWidth: .infinity).frame(height: 28)
                .foregroundStyle(style.block == block ? theme.novelC : theme.ink2C)
                .background(style.block == block ? theme.activeBgC : theme.hoverC, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(PouchRowButtonStyle()).accessibilityLabel(title)
            .accessibilityValue(style.block == block ? "선택됨" : "")
    }
    private func colorButton(_ hex: String?, label: String) -> some View {
        Button { apply(.color(hex)) } label: {
            Circle().fill(Color(nsColor: hex.flatMap { NSColor(inlineHex: $0) } ?? theme.ink))
                .frame(width: 14, height: 14).padding(3)
                .overlay(Circle().strokeBorder(style.colorHex == hex ? theme.inkC : .clear, lineWidth: 1))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label + " 글자색")
            .accessibilityValue(style.colorHex == hex ? "선택됨" : "")
    }
    private func toggleRow(_ title: String, symbol: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol).mintUIFont(12)
        }.toggleStyle(.switch).controlSize(.mini).tint(theme.novelC)
            .padding(.horizontal, 8).frame(height: 30).accessibilityIdentifier(id)
    }

    private var blockTitle: String {
        switch style.block {
        case .h1: "제목 1"; case .h2: "제목 2"; case .h3: "제목 3"
        case .quote: "인용"; case .bullet: "글머리"; case .number: "번호"; case .todo: "체크"; case .code: "코드"
        default: "본문"
        }
    }
    @ViewBuilder private var contextualSection: some View {
        heading(WorkspacePouchSection.object.title(for: target))
        switch target {
        case .characters, .narrative, .context:
            row(target == .characters ? "인물과 작품 정보 편집" : (target == .narrative ? "작가 수정과 기록" : "문맥 고정·제외"),
                "pencil", status: showsWriter ? "접기" : "열기") { showsWriter.toggle() }
            if showsWriter {
                ProjectWriterToolsView(session: session, completion: completion, editorRequests: requests,
                    section: target == .characters ? .bible : (target == .narrative ? .narrative : .context),
                    theme: theme, spatial: model, embedded: true)
            }
        case .margin:
            row("마진 노트 생성", "sparkles", status: "로컬 AI", enabled: canGenerate, action: generateMargin)
        case .search:
            ForEach(WorkspaceSearchScope.allCases, id: \.self) { scope in
                row(scope.rawValue + " 찾기", "magnifyingglass") { model.openSearch(scope: scope) }
            }
        case .navigator:
            row("문서 나란히 펼치기", "rectangle.split.3x1") { model.openAll() }
        case .map, .outline:
            row("글쓰기로 돌아가기", "pencil", id: target == .map ? "mint.story-map.close" : "mint.document-outline.close") {
                session.selectWorkspaceMode(.write); requests.focusEditor()
            }
        default: EmptyView()
        }
    }
    private var manuscriptSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            heading("원고·도구", actionLabel: "새 원고", enabled: session.isEditorEditable, action: {
                ProjectCommandActions(session: session).newDocument(.manuscript); requests.focusEditor()
            })
            row("검색", "magnifyingglass", status: "⌘F", id: "mint.source-search.show") { model.openSearch() }
            Menu {
                Button("문서 목록") { open(.navigator) }
                Button("인물·작품 정보") { open(.characters) }
                Button("서사 흐름") { open(.narrative) }
                Button("마진 노트") { open(.margin) }
                Button("문서 나란히 펼치기") { model.openAll() }
            } label: {
                PouchActionLabel(title: "원고와 참고 도구", symbol: "square.grid.2x2", status: "", theme: theme, submenu: true)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            row("AI가 참고한 내용", "text.magnifyingglass") { open(.context) }
            Menu {
                if let target {
                    Button(target.documentID == nil ? "객체 닫기" : "원고 닫기") { model.dismissObject?(target) }
                }
                Button("주머니 떼어 놓기") { model.selectTile(nil) }
                Divider()
                Button("MINT 전체 설정…", action: openSettings)
            } label: {
                PouchActionLabel(title: "객체와 앱 설정", symbol: "gearshape", status: "", theme: theme, submenu: true)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
    }
    private func receiveCommand() {
        if model.pouchSection == .overview {
            showsModels = false; showsCoauthor = false; showsWriter = false
        }
        if model.pouchSection == .ai { showsCoauthor = true }
        if model.pouchSection == .object, [.characters, .narrative, .context].contains(target) { showsWriter = true }
    }
    private func open(_ tile: WorkspaceTileID) {
        if !model.layout.contains(tile) { model.toggle(tile) } else { model.selectTile(tile) }
    }
    private func openCoauthor() {
        guard let assistance, let editor, !editor.hasMarkedText() else { return }
        do { try assistance.openCoauthor(editor: editor); showsCoauthor = true }
        catch { model.showToast("현재 원고에서 다시 실행해 주세요.") }
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
}

private struct PouchContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PouchActionLabel: View {
    let title: String
    let symbol: String
    let status: String
    let theme: MintTheme
    var submenu = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 17).foregroundStyle(theme.ink2C)
            Text(title).mintUIFont(12).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 4)
            if !status.isEmpty { Text(status).mintUIFont(10.5).foregroundStyle(theme.ink2C).lineLimit(1).truncationMode(.middle).frame(maxWidth: 92, alignment: .trailing) }
            if submenu { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.ink2C) }
        }.padding(.horizontal, 8).frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(hovered && enabled ? theme.hoverC : .clear, in: RoundedRectangle(cornerRadius: 7))
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}
private struct PouchRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Color.white.opacity(0.07) : .clear,
            in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct WorkspacePouchCoauthor: View {
    @ObservedObject var assistance: WorkspaceAssistance
    @ObservedObject var workspace: SpatialWorkspaceController
    let theme: MintTheme
    let editor: BlockTextView?
    let canGenerate: Bool
    private var key: ProjectDocumentKey? {
        guard case .project(let key) = editor?.writingDocumentIdentity else { return nil }
        return key
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("공동 집필").mintUIFont(11, .semibold)
                Spacer()
                if assistance.generating && assistance.coauthorKey == key {
                    ProgressView().controlSize(.mini).accessibilityLabel("초안 생성 중")
                }
            }
            if let key, assistance.mode == .coauthor, assistance.coauthorKey == key {
                WorkspaceAssistanceView(model: assistance, theme: theme,
                    close: { workspace.pouchSection = nil; editor?.window?.makeFirstResponder(editor) },
                    embedded: true, canGenerate: canGenerate, prepareGeneration: {
                        guard let editor else { return false }
                        do { try assistance.capture(.coauthor, editor: editor); return true }
                        catch { workspace.showToast("현재 원고에서 다시 실행해 주세요."); return false }
                    })
            } else {
                Text("장면의 방향을 적고 초안을 함께 다듬으세요.\n도구를 접어도 요청과 초안은 유지됩니다.")
                    .foregroundStyle(theme.ink2C).fixedSize(horizontal: false, vertical: true)
                Button(key.map { assistance.hasCoauthorDraft(for: $0) } == true ? "보관한 집필 이어가기" : "공동 집필 시작") {
                    guard let editor else { return }
                    do { try assistance.openCoauthor(editor: editor) }
                    catch { workspace.showToast("현재 원고에서 다시 실행해 주세요.") }
                }.disabled(editor == nil || editor?.hasMarkedText() == true)
            }
        }
    }
}
