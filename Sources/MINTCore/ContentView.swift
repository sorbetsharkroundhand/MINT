import AppKit
import SwiftUI

/// MINT 에디터 v3 메인 화면 — 디자인 "MINT Editor v3.dc.html" 완전 이식.
///
/// 창 전체가 리퀴드 글래스(배경 블러 + 유리 톤), 좌측 사이드바(다중 저널),
/// 우측 에디터 컬럼(툴바 · Notion식 블록 에디터 · 단축키 필 · 상태 바).
public struct ContentView: View {
    // 저장소·자동완성은 App(단일 인스턴스)에서 주입받는다 — 창마다 별도 저장소가
    // 생기던 문제를 없애기 위해 소유권을 위로 올렸다.
    @ObservedObject private var store: EntryStore
    @ObservedObject private var completion: CompletionController
    /// 백그라운드 이해 파이프라인 (M6) — nil이면 지식 없이 동작 (프리뷰 등).
    private let indexer: BackgroundIndexer?
    /// ""=시스템 따름 / "light" / "dark" — 툴바 토글로 전환.
    @AppStorage("mint.appearance") private var appearance = ""

    public init(
        store: EntryStore,
        completion: CompletionController,
        indexer: BackgroundIndexer? = nil
    ) {
        self.store = store
        self.completion = completion
        self.indexer = indexer
    }

