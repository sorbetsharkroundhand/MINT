import SwiftUI

/// 설정 화면 — 앱 메뉴/⌘,의 Settings 씬, 툴바 톱니바퀴에서 연다.
///
/// `CompletionSettings`(UserDefaults 보존)에 바인딩된다. 모델·프롬프트 방식
/// 변경은 **다음 제안부터** 적용되며, 새 모델은 첫 사용 시 다운로드된다.
///
/// **탭으로 나눈 이유**: 한 Form에 모든 섹션을 세로로 쌓으니 창이 화면보다
/// 길어져 아래에 무엇이 있는지 알 수 없었다. macOS 설정창 관례대로 기능별
/// 탭으로 자르고, 각 탭은 고정 높이 안에서 스스로 스크롤한다 — 예전의
/// `.fixedSize(vertical: true)`가 Form을 내용 전체 높이로 늘려 스크롤 자체를
/// 없앴던 것이 문제였다.
public struct SettingsView: View {
    @ObservedObject private var settings: CompletionSettings
    /// 예측 의유 통로 (이슈 #11) — 자동완성 스위치·모델 변경은 settings를 직접
    /// 고치지 않고 컨트롤러의 무효화(세대 상승·스트림 취소·리포트 폐기)를 함께
    /// 발화한다. nil이면 프리뷰처럼 값만 바뀐다.
    private let completion: CompletionController?
    /// 실사용 품질 지표 집계 (M7) — .task에서 백그라운드 로드.
    @State private var metrics = AcceptanceMetrics.Summary()
    /// 외형(다크 모드) — 상단바 스위치에서 옮겨 왔다. 키는 그대로 둬서 기존
    /// 사용자의 선택이 유지된다. ""=시스템 따름 · "light" · "dark".
    @AppStorage("mint.appearance") private var appearance = ""
    @Environment(\.colorScheme) private var colorScheme
    /// 색상 팔레트 — 고르는 즉시 앱 전체에 반영된다 (ContentView도 관찰).
    // 앱 수명 싱글턴 — StateObject 소유 의미 (#60).
    @StateObject private var palette = PaletteSettings.shared
    /// 모델 ID 초안 — 커밋(Enter/적용)까지 settings에 쓰지 않는다 (#65 H2).
    @State private var modelIDDraft = ""
    /// 초안 검증 실패 문구 — nil이면 오류 없음.
    @State private var modelIDError: String?

