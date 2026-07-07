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
    /// ""=시스템 따름 / "light" / "dark" — 툴바 토글로 전환.
    @AppStorage("mint.appearance") private var appearance = ""

    public init(store: EntryStore, completion: CompletionController) {
        self.store = store
        self.completion = completion
    }

    public var body: some View {
        MainSurface(store: store, completion: completion)
            .frame(minWidth: 860, minHeight: 540)
            .preferredColorScheme(preferredScheme)
            .onAppear {
                // 모델 상주(PLAN §9-2) — 미리 로드해 첫 제안 지연(<~500ms)을 지킨다.
                completion.preloadEngine()
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
                    SidebarView(store: store, theme: theme)
                        .frame(minWidth: 200, idealWidth: 250, maxWidth: 320)
                }
                EditorPane(
                    store: store, completion: completion,
                    settings: completion.settings, theme: theme
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

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                store: store, completion: completion, settings: settings, theme: theme)
            theme.sepC.frame(height: 1)
            editor
            theme.sepC.frame(height: 1)
            EditorStatusBar(
                store: store, completion: completion, settings: settings, theme: theme)
        }
    }

    private var editor: some View {
        MintBlockEditor(
            text: bodyBinding, controller: completion, theme: theme,
            lineSpacing: CGFloat(settings.lineSpacing))
            .overlay(alignment: .topLeading) {
                if (store.activeEntry?.body ?? "").isEmpty {
                    Text("오늘 하루를 적어보세요…")
                        .font(MintFonts.serifUI(20))
                        .foregroundStyle(theme.ghostC)
                        // MintBlockEditor의 textContainerInset(56,44)에 맞춰 정렬.
                        .padding(.top, 51)
                        .padding(.leading, 61)
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
    @AppStorage("mint.appearance") private var appearance = ""
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarButtonHovered = false
    @State private var imageButtonHovered = false

    var body: some View {
        HStack(spacing: 12) {
            sidebarToggle
            Text(store.activeDateLabel)
                .font(MintFonts.uiFont(13.5, .semibold))
                .foregroundStyle(theme.inkC)
            Spacer()
            imageButton
            ModelChip(completion: completion, settings: settings, theme: theme)
            themeSwitch
        }
        .padding(.horizontal, 22)
        .frame(height: 52)
        .background(theme.toolbarC)
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

/// 모델 상태 칩 + 디자인형 드롭다운 (264px 카드, nano/air/pro).
struct ModelChip: View {
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme

    @State private var menuOpen = false
    @State private var hoveredID: String?
    @State private var chipHovered = false

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

    private func row(_ choice: ModelChoice) -> some View {
        let selected = settings.modelID == choice.id
        return Button {
            pick(choice.id)
        } label: {
            HStack(spacing: 10) {
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
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? choice.id : nil }
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

/// 글자 수 · 모델 · Markdown · (실패 시 재시도) · 예측 토큰 (디자인 v3).
struct EditorStatusBar: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme

    var body: some View {
        HStack(spacing: 16) {
            Text("\(charCount)자")
            separator
            Text(modelLabel)
            separator
            Text("Markdown")
            if case .failed(let message) = completion.engineState {
                separator
                Text("로드 실패: \(message)")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                Button("다시 시도") { completion.retryEngineLoad() }
                    .buttonStyle(.link)
                    .font(MintFonts.monoUI(11))
            }
            Spacer()
            Text(ghostLabel)
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

    private var charCount: Int {
        (store.activeEntry?.body ?? "").filter { !$0.isWhitespace }.count
    }

    private var modelLabel: String {
        var label = ModelChip.displayName(settings.modelID)
        if let choice = ModelChoice.matching(settings.modelID) {
            label += " \(choice.sizeLabel)"
        }
        label += " · 온디바이스"
        switch completion.engineState {
        case .downloading(let fraction):
            label += String(format: " · 다운로드 %.0f%%", fraction * 100)
        case .loading:
            label += " · 로드 중"
        case .ready:
            if let latency = completion.lastLatency {
                label += String(format: " · 최근 %.2fs", latency)
            }
        default:
            break
        }
        return label
    }

    private var ghostLabel: String {
        if !settings.autocompleteEnabled { return "자동완성 꺼짐" }
        if let suggestion = completion.suggestion {
            let length = suggestion.trimmingCharacters(in: .whitespaces).count
            return "\(max(1, length / 2)) tokens · 예측"
        }
        return completion.isPredicting ? "예측 중…" : "대기"
    }
}

#Preview {
    ContentView(store: EntryStore(), completion: CompletionController())
        .frame(width: 1180, height: 760)
}