    public var body: some View {
        MainSurface(store: store, completion: completion, indexer: indexer)
            .frame(minWidth: 860, minHeight: 540)
            .preferredColorScheme(preferredScheme)
            .onAppear {
                // 모델 상주 — 미리 로드해 첫 제안 지연(<~500ms)을 지킨다 (PLAN §10).
                completion.preloadEngine()
                // 예측 조립에 쓸 활성 문서 스냅샷 공급 — 예측 직전 pull (PLAN §10).
                completion.documentContextProvider = { [weak store] in
                    store?.activeDocumentContext
                }
                // 백그라운드 이해 배선 (M6, PLAN §9) — 편집 신호 → 인덱서,
                // 인덱서 스냅샷 → 예측 조립. 활성 문서 불일치는 여기서 거른다.
                if let indexer {
                    indexer.attach(store: store)
                    store.documentDidChange = { [weak indexer] id in
                        indexer?.noteChange(entryID: id)
                    }
                    completion.knowledgeProvider = { [weak indexer, weak store] in
                        guard let snapshot = indexer?.snapshot,
                            snapshot.entryID == store?.activeID
                        else { return nil }
                        return snapshot
                    }
                    // 시작 직후에도 유휴 타이머를 감는다 — 앱을 켜두기만 해도
                    // 열린 작품의 이해가 준비된다 (상주 앱의 이점, CLAUDE.md §1-4).
                    indexer.noteChange(entryID: store.activeID)
                }
            }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

/// preferredColorScheme 적용 *이후*의 유효 테마를 읽기 위한 레이어.
private struct MainSurface: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    /// 인물 감지 후보 UI 배선용 (M6) — 프리뷰 등에서는 nil.
    var indexer: BackgroundIndexer?
    @Environment(\.colorScheme) private var colorScheme
    /// 파일 목록(사이드바) 표시 여부 — 끄면 텍스트 입력에 집중하는 모드.
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true

    var body: some View {
        let theme = MintTheme.of(colorScheme)
        ZStack {
            GlassBackground()
            theme.glassWinC
            // 콘텐츠는 타이틀바(신호등 줄) 안전영역 아래부터 — 사이드바 헤더가
            // 신호등 한 줄 밑에서 우측 날짜 툴바와 나란히 놓인다.
            HSplitView {
                if sidebarVisible {
                    SidebarView(
                        store: store, completion: completion, theme: theme,
                        indexer: indexer
                    )
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 320)
                }
                EditorPane(
                    store: store, completion: completion,
                    settings: completion.settings, theme: theme,
                    indexer: indexer
                )
                .frame(minWidth: 560, maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}

/// 창 전체 리퀴드 글래스 — 창 뒤 화면을 블러·새추레이션 (디자인 backdrop-filter).
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - 에디터 컬럼

struct EditorPane: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    var indexer: BackgroundIndexer?
    /// 집중 모드 — 툴바·상태 바를 숨겨 글에만 집중 (L10). 본문 상단 inset(44pt)이
    /// 신호등 아래에서 시작하므로 타이틀바 없이도 첫 줄이 신호등과 겹치지 않는다.
    @AppStorage("mint.chromeHidden") private var chromeHidden = false

    var body: some View {
        VStack(spacing: 0) {
            if !chromeHidden {
                EditorToolbar(
                    store: store, completion: completion, settings: settings, theme: theme,
                    indexer: indexer)
                theme.sepC.frame(height: 1)
            }
            editor
            if !chromeHidden {
                theme.sepC.frame(height: 1)
                EditorStatusBar(
                    store: store, completion: completion, settings: settings, theme: theme)
            }
        }
    }

    private var editor: some View {
        MintBlockEditor(
            text: bodyBinding, controller: completion, theme: theme,
            lineSpacing: CGFloat(settings.lineSpacing),
            baseFontSize: CGFloat(settings.editorFontSize),
            entryID: store.activeID,
            focusRequest: store.editorFocusRequests,
            searchJump: store.searchJump)
            .overlay(alignment: .topLeading) {
                if (store.activeEntry?.body ?? "").isEmpty {
                    // 본문 가독 폭(EditorMetrics)에 맞춰 placeholder도 같은 좌우 여백을
                    // 따라간다 — 넓은 창에서 본문은 가운데인데 안내문만 왼쪽에 뜨지 않게.
                    GeometryReader { geo in
                        Text("오늘 하루를 적어보세요…")
                            .font(MintFonts.serifUI(20))
                            .foregroundStyle(theme.ghostC)
                            .padding(.top, 51)
                            .padding(.leading, EditorMetrics.sideInset(forWidth: geo.size.width) + 5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if settings.autocompleteEnabled {
                    ShortcutHintPill(active: completion.suggestion != nil, theme: theme)
                        .padding(.bottom, 20)
                }
            }
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { store.activeEntry?.body ?? "" },
            set: { store.updateActiveBody($0) }
        )
    }
}

// MARK: - 툴바 (날짜 · 모델 스위처 · 다크 모드)

struct EditorToolbar: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    var indexer: BackgroundIndexer?
    @AppStorage("mint.appearance") private var appearance = ""
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarButtonHovered = false
    @State private var imageButtonHovered = false
    @State private var helpButtonHovered = false
    @State private var helpOpen = false
    @State private var dateOpen = false
    @State private var dateHovered = false
    @State private var longParagraphOpen = false
    /// 사이드바 섹션 (M6-8) — 배지 클릭이 팝오버 대신 사이드바 패널을 연다.
    @AppStorage("mint.sidebarSection") private var sidebarSection = SidebarSection.files.rawValue

    var body: some View {
        HStack(spacing: 12) {
            sidebarToggle
            dateButton
            // 소설 저널이면 날짜 옆에 종류 배지 = 스토리 바이블 입구 (PLAN §7).
            // M6-8: 팝오버 → 사이드바 패널 승격. 배지는 바이블 섹션을 연다.
            if store.activeEntry?.resolvedKind == .novel {
                Button {
                    sidebarVisible = true
                    sidebarSection = SidebarSection.bible.rawValue
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 9))
                        Text("소설")
                            .font(MintFonts.serifUI(11, .semibold))
                        // 등록된 인물 수 — 배지가 바이블 입구임을 알리는 최소 신호.
                        if let count = store.activeEntry?.characters?.count, count > 0 {
                            Text("\(count)")
                                .font(MintFonts.monoUI(9, .semibold))
                        }
                        // 감지된 인물 후보가 기다리는 중 — 점 하나만 (비침습, M6).
                        if let indexer {
                            CandidateDot(indexer: indexer, store: store, theme: theme)
                        }
                    }
                    .foregroundStyle(theme.novelC)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(theme.novelBgC))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("스토리 바이블 — 사이드바에서 장르·인물·자동 이해")
            }

            // 긴 문단 표시 (docs/editor-paragraph-split.md) — 대상이 있을 때만
            // 조용히 나타난다. 누르면 설명·확인. 원문 수정은 사용자 확인이 필수.
            if completion.longParagraph.count > 0 {
                Button {
                    longParagraphOpen.toggle()
                } label: {
                    Image(systemName: "bolt.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.novelC)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(theme.novelBgC))
                        // 알림 점 — 눈에 띄게 (조용한 아이콘만으론 놓치기 쉬움).
                        // 툴바색 링으로 배경 알약과 분리한다.
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(theme.novelC)
                                .frame(width: 6, height: 6)
                                .overlay(Circle().stroke(theme.toolbarC, lineWidth: 1.5))
                                .offset(x: 3, y: -3)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("긴 문단이 있어 입력이 느려질 수 있어요")
                .popover(isPresented: $longParagraphOpen, arrowEdge: .bottom) {
                    LongParagraphNotice(
                        completion: completion, theme: theme,
                        onDismiss: { longParagraphOpen = false })
                }
            }
            Spacer()
            helpButton
            imageButton
            ModelChip(completion: completion, settings: settings, theme: theme)
            themeSwitch
        }
        // 사이드바를 접으면 툴바가 창 맨 왼쪽까지 차서 신호등(닫기·최소화·최대화)과
        // 겹친다 — 접힘 상태에선 신호등을 비켜 갈 만큼 왼쪽 여백을 준다.
        .padding(.leading, sidebarVisible ? 22 : 84)
        .padding(.trailing, 22)
        .frame(height: 52)
        .background(theme.toolbarC)
    }

    /// 작성일 — 누르면 날짜를 바꿀 수 있다(어제 일을 오늘 적었을 때 등, L9).
    private var dateButton: some View {
        Button {
            dateOpen.toggle()
        } label: {
            Text(store.activeDateLabel)
                .font(MintFonts.uiFont(13.5, .semibold))
                .foregroundStyle(theme.inkC)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(dateHovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { dateHovered = $0 }
        .help("작성일 바꾸기")
        .popover(isPresented: $dateOpen, arrowEdge: .bottom) {
            DatePicker(
                "작성일", selection: dateBinding, displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(14)
            .frame(width: 300)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { store.activeEntry?.createdAt ?? .now },
            set: { if let id = store.activeEntry?.id { store.setDate(id, to: $0) } }
        )
    }

    /// 마크다운 서식 도움말 — 블록·인라인 단축 문법을 발견할 수 있는 유일한 창구.
    /// (예전엔 "# " 같은 변환을 아무도 알 수 없었다.)
    private var helpButton: some View {
        Button {
            helpOpen.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink2C)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(helpButtonHovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { helpButtonHovered = $0 }
        .help("마크다운 서식 도움말")
        .popover(isPresented: $helpOpen, arrowEdge: .bottom) {
            MarkdownCheatSheet(theme: theme)
        }
    }

    /// 이미지 삽입 — 리스폰더 체인으로 에디터(BlockTextView)에 파일 선택을 요청한다.
    /// 붙여넣기(⌘V)·드래그 드롭·⇧⌘I와 같은 삽입 경로를 버튼으로도 노출한다.
    private var imageButton: some View {
        Button {
            NSApp.sendAction(
                #selector(BlockTextView.insertImageFromMenu(_:)), to: nil, from: nil)
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink2C)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(imageButtonHovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { imageButtonHovered = $0 }
        .help("이미지 삽입 (⇧⌘I · 붙여넣기 · 드래그)")
    }

    /// 파일 목록(사이드바) 접기/펴기 — 끄면 입력창에 집중하는 모드.
    private var sidebarToggle: some View {
        Button {
            sidebarVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(sidebarVisible ? theme.ink2C : theme.ink3C)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(sidebarButtonHovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sidebarButtonHovered = $0 }
        .help(sidebarVisible ? "파일 목록 숨기기" : "파일 목록 보이기")
    }

    /// 디자인의 커스텀 스위치 (42×25, ☾) — 리퀴드 글래스 토글.
    private var themeSwitch: some View {
        Button {
            appearance = isDark ? "light" : "dark"
        } label: {
            HStack(spacing: 8) {
                Text("☾")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink3C)
                GlassSwitch(isOn: isDark, theme: theme)
            }
        }
        .buttonStyle(.plain)
        .help("다크 모드")
    }

    private var isDark: Bool {
        appearance == "dark" || (appearance.isEmpty && colorScheme == .dark)
    }
}

/// 소설 배지 안의 인물 후보 대기 점 (M6, PLAN §7) — 감지는 자동이지만 UI는
/// 점 하나뿐이다. 화면을 흔들지 않는다 (CLAUDE.md §3 "고스트는 조용히"의 연장).
private struct CandidateDot: View {
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var store: EntryStore
    let theme: MintTheme

    var body: some View {
        if indexer.candidatesEntryID == store.activeID,
            !indexer.characterCandidates.isEmpty
        {
            Circle()
                .fill(theme.novelC)
                .frame(width: 5, height: 5)
        }
    }
}

/// 모델 상태 칩 + 디자인형 드롭다운 (264px 카드, nano/air/pro).
struct ModelChip: View {
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme

    @State private var menuOpen = false
    @State private var hoveredID: String?
    @State private var chipHovered = false
    /// 모델 가중치 프리페치 — 드롭다운 행의 다운로드 버튼·진행률 담당.
    @StateObject private var downloads = ModelDownloadManager()

    var body: some View {
        Button {
            menuOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                if completion.isPredicting {
                    PulsingDots(color: theme.blueC)
                } else {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                }
                Text(statusLabel)
                    .font(MintFonts.monoUI(11, .semibold))
                    .foregroundStyle(theme.ink2C)
                Text("▼")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.ink3C)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chipHovered ? theme.hoverC : theme.chipC)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.chipBorderC)
            )
        }
        .buttonStyle(.plain)
        .onHover { chipHovered = $0 }
        .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
            dropdown
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("온디바이스 모델")
                .font(MintFonts.monoUI(10.5))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink3C)
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 8)
            theme.sepC.frame(height: 1)
            VStack(spacing: 0) {
                ForEach(ModelChoice.all) { choice in
                    row(choice)
                }
                if ModelChoice.matching(settings.modelID) == nil {
                    customRow
                }
                if case .failed = completion.engineState {
                    theme.sepC.frame(height: 1).padding(.vertical, 4)
                    Button("모델 다시 로드") { completion.retryEngineLoad() }
                        .buttonStyle(.plain)
                        .font(MintFonts.uiFont(12, .medium))
                        .foregroundStyle(theme.blueC)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            .padding(6)
            theme.sepC.frame(height: 1)
            autocompleteToggle
            theme.sepC.frame(height: 1)
            predictionLengthRow
        }
        .frame(width: 264)
        // 열 때마다 로컬 캐시를 다시 확인한다 — 엔진 로드로 받아진 모델도 반영.
        .onAppear { downloads.refresh(ModelChoice.all.map(\.id)) }
    }

    /// 예측 길이(최대 토큰) 조절 — SettingsView(⌘,)의 스테퍼와 같은 값·범위.
    /// 값은 다음 제안부터 적용된다 (parameters 스냅샷 경계).
    private var predictionLengthRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("예측 길이")
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                Text("한 번에 제안하는 최대 토큰")
                    .font(MintFonts.uiFont(11.5))
                    .foregroundStyle(theme.ink2C)
            }
            Spacer(minLength: 0)
            StepIconButton(systemName: "minus", theme: theme, help: "짧게") {
                settings.maxTokens = max(4, settings.maxTokens - 2)
            }
            Text("\(settings.maxTokens)")
                .font(MintFonts.monoUI(12, .semibold))
                .foregroundStyle(theme.inkC)
                .frame(minWidth: 22)
            StepIconButton(systemName: "plus", theme: theme, help: "길게") {
                settings.maxTokens = min(32, settings.maxTokens + 2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    /// 드롭다운 하단의 자동완성 마스터 스위치 — 끄면 제안·모델 로드 중단.
    private var autocompleteToggle: some View {
        Button {
            completion.setAutocompleteEnabled(!settings.autocompleteEnabled)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("자동완성")
                        .font(MintFonts.uiFont(13, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text(settings.autocompleteEnabled
                        ? "글을 멈추면 이어질 내용을 제안해요"
                        : "꺼짐 — 제안하지 않아요")
                        .font(MintFonts.uiFont(11.5))
                        .foregroundStyle(theme.ink2C)
                }
                Spacer(minLength: 0)
                GlassSwitch(isOn: settings.autocompleteEnabled, theme: theme)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("자동완성 켜기/끄기")
    }

    // 행 전체는 탭 제스처(모델 선택), 다운로드 버튼은 내부의 독립 Button —
    // Button 안에 Button을 겹치면 탭이 엉키므로 행을 제스처로 구성한다.
    private func row(_ choice: ModelChoice) -> some View {
        let selected = settings.modelID == choice.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(choice.name)
                        .font(MintFonts.uiFont(13, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text(choice.sizeLabel)
                        .font(MintFonts.monoUI(10.5))
                        .foregroundStyle(theme.ink3C)
                }
                Text(choice.detail)
                    .font(MintFonts.uiFont(11.5))
                    .foregroundStyle(theme.ink2C)
            }
            Spacer(minLength: 0)
            downloadAccessory(choice)
            Text(choice.latencyLabel)
                .font(MintFonts.monoUI(10.5))
                .foregroundStyle(theme.ink3C)
            Text(selected ? "✓" : "")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.blueC)
                .frame(width: 16)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected
                    ? theme.activeBgC
                    : (hoveredID == choice.id ? theme.hoverC : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { pick(choice.id) }
        .onHover { hoveredID = $0 ? choice.id : nil }
    }

    /// 행 우측의 다운로드 상태 — 안 받았으면 받기 버튼, 진행 중엔 %, 받았으면 체크.
    /// 미리 받아 두면 그 모델로 전환할 때 다운로드 없이 바로 로드된다.
    @ViewBuilder
    private func downloadAccessory(_ choice: ModelChoice) -> some View {
        switch downloads.states[choice.id] {
        case .downloading(let fraction):
            Button {
                downloads.cancel(choice.id)
            } label: {
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(MintFonts.monoUI(10, .semibold))
                    .foregroundStyle(theme.blueC)
            }
            .buttonStyle(.plain)
            .help("다운로드 중 — 누르면 취소")
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3C)
                .help("다운로드됨 — 전환 시 바로 로드")
        case .failed(let message):
            Button {
                downloads.download(choice.id)
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink2C)
            }
            .buttonStyle(.plain)
            .help("실패 — 다시 시도 (\(message))")
        case .notDownloaded, .none:
            Button {
                downloads.download(choice.id)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.blueC)
            }
            .buttonStyle(.plain)
            .help("모델 미리 받기 (\(choice.sizeLabel))")
        }
    }

    /// Settings(⌘,)에서 직접 입력한 저장소 id도 선택 상태로 보이게.
    private var customRow: some View {
        HStack(spacing: 10) {
            Text(ModelChip.shortID(settings.modelID))
                .font(MintFonts.uiFont(12, .semibold))
                .foregroundStyle(theme.inkC)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("✓")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.blueC)
                .frame(width: 16)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.activeBgC)
        )
    }

    private func pick(_ id: String) {
        menuOpen = false
        guard id != settings.modelID else { return }
        settings.modelID = id
        completion.modelDidChange()
    }

    private var statusLabel: String {
        "\(ModelChip.displayName(settings.modelID)) · \(stateText)"
    }

    private var stateText: String {
        if !settings.autocompleteEnabled { return "꺼짐" }
        if completion.isPredicting { return "예측 중" }
        switch completion.engineState {
        case .idle: return "대기"
        case .downloading(let fraction): return String(format: "다운로드 %.0f%%", fraction * 100)
        case .loading: return "로드 중"
        case .ready: return completion.suggestion != nil ? "제안 준비됨" : "대기"
        case .failed: return "오류"
        }
    }

    private var dotColor: Color {
        if !settings.autocompleteEnabled { return theme.ink3C }
        return switch completion.engineState {
        case .idle: theme.ink3C
        case .downloading, .loading: .orange
        case .ready: completion.suggestion != nil ? theme.inkC : theme.ink3C
        case .failed: .red
        }
    }

    static func displayName(_ modelID: String) -> String {
        ModelChoice.matching(modelID)?.name ?? shortID(modelID)
    }

    static func shortID(_ modelID: String) -> String {
        modelID.components(separatedBy: "/").last ?? modelID
    }
}

/// 드롭다운의 작은 ± 스텝 버튼 — 칩과 같은 유리 톤.
private struct StepIconButton: View {
    let systemName: String
    let theme: MintTheme
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.ink2C)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovered ? theme.hoverC : theme.chipC)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.chipBorderC)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// 리퀴드 글래스 토글 스위치 (42×25) — 창 유리 톤과 통일된 디테일.
///
/// 트랙은 ultraThinMaterial 위에 유리 틴트 + 헤어라인 보더, 노브는 흰 원.
/// 다크 모드 스위치·자동완성 스위치 등 모든 토글이 이 컴포넌트를 공유한다.
struct GlassSwitch: View {
    let isOn: Bool
    let theme: MintTheme

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? theme.blueC.opacity(0.85) : theme.chipC)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.chipBorderC))
                .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
            Circle()
                .fill(.white)
                .frame(width: 21, height: 21)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .offset(x: isOn ? 19 : 2)
        }
        .frame(width: 42, height: 25)
        .animation(.spring(duration: 0.25), value: isOn)
    }
}