    public init(
        settings: CompletionSettings = .shared,
        completion: CompletionController? = nil
    ) {
        self._settings = ObservedObject(wrappedValue: settings)
        self.completion = completion
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("일반", systemImage: "gearshape") }
            predictionTab
                .tabItem { Label("예측", systemImage: "sparkles") }
            novelTab
                .tabItem { Label("소설", systemImage: "book.closed") }
            helpTab
                .tabItem { Label("사용 방법", systemImage: "questionmark.circle") }
            metricsTab
                .tabItem { Label("지표", systemImage: "chart.bar") }
        }
        // 고정 크기 — 탭 안의 Form이 이 높이를 넘으면 그 안에서 스크롤한다.
        // 창이 내용을 따라 늘어나면 다시 "아래가 안 보이는" 문제로 돌아간다.
        .frame(width: 500, height: 520)
        .onAppear { syncModelIDDraft() }
        // 프리셋 적용 등 외부 경로로 모델이 바뀌면 초안·오류를 따라 맞춘다.
        .onChange(of: settings.modelID) { _, _ in syncModelIDDraft() }
        .task {
            // 파일 집계는 백그라운드에서 — 설정 창이 뜨는 프레임을 안 막는다.
            metrics = await Task.detached(priority: .utility) {
                AcceptanceMetrics.summarize()
            }.value
            guard !Task.isCancelled else { return }  // stale 결과 할당 금지 (#60)
        }
    }

    // MARK: - 일반 (외형·본문 조판)

    private var generalTab: some View {
        Form {
            Section("외형") {
                Toggle("다크 모드", isOn: darkModeBinding)
                caption("끄면 라이트 모드예요 — 시스템 외형을 따르려면 보기 메뉴의 '시스템 외형 따르기'.")
            }

            Section("색상") {
                Toggle("색상 직접 고르기", isOn: $palette.enabled)
                caption(
                    palette.enabled
                        ? "아래에서 고른 색이 배경·툴바·사이드바·배지에 쓰여요 — 글자는 항상 읽히도록 따로 관리돼요."
                        : "지금은 기본 색을 쓰고 있어요. 켜면 라이트·다크 각각 다섯 색을 직접 고를 수 있어요.")
            }

            if palette.enabled {
                paletteSection(dark: false)
                paletteSection(dark: true)
            }

            Section("본문") {
                Stepper(
                    "글자 크기: \(Int(settings.editorFontSize.rounded()))pt",
                    value: $settings.editorFontSize,
                    in: CompletionSettings.minFontSize...CompletionSettings.maxFontSize,
                    step: 1
                )
                caption("본문·제목이 이 크기에 비례해요 (⌘+ / ⌘− / ⌘0).")
                Stepper(
                    "줄 간격: \(Int(settings.lineSpacing.rounded()))pt",
                    value: $settings.lineSpacing,
                    in: 0...20,
                    step: 1
                )
                caption("줄 사이 여백을 조절해요 — 낮추면 촘촘하게, 높이면 시원하게.")
            }
        }
        .formStyle(.grouped)
    }

    /// 색상 팔레트 — 밝기 순 5슬롯을 라이트/다크 각각 고른다.
    ///
    /// 팔레트는 **배경·표면에만** 쓰인다. 글자색은 팔레트와 무관하게 유지되고,
    /// 액센트만 팔레트에서 색상을 물려받아 대비에 맞게 명도를 조정한다 —
    /// 그러지 않으면 밝은 색만 고른 순간 글자가 사라진다.
    @ViewBuilder private func paletteSection(dark: Bool) -> some View {
        Section(dark ? "색상 — 다크 모드" : "색상 — 라이트 모드") {
            ForEach(0..<MintPalette.slotCount, id: \.self) { slot in
                ColorPicker(
                    MintPalette.slotLabels[slot],
                    selection: paletteBinding(dark: dark, slot: slot),
                    supportsOpacity: false)
            }
            Button("기본값으로 되돌리기") {
                palette.reset(dark: dark)
            }
        }
    }

    /// 슬롯 하나의 색 바인딩 — SwiftUI `Color` ↔ 저장용 hex 왕복.
    private func paletteBinding(dark: Bool, slot: Int) -> Binding<Color> {
        Binding(
            get: {
                let current = dark ? palette.dark : palette.light
                return Color(nsColor: current.color(slot))
            },
            set: { newValue in
                let hex = NSColor(newValue).hexValue
                var current = dark ? palette.dark : palette.light
                current.hexes[slot] = hex
                if dark { palette.dark = current } else { palette.light = current }
            }
        )
    }

    // MARK: - 예측 (모델 + 제안 동작)

    /// 모델과 제안 파라미터는 같은 것(예측 품질)을 조절하므로 한 탭에 둔다.
    private var predictionTab: some View {
        Form {
            Section("모델") {
                // 초안/커밋 경계 (이슈 #25 / #65 H2) — TextField는 modelIDDraft만
                // 편집한다. 타이핑이 changeModel을 부르면 불완전한 ID마다 취소·
                // 다운로드·preload가 반복됐다. 커밋은 Enter/적용에서 1회.
                TextField("Hugging Face 저장소 id (namespace/model)", text: $modelIDDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(commitModelIDDraft)
                if let modelIDError {
                    Text(modelIDError)
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text("모델 ID 오류: \(modelIDError)"))
                }
                HStack {
                    Menu("프리셋에서 선택") {
                        ForEach(ModelPresets.all, id: \.self) { preset in
                            Button(preset) { changeModel(preset) }  // 프리셋은 형식 보장 — 즉시 적용
                        }
                    }
                    Spacer()
                    Button("적용", action: commitModelIDDraft)
                        .disabled(modelIDDraft.trimmingCharacters(in: .whitespaces) == settings.modelID)
                }
                caption("모델 변경은 다음 제안부터 적용 — 새 모델은 첫 사용 시 다운로드돼요(수 GB).")
            }

            Section("제안") {
                Toggle("자동완성 사용", isOn: autocompleteBinding)
                Picker("프롬프트 방식", selection: $settings.promptStyle) {
                    ForEach(PromptStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                Stepper(
                    "디바운스: \(settings.debounceMilliseconds)ms",
                    value: $settings.debounceMilliseconds,
                    in: 150...1_000,
                    step: 50
                )
                Stepper(
                    "최대 토큰: \(settings.maxTokens)",
                    value: $settings.maxTokens,
                    in: 4...32
                )
            }

            Section("생성 파라미터") {
                VStack(alignment: .leading) {
                    Slider(value: $settings.temperature, in: 0...1) {
                        Text(String(format: "온도: %.2f", settings.temperature))
                    }
                    caption("낮을수록 일관된 제안, 높을수록 다양한 제안.")
                }
                VStack(alignment: .leading) {
                    Slider(value: $settings.topP, in: 0.5...1.0) {
                        Text(String(format: "top-p: %.2f", settings.topP))
                    }
                    caption("누적 확률 컷 — 벤치(MINTBench)로 확정하는 값이에요 (PLAN §10).")
                }
                Toggle("KV 캐시 재사용", isOn: $settings.kvCacheEnabled)
                caption("타이핑 중 프리필을 증분 처리해 제안이 빨라져요 — 이상 동작 시 꺼 보세요.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 소설 (작품 메타데이터·이해 범위)

    private var novelTab: some View {
        Form {
            Section("저자") {
                TextField("저자 이름 (필명)", text: $settings.authorName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                caption("EPUB으로 내보낼 때 저자로 실려요 — 비워 두면 저자 정보 없이 내보내요.")
            }

            Section("이해 범위") {
                Stepper(
                    "소설 컨텍스트: \(settings.novelContextCharacters)자",
                    value: $settings.novelContextCharacters,
                    in: 1_200...12_000,
                    step: 400
                )
                caption("소설 종류 문서가 커서 앞에서 읽는 최대 분량 — 넓을수록 멀리 기억하지만 첫 제안이 느려질 수 있어요.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 사용 방법 (단축키·마크다운)

    /// 상단바 도움말 버튼을 대신한다. 여기 적는 단축키는 전부 코드에 실제로
    /// 있는 것만 (AppCommands·BlockTextView 기준).
    private var helpTab: some View {
        Form {
            Section("제안 다루기") {
                shortcut("Tab", "제안 전체 수락")
                shortcut("→", "제안을 한 단어만 수락")
                shortcut("Esc", "제안 무시")
            }

            Section("글쓰기") {
                shortcut("⌘B / ⌘I / ⇧⌘C", "굵게 · 기울임 · 인라인 코드")
                shortcut("⌥⌘1~3 / ⌥⌘0", "제목 1~3 · 본문")
                shortcut("⇧⌘I", "이미지 삽입 (붙여넣기·드래그 드롭도 돼요)")
                shortcut("⌘+ / ⌘− / ⌘0", "글자 크게 · 작게 · 기본")
            }

            Section("찾기·이동") {
                shortcut("⌘F / ⌘G / ⇧⌘G", "문서에서 찾기 · 다음 · 이전")
                shortcut("⇧⌘F", "저널 검색")
            }

            Section("문서·창") {
                shortcut("⌘N / ⌥⌘N / ⇧⌘N", "새 저널 · 새 소설 · 새 폴더")
                shortcut("⌃⌘S", "파일 목록 접기/펴기")
                shortcut("⇧⌘D", "집중 모드")
                shortcut("⇧⌘E / ⌘P", "Markdown 내보내기 · 인쇄")
                caption("작성일 바꾸기·EPUB 내보내기·소설 전환은 사이드바에서 저널을 오른쪽 클릭.")
            }

            Section("마크다운 서식") {
                MarkdownCheatSheet(theme: MintTheme.of(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 지표 (로컬 전용)

    /// 실사용 품질 지표 (M7, PLAN §13) — 로컬 파일에만, 원격 전송 절대 금지.
    private var metricsTab: some View {
        Form {
            Section("품질 지표 (로컬 전용)") {
                if metrics.shown == 0 {
                    caption("아직 기록이 없어요 — 제안이 뜨고 수락/거절될 때마다 이 Mac에만 기록돼요.")
                } else {
                    LabeledContent("제안 노출", value: "\(metrics.shown)회")
                    LabeledContent(
                        "전체 수락 (Tab)",
                        value: "\(metrics.acceptedFull)회 · \(metrics.acceptanceRate)%")
                    LabeledContent("단어 수락 (→)", value: "\(metrics.acceptedWord)회")
                    ForEach(metrics.byMode.keys.sorted(), id: \.self) { mode in
                        let stats = metrics.byMode[mode] ?? (0, 0)
                        LabeledContent(
                            "· \(mode)",
                            value: "노출 \(stats.shown) · 수락 \(stats.accepted)")
                        .font(.caption)
                    }
                }
                Button("지표 삭제") {
                    AcceptanceMetrics.reset()
                    metrics = .init()
                }
                caption("어떤 지표도 기기 밖으로 나가지 않아요 (~/Documents/MINT/metrics.jsonl).")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 예측 의유 바인딩 (이슈 #11)

    /// 컨트롤러가 있으면 의유 API로, 없으면(프리뷰) 직접 쓴다.
    private func changeModel(_ id: String) {
        guard let completion else {
            settings.modelID = id
            return
        }
        completion.changeModel(to: id)
    }

    private var autocompleteBinding: Binding<Bool> {
        Binding(
            get: { settings.autocompleteEnabled },
            set: { enabled in
                guard let completion else {
                    settings.autocompleteEnabled = enabled
                    return
                }
                completion.setAutocompleteEnabled(enabled)
            })
    }

    /// 초안을 검증해 유효한 새 ID일 때만 changeModel을 **한 번** 호출한다 (#65 H2).
    /// 같은 ID는 무해(무동작), 잘못된 ID는 인라인 오류로 현재 모델을 건드리지 않는다.
    private func commitModelIDDraft() {
        switch ModelIDCommit.validate(modelIDDraft) {
        case .failure(let error):
            modelIDError = error.message
        case .success(let id):
            modelIDError = nil
            guard id != settings.modelID else { return }
            changeModel(id)
        }
    }

    /// 프리셋·외부 경로로 모델이 바뀌면 초안을 따라 맞춘다.
    private func syncModelIDDraft() {
        modelIDDraft = settings.modelID
        modelIDError = nil
    }

    // MARK: - 공용 조각

    /// 설명 한 줄 — 컨트롤 아래 붙는 보조 문구.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 단축키 한 줄 — 키는 고정폭으로 읽기 쉽게.
    private func shortcut(_ keys: String, _ label: String) -> some View {
        LabeledContent {
            Text(keys).font(MintFonts.monoUI(11, .semibold))
        } label: {
            Text(label)
        }
    }

    /// 다크 모드 스위치 — 예전 상단바 스위치와 같은 규칙으로 읽고 쓴다.
    /// "시스템 따름"(빈 값)일 땐 실제 시스템 외형을 현재 상태로 보여준다.
    private var darkModeBinding: Binding<Bool> {
        Binding(
            get: { appearance == "dark" || (appearance.isEmpty && colorScheme == .dark) },
            set: { appearance = $0 ? "dark" : "light" }
        )
    }
}

#Preview {
    SettingsView(settings: CompletionSettings())
}
