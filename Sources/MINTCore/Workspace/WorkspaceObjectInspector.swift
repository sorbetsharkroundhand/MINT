import SwiftUI

/// Context follows the selected object; opening the inspector does not replace the editor.
struct WorkspaceObjectInspector: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var requests: ProjectEditorRequests
    @ObservedObject var model: SpatialWorkspaceController
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    let generateMargin: () -> Void
    @Environment(\.openSettings) private var openSettings

    private var target: WorkspaceTileID? { model.inspectedTile }
    private var title: String {
        switch target {
        case .document(let id): session.document(id)?.title ?? "원고"
        case .characters: "인물·작품 정보"
        case .narrative: "서사 흐름"
        case .margin: "마진 노트"
        case .navigator: "문서 목록"
        case .search: "검색"
        case .map: "이야기 지도"
        case .outline: "문서 개요"
        case .context: "제안에 쓰인 내용"
        default: "작업 공간"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).mintUIFont(14, .semibold).foregroundStyle(theme.inkC)
                if case .document = target {
                    Toggle("타자기 중앙 스크롤", isOn: $model.typewriter)
                    Toggle("현재 문단에 집중", isOn: $model.focusDimming)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("본문 크기 · \(Int(settings.editorFontSize))")
                        Slider(value: $settings.editorFontSize, in: CompletionSettings.minFontSize...CompletionSettings.maxFontSize, step: 1)
                        Text("줄 간격 · \(Int(settings.lineSpacing))")
                        Slider(value: $settings.lineSpacing, in: 0...20, step: 1)
                    }
                    ModelChip(completion: completion, settings: settings, theme: theme)
                    Text("글자 크기·줄 간격·자동완성은 원고 전체에 적용됩니다.")
                        .mintUIFont(10).foregroundStyle(theme.ink2C)
                } else if target == .characters {
                    Toggle("인물·작품 정보 편집", isOn: $model.writerDetailsVisible)
                    Button("새 인물 추가") {
                        guard let identity = session.runtimeIdentity else { return }
                        let card = CharacterCard()
                        do {
                            try ProjectWriterEditing.perform(.character(card), in: session, identity: identity)
                            model.expandedItem = card.id.uuidString; model.writerDetailsVisible = true
                        } catch { session.reportError(error) }
                    }
                } else if target == .narrative {
                    Toggle("작가 수정과 기록", isOn: $model.narrativeDetailsVisible)
                } else if target == .margin {
                    Button("로컬 AI로 마진 노트 생성", action: generateMargin)
                        .disabled(completion.engineState != .ready || !settings.autocompleteEnabled)
                } else if target == .search {
                    ForEach(WorkspaceSearchScope.allCases, id: \.self) { scope in
                        Button(scope.rawValue + " 찾기") { model.openSearch(scope: scope) }
                    }
                } else if target == .navigator {
                    Button("문서 나란히 펼치기") { model.openAll() }
                } else if target == .context {
                    ModelChip(completion: completion, settings: settings, theme: theme)
                }
                Divider()
                if let target, target != .inspector {
                    Button("이 객체를 주머니에 넣기") {
                        if model.close(target) {
                            if target == .map || target == .outline { session.selectWorkspaceMode(.write) }
                            requests.focusEditor()
                        }
                    }
                }
                Button("주머니 떼어 놓기") { model.selectTile(nil) }
                Button("MINT 전체 설정…") { openSettings() }
            }.mintUIFont(12).foregroundStyle(theme.ink2C).padding(16)
        }.accessibilityIdentifier("mint.workspace.object-inspector")
    }
}