/// "예측 중" 점 세 개 애니메이션 (디자인 mint-dot).
struct PulsingDots: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(pulsing ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: pulsing
                    )
            }
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - 마크다운 치트시트

/// 도움말 버튼 팝오버 — 줄 맨 앞/인라인 단축 문법을 한눈에.
struct MarkdownCheatSheet: View {
    let theme: MintTheme

    private struct Item: Identifiable {
        let id = UUID()
        let syntax: String
        let label: String
    }

    private static let blocks: [Item] = [
        Item(syntax: "# ", label: "제목 1"),
        Item(syntax: "## ", label: "제목 2"),
        Item(syntax: "### ", label: "제목 3"),
        Item(syntax: "- ", label: "글머리 목록"),
        Item(syntax: "1. ", label: "번호 목록"),
        Item(syntax: "[ ] ", label: "체크리스트"),
        Item(syntax: "> ", label: "인용"),
        Item(syntax: "```", label: "코드 블록"),
        Item(syntax: "$$ ", label: "수식 (LaTeX)"),
        Item(syntax: "---", label: "구분선"),
    ]

    private static let inlines: [Item] = [
        Item(syntax: "**굵게**", label: "굵게"),
        Item(syntax: "*기울임*", label: "기울임"),
        Item(syntax: "`코드`", label: "인라인 코드"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("줄 맨 앞에서 입력")
            ForEach(Self.blocks) { row($0) }
            theme.sepC.frame(height: 1).padding(.vertical, 7)
            sectionTitle("인라인")
            ForEach(Self.inlines) { row($0) }
            theme.sepC.frame(height: 1).padding(.vertical, 7)
            Text("서식 메뉴(⌘⌥1~3, ⌘B/⌘I 등)로도 적용할 수 있어요.")
                .font(MintFonts.uiFont(11))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 264)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(MintFonts.monoUI(10))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundStyle(theme.ink3C)
            .padding(.bottom, 6)
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Text(item.syntax)
                .font(MintFonts.monoUI(11.5, .semibold))
                .foregroundStyle(theme.inkC)
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme.chipC))
            Spacer(minLength: 8)
            Text(item.label)
                .font(MintFonts.uiFont(12))
                .foregroundStyle(theme.ink2C)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 단축키 힌트 필

