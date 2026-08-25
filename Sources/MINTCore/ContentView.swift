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
    /// ""=시스템 따름 / "light" / "dark" — 설정에서 전환.
    @AppStorage("mint.appearance") private var appearance = ""
    /// 손상 복구 안내를 이번 세션에서 닫았는지 — 닫아도 저장 우회 보호는 계속된다.
    @State private var recoveryGuideDismissed = false
    /// 첫 실행 모델 선택 시트 (#40) — 기본 모델(Basil 16.9GB)의 조용한 자동
    /// 다운로드 전에 사용자가 크기·성격을 보고 고르게 한다.
    @ObservedObject private var settings: CompletionSettings

    public init(
        store: EntryStore,
        completion: CompletionController,
        indexer: BackgroundIndexer? = nil
    ) {
        self.store = store
        self.completion = completion
        self.indexer = indexer
        self.settings = completion.settings
    }

    public var body: some View {
        MainSurface(store: store, completion: completion, indexer: indexer)
            .frame(minWidth: 860, minHeight: 540)
            .preferredColorScheme(preferredScheme)
            .confirmationDialog(
                "원고 파일 복구",
                isPresented: recoveryDialogBinding,
                titleVisibility: .visible
            ) {
                Button("안전 내보내기…") { exportSessionCopy() }
                if let preserved = store.pendingRecovery?.preservedCopyURL {
                    Button("보존 사본 위치 열기") {
                        NSWorkspace.shared.activateFileViewerSelecting([preserved])
                    }
                }
                Button("복구 파일로 라이브러리 승계", role: .destructive) {
                    store.adoptRecoveredAsLibrary()
                    recoveryGuideDismissed = false
                }
            } message: {
                Text(recoveryMessage)
            }
            // 첫 실행 모델 선택 (#40) — 확인 전엔 시트가 뜨고 시작 preload는 보류.
            .sheet(isPresented: initialModelSheetBinding) {
                InitialModelPicker(settings: settings) {
                    completion.preloadEngine()
                }
            }
            .onAppear {
                // 모델 상주 — 미리 로드해 첫 제안 지연(<~500ms)을 지킨다 (PLAN §10).
                // 첫 실행(선택 전)이면 시트가 대신 받고, 고른 뒤 preload한다 (#40).
                if settings.initialModelConfirmed { completion.preloadEngine() }
                // 예측 조립에 쓸 활성 문서 스냅샷 공급 — 예측 직전 pull (PLAN §10).
                completion.documentContextProvider = { [weak store] in
                    store?.activeDocumentContext
                }
                // 대화 기록 (요구사항 §20–§21) — Enter 승인 → 마크다운 본문
                // 좌표로 재앵커해 entries.json에 저장. 스토어가 재조립 신호를 쏜다.
                completion.onRecordConversation = { [weak store] record in
                    guard let store else { return }
                    var record = record
                    if let body = store.activeEntry?.body {
                        record = ConversationDetector.reanchor(record, in: body as NSString)
                            ?? record
                    }
                    store.recordConversation(record, in: store.activeID)
                }
                completion.recordedConversationHashesProvider = { [weak store] in
                    Set((store?.activeEntry?.recordedConversations ?? []).map(\.contentHash))
                }
                // 백그라운드 이해 배선 (M6, PLAN §9) — 편집 신호 → 인덱서,
                // 인덱서 스냅샷 → 예측 조립. 활성 문서 불일치는 여기서 거른다.
                if let indexer {
                    indexer.attach(store: store)
                    store.documentDidChange = { [weak indexer, weak completion] id in
                        indexer?.noteChange(entryID: id)
                        // 문서 전환을 예측 쪽에도 알린다 — 이전 작품의 고스트·
                        // 리포트가 B 화면에 남거나 B 오버라이드에 기록되지 않게
                        // (이슈 #8, Gate 2).
                        completion?.noteDocumentSwitch(to: id)
                    }
                    // 사용자 수정(오버라이드) 변경 → LLM 없이 스냅샷만 재조립
                    // (v4) — 타임라인·바이블·예측이 즉시 수정본을 본다.
                    store.narrativeOverridesDidChange = { [weak indexer] id in
                        indexer?.rehydrate(entryID: id)
                    }
                    // 커서 거리순 이해 (docs/m6-scene-split.md §5) — 쓰고 있는
                    // 자리 근처부터 읽는다. 값 pull이라 키 입력 비용 없음.
                    indexer.caretProvider = { [weak completion] in
                        completion?.lastCaretLocation
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

    // MARK: - 손상 복구 안내 (이슈 #6)

    /// 복구 모드에서만 뜨고, 사용자가 닫으면 이번 세션에선 다시 열지 않는다.
    /// 닫아도 데이터는 안전 — 저장은 계속 세션 복구 파일로 우회된다.
    private var recoveryDialogBinding: Binding<Bool> {
        Binding(
            get: { store.pendingRecovery != nil && !recoveryGuideDismissed },
            set: { shown in if !shown { recoveryGuideDismissed = true } })
    }

    /// 첫 실행 모델 선택 시트 바인딩 (#40) — 한 번 확인하면 다시 뜨지 않는다.
    private var initialModelSheetBinding: Binding<Bool> {
        Binding(
            get: { !settings.initialModelConfirmed },
            set: { shown in
                // 시트를 내리는 길은 사용자의 선택(고르기·나중에)뿐이다.
                // 드래그로 닫아도 "나중에"와 같다 — 다음 실행에선 다시 묻지 않는다.
                if !shown { settings.initialModelConfirmed = true }
            })
    }

    private var recoveryTitle: String {
        switch store.pendingRecovery?.cause {
        case .unreadable: "원고 파일을 읽을 수 없습니다"
        default: "원고 파일이 손상되어 있습니다"
        }
    }

    private var recoveryMessage: String {
        guard let recovery = store.pendingRecovery else { return "" }
        var lines = ["""
            원본은 그대로 보존됐고, 이 세션의 입력은 아래 복구 파일에 기록됩니다 \
            (손상 원본을 덮지 않기 위한 우회).
            """
        ]
        lines.append("• 원본: \(recovery.originalURL.lastPathComponent)")
        if let preserved = recovery.preservedCopyURL {
            lines.append("• 보존 사본: \(preserved.lastPathComponent)")
        }
        if case .corrupted(let reason) = recovery.cause {
            lines.append("• 오류: \(reason)")
        } else if case .unreadable(let message) = recovery.cause {
            lines.append("• 오류: \(message)")
        }
        lines.append("• 이 세션 기록: \(recovery.sessionURL.lastPathComponent)")
        return lines.joined(separator: "\n")
    }

    /// 현재 세션 전체를 사용자가 고른 위치로 내보낸다 (SavePanel).
    private func exportSessionCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = store.pendingRecovery?.sessionURL.lastPathComponent
            ?? "entries-recovered.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = store.exportSessionCopy(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// preferredColorScheme 적용 *이후*의 유효 테마를 읽기 위한 레이어.
private struct MainSurface: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    /// 인물 감지 후보 UI 배선용 (M6) — 프리뷰 등에서는 nil.
    var indexer: BackgroundIndexer?
    @Environment(\.colorScheme) private var colorScheme
    /// 창의 undo manager — 구조 변경(삭제·이동·바이블 메타) undo가 텍스트
    /// 편집과 같은 ⌘Z 흐름을 타게 배선한다 (이슈 #9).
    @Environment(\.undoManager) private var windowUndoManager
    /// 사용자 색상 팔레트 — 관찰해서 설정에서 색을 바꾸는 즉시 화면에 반영한다.
    // 앱 수명 싱글턴 — 뷰 수명과 무관한 소유 의미라 StateObject가 맞다 (#60).
    @StateObject private var palette = PaletteSettings.shared
    /// 파일 목록(사이드바) 표시 여부 — 끄면 텍스트 입력에 집중하는 모드.
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    /// 사이드바 폭 — 사용자가 divider를 끌어 조절하며 UserDefaults에 보존된다.
    /// HSplitView를 버리고 폭을 직접 소유하는 이유: 근접 감지·확대 히트영역을
    /// 가진 커스텀 divider(아래 SidebarResizeDivider)를 붙이기 위함.
    @AppStorage("mint.sidebarWidth") private var sidebarWidth = 250.0

    /// 사이드바 폭 한계 — 너무 좁으면 섹션 UI가 깨지고, 너무 넓으면 본문 가독 폭을 침범.
    private let sidebarMin: CGFloat = 200
    private let sidebarMax: CGFloat = 360

    private var clampedSidebarWidth: CGFloat {
        min(max(CGFloat(sidebarWidth), sidebarMin), sidebarMax)
    }

    var body: some View {
        let theme = palette.theme(for: colorScheme)
        // 구조 undo 배선 — 창마다 다시 잡는다 (⌘Z가 스토어 변경을 되돌린다).
        store.structureUndoManager = windowUndoManager
        return ZStack {
            GlassBackground()
            theme.glassWinC
            // 콘텐츠는 타이틀바(신호등 줄) 안전영역 아래부터 — 사이드바 헤더가
            // 신호등 한 줄 밑에서 우측 날짜 툴바와 나란히 놓인다.
            HStack(spacing: 0) {
                if sidebarVisible {
                    SidebarView(
                        store: store, completion: completion, theme: theme,
                        indexer: indexer
                    )
                    .frame(width: clampedSidebarWidth)
                }
                EditorPane(
                    store: store, completion: completion,
                    settings: completion.settings, theme: theme,
                    indexer: indexer
                )
                .frame(minWidth: 560, maxWidth: .infinity)
            }
            // divider는 레이아웃에 폭을 차지하지 않는 overlay다 — 근접 감지존이
            // 양쪽 패널 위로 넓게 겹치되(±12pt) 평상시엔 클릭을 가로채지 않는다.
            // 경계선 x = 사이드바 폭. 커스텀 NSView가 hitTest로 idle에선 얇은
            // 영역만 claim하므로 넓은 존이 다른 UI interaction을 삼키지 않는다.
            .overlay(alignment: .leading) {
                if sidebarVisible {
                    SidebarResizeDivider(
                        width: Binding(
                            get: { CGFloat(sidebarWidth) },
                            set: { sidebarWidth = Double($0) }),
                        minWidth: sidebarMin, maxWidth: sidebarMax, theme: theme
                    )
                    // 폭 24 = 근접 감지존 ±12pt. 경계선 위에 정중앙 정렬하려고
                    // 절반(12)만큼 좌측 보정한다.
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .offset(x: clampedSidebarWidth - 12)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 사이드바-에디터 사이 커스텀 분할 divider — 근접 감지·확대 히트영역·리사이즈 커서.
///
/// **왜 AppKit(NSViewRepresentable)인가.** SwiftUI의 `.onHover`는 히트테스트에
/// 참여하는 뷰에서만 발동하므로 "넓은 근접존이 hover는 감지하되 클릭은 가로채지
/// 않는다"를 표현할 수 없다. NSTrackingArea(마우스 이동 감지)와 hitTest(클릭
/// 가로채기)는 서로 독립적이라, 이 둘을 분리하면 idle에서 넓은 존이 아무
/// interaction도 삼키지 않게 만들 수 있다.
///
/// 상태: idle(얇은 선 + ±3pt 히트) → pointerNear(굵은 선 + ±9pt 히트 + resize
/// 커서) → dragging(near 유지 + 실시간 리사이즈). 근접 감지 트래킹 영역(±12pt)은
/// 상태와 무관하게 고정 크기라, 히트영역이 확대되는 순간 hover가 풀리는
/// flickering이 생기지 않는다.
private struct SidebarResizeDivider: NSViewRepresentable {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let theme: MintTheme

    func makeNSView(context: Context) -> DividerHandleView {
        let view = DividerHandleView()
        configure(view)
        return view
    }

    func updateNSView(_ view: DividerHandleView, context: Context) {
        configure(view)
    }

    private func configure(_ view: DividerHandleView) {
        view.minWidth = minWidth
        view.maxWidth = maxWidth
        // idle 선은 그리지 않는다 — 사이드바가 이미 우측에 1px sep을 그려
        // 경계에 얇은 선이 있다. near/dragging에서만 굵은 선을 덧그린다.
        view.idleLineColor = .clear
        view.nearLineColor = theme.ink3
        // Binding은 매 업데이트마다 최신값을 읽도록 클로저로 감싼다.
        view.currentWidth = { width }
        view.onWidthChange = { newWidth in width = newWidth }
    }
}

/// SidebarResizeDivider의 실제 AppKit 뷰. 좌표 x만 다루므로 flipped 여부는 무관.
///
/// 접근성 (#59): 마우스 드래그 전용이던 너비 조절을 **조절 가능(adjustable) AX
/// 요소**로 노출한다 — VoiceOver 스와이프·Full Keyboard Access 방향키로 ±20pt.
final class DividerHandleView: NSView {
    var onWidthChange: ((CGFloat) -> Void)?
    var currentWidth: (() -> CGFloat)?
    var minWidth: CGFloat = 200
    var maxWidth: CGFloat = 360

    // NSAccessibility 프로토콜 위트니스 중 상위에 선언이 있는 것(isAccessibility·
    // Role·Label)만 override이고, 값·증감(NSAccessibilityValue/Incrementor
    // 프로토콜 기본 구현)은 키워드 없이 대체한다.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "사이드바 너비" }
    override func accessibilityValue() -> Any? {
        Int(currentWidth?() ?? 0)
    }
    // 증감은 NSAccessibilityIncrementor/Decrementor 프로토콜 기본 구현 대체 —
    // 상위 클래스 선언이 없어 override 키워드를 쓰지 않는다.
    func accessibilityIncrement() {
        adjust(by: 20)
    }
    func accessibilityDecrement() {
        adjust(by: -20)
    }

    private func adjust(by delta: CGFloat) {
        guard let onWidthChange else { return }
        let next = min(max((currentWidth?() ?? 0) + delta, minWidth), maxWidth)
        onWidthChange(next)
        // 값 변화를 VoiceOver에 알린다 — 슬라이더 규약 (요구사항 §33의 로컬 원칙).
        NSAccessibility.post(
            element: self, notification: .valueChanged)
    }
    var idleLineColor: NSColor = .clear { didSet { needsDisplay = true } }
    var nearLineColor: NSColor = .clear { didSet { needsDisplay = true } }

    /// 확대 히트영역 반폭 — near/dragging에서 여기까지 클릭을 잡고 resize 커서.
    private let expandedHalf: CGFloat = 9
    /// idle 히트영역 반폭 — 평상시엔 이 얇은 대역만 claim(나머지는 통과).
    private let idleHalf: CGFloat = 3

    private enum State { case idle, near, dragging }
    private var state: State = .idle {
        didSet { if oldValue != state { needsDisplay = true } }
    }
    private var isActive: Bool { state != .idle }

    private var trackingArea: NSTrackingArea?
    private var dragStartMouseX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        // 근접 감지는 뷰 전체(±12pt) 고정 — 상태에 따라 크기가 바뀌지 않으므로
        // enter/exit이 재발화되며 깜빡이지 않는다.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // idle에선 ±3pt만, near/dragging에선 ±9pt만 claim한다. 그 밖의 점은 nil을
    // 반환해 아래 패널(사이드바·에디터)로 클릭이 통과한다 — 넓은 존이 평상시
    // 다른 interaction을 가로채지 않게 하는 핵심.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let half = isActive ? expandedHalf : idleHalf
        return abs(local.x - bounds.midX) <= half ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        if state != .dragging { state = .near }
        updateCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard state != .dragging else { return }
        state = .near
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        // 드래그 중엔 존을 벗어나도 상태를 유지한다 — mouseUp에서 정리.
        guard state != .dragging else { return }
        state = .idle
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        state = .dragging
        dragStartMouseX = event.locationInWindow.x
        dragStartWidth = currentWidth?() ?? bounds.width
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard state == .dragging else { return }
        // 드래그가 존을 벗어나도 mouseUp까지 이벤트가 이 뷰로 계속 라우팅된다.
        let dx = event.locationInWindow.x - dragStartMouseX
        let newWidth = max(minWidth, min(maxWidth, dragStartWidth + dx))
        NSCursor.resizeLeftRight.set()
        onWidthChange?(newWidth)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if bounds.contains(local) {
            state = .near
            updateCursor(for: event)
        } else {
            state = .idle
            NSCursor.arrow.set()
        }
    }

    /// 확대 히트영역(±9pt) 안에서만 resize 커서 — 감지존 바깥 테두리(9~12pt)는
    /// 선만 굵어지고 커서는 기본이라 "잡을 수 있는 곳"이 커서로 정직하게 드러난다.
    private func updateCursor(for event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if abs(local.x - bounds.midX) <= expandedHalf {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = isActive ? 3 : 1
        let color = isActive ? nearLineColor : idleLineColor
        guard color.alphaComponent > 0 else { return }
        color.setFill()
        NSRect(
            x: bounds.midX - lineWidth / 2, y: 0,
            width: lineWidth, height: bounds.height
        ).fill()
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

// MARK: - 툴바 (사이드바 · 소설 배지 · 모델 스위처)

/// 상단바는 **글을 쓰는 동안 필요한 것**만 남긴다 — 날짜·다크 모드·도움말·이미지
/// 삽입은 한 번 정하면 잘 바뀌지 않거나 단축키/메뉴로 이미 닿을 수 있어 설정(⌘,)과
/// 메뉴로 옮겼다 (CLAUDE.md §3 "고스트는 조용히"의 연장 — 화면의 소음을 줄인다).
struct EditorToolbar: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    var indexer: BackgroundIndexer?
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @State private var sidebarButtonHovered = false
    @State private var settingsButtonHovered = false
    @State private var longParagraphOpen = false
    /// ⌘,의 Settings 씬을 여는 표준 액션 (macOS 14+). 다크 모드·사용 방법·
    /// 저자 이름이 전부 설정으로 옮겨 가면서 눈에 보이는 입구가 필요해졌다.
    @Environment(\.openSettings) private var openSettings
    /// 사이드바 섹션 (M6-8) — 배지 클릭이 팝오버 대신 사이드바 패널을 연다.
    @AppStorage("mint.sidebarSection") private var sidebarSection = SidebarSection.files.rawValue

    var body: some View {
        HStack(spacing: 10) {
            sidebarToggle
            // 소설 저널이면 종류 배지 = 스토리 바이블 입구 (PLAN §7).
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
                .accessibilityLabel(Text("스토리 바이블"))
                // 색점 없이도 후보 대기를 알 수 있게 (#59-3).
                .accessibilityValue(
                    Text(bibleBadgeAXValue(indexer: indexer, store: store)))
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
            ModelChip(completion: completion, settings: settings, theme: theme)
            settingsButton
        }
        // 사이드바를 접으면 툴바가 창 맨 왼쪽까지 차서 신호등(닫기·최소화·최대화)과
        // 겹친다 — 접힘 상태에선 신호등을 비켜 갈 만큼 왼쪽 여백을 준다.
        .padding(.leading, sidebarVisible ? 22 : 84)
        .padding(.trailing, 22)
        .frame(minHeight: 52)
        .background(theme.toolbarC)
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
            .accessibilityLabel(Text(sidebarVisible ? "파일 목록 숨기기" : "파일 목록 보이기"))
    }

    /// 설정 — ⌘,와 같은 Settings 창을 연다. 모델·제안·다크 모드·저자 이름·
    /// 사용 방법이 전부 그 안에 있으므로 툴바의 유일한 설정 입구다.
    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.ink2C)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(settingsButtonHovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { settingsButtonHovered = $0 }
        .help("설정 (⌘,) — 모델·제안·다크 모드·저자 이름·사용 방법")
            .accessibilityLabel(Text("설정"))
    }
}

/// 스토리 바이블 배지의 VoiceOver 값 — 후보 대기 수를 읽는다 (#59-3).
@MainActor
private func bibleBadgeAXValue(indexer: BackgroundIndexer?, store: EntryStore) -> String {
    guard let indexer,
        indexer.candidatesEntryID == store.activeID,
        !indexer.characterCandidates.isEmpty
    else { return "" }
    return "인물 후보 검토 \(indexer.characterCandidates.count)명 대기"
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
                // 상태 의미는 색이 아니라 소리로 전달한다 (#59): 점은 AX에서 숨기고
                // 부모 배지의 accessibilityValue가 "검토 후보 N명"을 말한다.
                .accessibilityHidden(true)
        }
    }
}

/// 모델 상태 칩 + 디자인형 드롭다운 (264px 카드, mint/basil/peppermint).
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
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)  // 의미는 아래 AX 값이 말한다 (#59-3).
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
            .focusedValue(\.hasMintEditor, true)
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
        .overlay(alignment: .bottom) { downloadFailureFooter }
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
        .accessibilityLabel(Text("자동완성"))
    }

    /// 모델 행 — **실제 Button**이라 Tab 포커스·Enter 활성화·VO 버튼 역할을 갖는다
    /// (#25). 다운로드 액세서리는 trailing overlay의 독립 Button으로 올려,
    /// 버튼 중첩 충돌 없이(overlay가 히트를 먼저 가져간다) 두 동작을 분리한다.
    /// 실패 원인은 AX value로 읽혀 색·help에만 의존하지 않는다.
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(choice.name) 모델"))
        .accessibilityValue(Text(selected ? "선택됨 · \(choice.latencyLabel)" : choice.latencyLabel))
        .accessibilityHint(Text("이 모델로 전환"))
        .overlay(alignment: .trailing) {
            downloadAccessory(choice)
                .padding(.trailing, 30)   // ✓ 칼럼 폭만큼 비켜난다
                .padding(.leading, 8)
        }
    }

    /// 다운로드 실패 원인 가시 푸터 (#25 완료 조건 3) — help 뒤에 숨기지 않는다.
    @ViewBuilder
    private var downloadFailureFooter: some View {
        let failure = downloads.states.first { state in
            if case .failed = state.value { return true }
            return false
        }
        if let failure {
            if case .failed(let message) = failure.value {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ModelChip.displayName(failure.key)) 다운로드 실패")
                        .font(MintFonts.uiFont(11, .semibold))
                        .foregroundStyle(theme.dangerC)
                    Text(Self.recoveryAdvice(for: message))
                        .font(MintFonts.uiFont(10.5))
                        .foregroundStyle(theme.ink2C)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.pillC)
            }
        }
    }

    /// 오류 메시지 → 다음 행동 제안 (#25). 결정적 매핑 — 네트워크/디스크/형식.
    static func recoveryAdvice(for message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("network") || lowered.contains("인터넷") || lowered.contains("연결") {
            return "네트워크 상태를 확인한 뒤 다시 시도해 주세요."
        }
        if lowered.contains("disk") || lowered.contains("space") || lowered.contains("공간")
            || lowered.contains("no space")
        {
            return "디스크 여유 공간을 확보한 뒤 다시 시도해 주세요."
        }
        if lowered.contains("404") || lowered.contains("not found") || lowered.contains("찾을 수 없") {
            return "저장소 id가 맞는지 확인해 주세요 (설정에서 직접 입력한 경우 오타 확인)."
        }
        return "잠시 후 다시 시도해 주세요."
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
                .accessibilityLabel(Text("다운로드 취소"))
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3C)
                .help("다운로드됨 — 전환 시 바로 로드")
                    .accessibilityLabel(Text("다운로드됨 — 이 모델로 전환"))
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
                    .accessibilityLabel(Text("모델 다운로드 실패 — 다시 시도"))
                    .accessibilityValue(Text(message))
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
                    .accessibilityLabel(Text("\(choice.name) 모델 미리 받기"))
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
        case .downloading, .loading: theme.warningC
        case .ready: completion.suggestion != nil ? theme.inkC : theme.ink3C
        case .failed: theme.dangerC
        }
    }

    /// 상태점의 의미를 텍스트로 — 색만 보고 판단하지 않게 (#59-3).
    fileprivate var engineStateAXValue: String {
        if !settings.autocompleteEnabled { return "자동완성 꺼짐" }
        switch completion.engineState {
        case .idle: return "대기"
        case .downloading(let fraction):
            return String(format: "다운로드 %.0f%%", fraction * 100)
        case .loading: return "모델 로드 중"
        case .ready: return completion.suggestion != nil ? "제안 준비됨" : "준비됨"
        case .failed: return "오류"
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
                .fill(theme.knobC)
                .frame(width: 21, height: 21)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .offset(x: isOn ? 19 : 2)
        }
        .frame(width: 42, height: 25)
        // Reduce Motion에선 즉시 전환 — 상태 변화 자체가 피드백이다 (#27).
        .modifier(ReduceMotionAnimation(animation: .spring(duration: 0.25), value: isOn))
    }
}