/// 에디터 하단 중앙의 고스트 단축키 안내 (tab / → / esc, 디자인 sticky pill).
struct ShortcutHintPill: View {
    let active: Bool
    let theme: MintTheme

    var body: some View {
        HStack(spacing: 14) {
            item(key: "tab", label: "수락")
            divider
            item(key: "→", label: "한 단어")
            divider
            item(key: "esc", label: "무시")
        }
        .fixedSize()  // 폭이 좁아도 "t…"처럼 생략하지 않고 전부 그린다
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.pillC)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.pillBorderC)
        )
        .shadow(color: .black.opacity(0.16), radius: 15, y: 5)
        .opacity(active ? 1 : 0.6)
        .animation(.easeOut(duration: 0.2), value: active)
        .allowsHitTesting(false)
    }

    private func item(key: String, label: String) -> some View {
        HStack(spacing: 7) {
            Text(key)
                .font(MintFonts.monoUI(11, .bold))
                .foregroundStyle(theme.inkC)
                .padding(.vertical, 2)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(theme.kbdC)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5).strokeBorder(theme.sepStrongC)
                )
            Text(label)
                .font(MintFonts.uiFont(12))
                .foregroundStyle(theme.ink2C)
        }
    }

    private var divider: some View {
        theme.sepC.frame(width: 1, height: 16)
    }
}

// MARK: - 상태 바

/// 단어 수 · 글자 수 · 읽는 시간 · Markdown (상용 v1.0 — 글쓰기 지표 중심).
///
/// 예전엔 모델명·지연·토큰 같은 개발용 텔레메트리를 늘어놨는데, 글쓰기 앱에선
/// 개발 콘솔처럼 보여 몰입을 깼다. 작가가 흘끗 보고 싶은 값(단어·글자·읽는 시간)만
/// 남기고, 모델 상태는 툴바의 ModelChip이 담당한다.
struct EditorStatusBar: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme

    var body: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) 단어")
            separator
            Text("\(charCount) 자")
            if !readingLabel.isEmpty {
                separator
                Text("읽기 \(readingLabel)")
            }
            if case .failed = completion.engineState {
                separator
                Text("자동완성 로드 실패")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button("다시 시도") { completion.retryEngineLoad() }
                    .buttonStyle(.link)
                    .font(MintFonts.monoUI(11))
            }
            Spacer()
            Text(store.isSaving ? "저장 중…" : "저장됨")
            separator
            Text("Markdown")
        }
        .font(MintFonts.monoUI(11))
        .foregroundStyle(theme.ink3C)
        .padding(.horizontal, 22)
        .frame(height: 34)
        .background(theme.statusbarC)
    }

    private var separator: some View {
        theme.sepC.frame(width: 1, height: 12)
    }

    private var text: String { store.activeEntry?.body ?? "" }

    /// 공백을 제외한 글자 수 (국문 글자 수 관례).
    private var charCount: Int {
        text.filter { !$0.isWhitespace }.count
    }

    /// 공백으로 나뉜 어절/단어 수 — 한글 어절·영문 단어 모두에 자연스럽다.
    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// 읽는 데 걸리는 대략 시간 — 한글 기준 분당 약 500자.
    private var readingLabel: String {
        guard charCount > 0 else { return "" }
        let minutes = Double(charCount) / 500
        if minutes < 1 { return "1분 미만" }
        return "약 \(Int(minutes.rounded()))분"
    }
}