/// Reduce Motion을 존중하는 animation 수정자 헬퍼 (#27) — 설정이 켜져 있으면
/// 값 변화를 애니메이션 없이 즉시 반영한다. SwiftUI 크롬 전역에서 재사용.
struct ReduceMotionAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation?
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// "예측 중" 점 세 개 애니메이션 (디자인 mint-dot).
///
/// 모션 정책 (#27 감사): 무한 반복 모션이라 Reduce Motion에서는 **정적** 0.65로
/// 만든다 — 진행 표시의 의미는 밝기 하나로도 성립한다. 일반 모드도 450ms →
/// 250ms·점 간 80ms로 줄여 프레임 예산 밖으로 나가지 않게 했다.
struct PulsingDots: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(pulsing ? 1 : (reduceMotion ? 0.65 : 0.25))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.25)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: pulsing
                    )
            }
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - 마크다운 치트시트

/// 마크다운 단축 문법 안내 — 줄 맨 앞/인라인 문법을 한눈에.
/// 상단바 도움말 버튼이 사라진 뒤로는 설정(⌘,)의 "사용 방법"에서 보여준다.
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
        // 모션 없음 — Tab/→/Esc마다 도는 고빈도 경로다 (감사 표, #27).
        // 과거 200ms fade가 키 피드백을 늦췄다.
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
///
/// ⚠️ 통계는 **디바운스 + 백그라운드**로 센다 — 렌더마다 세면 키 입력마다
/// 문서 전체를 3번 훑어 88k자에서 ~18ms·300k에서 ~62ms가 매 타에 든다
/// (릴리즈 실측 — 대형 문서 타이핑 랙의 주범이었다, docs/editor-perf.md).
/// 값이 최대 ~0.3s 낡을 수 있지만 단어 수는 그래도 된다. 랙은 안 된다.
struct EditorStatusBar: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    @State private var stats = TextStats.empty

    var body: some View {
        HStack(spacing: 16) {
            if let notice = store.notice {
                Text(notice)
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.blueC)
                    .lineLimit(1)
                separator
            }
            Text("\(stats.words) 단어")
            separator
            Text("\(stats.characters) 자")
            if !stats.readingLabel.isEmpty {
                separator
                Text("읽기 \(stats.readingLabel)")
            }
            if case .failed = completion.engineState {
                separator
                Text("자동완성 로드 실패")
                    .foregroundStyle(theme.dangerC)
                    .lineLimit(1)
                Button("다시 시도") { completion.retryEngineLoad() }
                    .buttonStyle(.link)
                    .font(MintFonts.monoUI(11))
            }
            Spacer()
            // 입력 지연 계측 (로컬 전용 진단) — 핸들러(우리 코드) vs 총(렌더 포함).
            // 랙 제보를 숫자로 받기 위한 장비. 표본이 쌓여야 나타난다.
            if completion.keystrokeStats.samples > 0 {
                Text(keystrokeLabel)
                    .help("키 입력 처리 시간 — 핸들러(에디터 코드) / 총(화면 갱신 포함), p95·최대")
                separator
            }
            // 저장 상태 — 실패를 "저장됨"으로 위장하지 않는다 (이슈 #10).
            if case .failed(let message, _) = store.savePhase {
                Text("저장 실패")
                    .foregroundStyle(theme.dangerC)
                    .help("\(message)\n대상: \(store.saveTargetFileName)")
                Button("다시 시도") { store.retrySave() }
                    .buttonStyle(.link)
                    .font(MintFonts.monoUI(11))
            } else if store.pendingRecovery != nil {
                Text("복구 파일 기록 중 (\(store.saveTargetFileName))")
            } else if store.isSaveInFlight {
                Text("저장 중…")
            } else if case .saved = store.savePhase {
                Text("저장됨")
            }
            separator
            Text("Markdown")
        }
        .font(MintFonts.monoUI(11))
        .foregroundStyle(theme.ink3C)
        .padding(.horizontal, 22)
        .frame(height: 34)
        .background(theme.statusbarC)
        // 통계 재계산 — 키가 바뀌고(편집·문서 전환) 0.25s 조용해진 뒤에만.
        // 그 사이 새 키 입력이 오면 이 task가 취소되고 새로 걸린다(디바운스).
        // 계산은 detached — 88k자 한 패스가 메인 프레임을 막지 않는다.
        .task(id: statsKey) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let text = store.activeEntry?.body ?? ""
            stats = await Task.detached(priority: .utility) {
                TextStats.compute(text)
            }.value
            guard !Task.isCancelled else { return }  // stale 결과 할당 금지 (#60)
        }
    }

    /// 디바운스 키 — 본문 변경 카운터 + 활성 문서. 문자열 비교(O(n))가 아니라
    /// 카운터 비교(O(1))로 변경을 감지한다.
    private var statsKey: String {
        "\(store.activeID.uuidString)-\(store.bodyVersion)"
    }

    private var keystrokeLabel: String {
        let stats = completion.keystrokeStats
        return String(
            format: "입력 %.1f/%.0fms·max %.0f",
            stats.handlerP95, stats.totalP95, stats.totalMax)
    }

    private var separator: some View {
        theme.sepC.frame(width: 1, height: 12)
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
                            .foregroundStyle(theme.novelC.accessibleForegroundC)
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

// MARK: - 첫 실행 모델 선택 (이슈 #40)

/// 첫 실행 모델 선택 시트 — 기본 모델(Basil, 16.9GB)이 조용히 내려받히기 **전에**
/// 사용자가 라인업의 크기·성격을 보고 고르게 한다 (#65 Phase 4 결정안 2).
/// 선택은 `CompletionSettings.modelID`에 저장되고, 확인과 함께 시작 preload가
/// 풀린다. "나중에"는 기본값(Basil)을 유지하되 자동 다운로드만 미룬다.
struct InitialModelPicker: View {
    @ObservedObject var settings: CompletionSettings
    /// 확인 후 호출 — 시작 preload를 이어간다 (ContentView 배선).
    var onConfirmed: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .foregroundStyle(MintTheme.of(.light).novelC)
                Text("AI 모델을 고르세요")
                    .font(MintFonts.uiFont(15, .semibold))
            }
            Text(
                "제안 엔진은 기기 안에서만 도니다. 모델 파일(최대 17GB)을 한 번 "
                    + "내려받으면 네트워크 없이 동작해요. 나중에 설정(⌘,)에서 바꿀 수 있어요."
            )
            .font(MintFonts.uiFont(12))
            .foregroundStyle(MintTheme.of(.light).ink2C)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(ModelChoice.all) { choice in
                Button {
                    settings.modelID = choice.id
                    confirm()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: settings.modelID == choice.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.modelID == choice.id ? MintTheme.of(.light).novelC : MintTheme.of(.light).ink3C)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(choice.name)
                                    .font(MintFonts.uiFont(13, .semibold))
                                Text(choice.sizeLabel + " · " + downloadSize(choice.id))
                                    .font(MintFonts.monoUI(10))
                                    .foregroundStyle(MintTheme.of(.light).ink3C)
                            }
                            Text(choice.detail)
                                .font(MintFonts.uiFont(11))
                                .foregroundStyle(MintTheme.of(.light).ink2C)
                        }
                        Spacer()
                        Text(choice.latencyLabel)
                            .font(MintFonts.uiFont(10))
                            .foregroundStyle(MintTheme.of(.light).ink3C)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(MintTheme.of(.light).chipC))
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Spacer()
                Button("나중에 결정") { confirm() }
                    .buttonStyle(.bordered)
                    .help("기본 모델(Basil)이 유지되지만 지금은 내려받지 않아요")
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func confirm() {
        settings.initialModelConfirmed = true
        dismiss()
        onConfirmed()
    }

    /// 라인업 다운로드 크기 표기 — 프리셋 id 기준 대략치.
    private func downloadSize(_ id: String) -> String {
        switch id {
        case ModelPresets.ternaryBonsai27B: "8.5GB"
        case ModelPresets.glm4_7_flash: "16.9GB"
        case ModelPresets.qwen3_6_35B_A3B: "~20GB"
        default: "수 GB"
        }
    }
}