/// 긴 문단 안내·확인 팝오버 (docs/editor-paragraph-split.md).
///
/// 원문을 수정하는 기능이라 **설명이 핵심**이다 — 왜 원고에 손을 대는지, 무엇이
/// 바뀌는지(글자 불변, 개행만), 되돌릴 수 있는지를 알려 사용자가 동의하게 한다.
/// 숫자는 감지 결과의 실제 수치라 막연한 안내가 아니다.
struct LongParagraphNotice: View {
    @ObservedObject var completion: CompletionController
    let theme: MintTheme
    let onDismiss: () -> Void
    @State private var detailShown = false
    @State private var splitResult: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.novelC)
                Text("아주 긴 문단이 있어요")
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                Spacer()
            }

            if let result = splitResult {
                // 실행 후 조용한 확인.
                Text(result > 0
                    ? "긴 문단 \(result)개를 문장 경계에서 나눴어요. ⌘Z로 되돌릴 수 있어요."
                    : "나눌 문단을 찾지 못했어요.")
                    .font(MintFonts.uiFont(11.5))
                    .foregroundStyle(theme.ink2C)
                    .fixedSize(horizontal: false, vertical: true)
                Button("닫기") { onDismiss() }
                    .font(MintFonts.uiFont(12, .medium))
            } else {
                Text("빠르게 입력하면 끊길 수 있어요.")
                    .font(MintFonts.uiFont(11.5))
                    .foregroundStyle(theme.ink2C)

                if detailShown {
                    Text(detailText)
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(theme.ink2C)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                HStack(spacing: 8) {
                    Button {
                        // 감지 count는 실행 후 0으로 갱신되므로 먼저 확보한다.
                        let before = completion.longParagraph.count
                        completion.performLongParagraphSplit()
                        splitResult = before
                    } label: {
                        Text("문단 나누기")
                            .font(MintFonts.uiFont(12, .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(theme.novelC))
                    }
                    .buttonStyle(.plain)

                    Button(detailShown ? "접기" : "자세히") { detailShown.toggle() }
                        .font(MintFonts.uiFont(12, .medium))
                    Spacer()
                    Button("그대로 두기") { onDismiss() }
                        .font(MintFonts.uiFont(12))
                        .foregroundStyle(theme.ink3C)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var detailText: String {
        let info = completion.longParagraph
        let ratio = info.ratio
        let ratioText = ratio > 1 ? "보통 문단의 \(ratio)배가 넘어요" : "아주 길어요"
        return """
            에디터는 문단 하나를 통째로 다시 배치하기 때문에, 문단이 길수록 글자 하나 \
            입력에 드는 비용이 커져요. 이 문서에서 가장 긴 문단은 약 \
            \(info.maxLength.formatted())자로, \(ratioText).

            문장 경계에서 이 문단을 몇 개로 나누면 입력이 다시 매끄러워져요. 글자는 \
            하나도 바뀌지 않고, 문단 사이에 빈 줄만 들어가요. 마음에 안 들면 ⌘Z 한 \
            번으로 되돌릴 수 있어요.

            나눌 문단: \(info.count)개 · 문장 중간은 자르지 않아요.
            """
    }
}

#Preview {
    ContentView(store: EntryStore(), completion: CompletionController())
        .frame(width: 1180, height: 760)
}
