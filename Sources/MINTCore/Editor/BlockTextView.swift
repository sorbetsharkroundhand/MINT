import AppKit
import SwiftMath
import SwiftUI
import UniformTypeIdentifiers

/// Notion식 블록 에디터 (에디터 v3 — 디자인 완전 이식).
///
/// 웹 목업의 세 축을 NSTextView(TextKit 1)로 옮긴 것:
/// - `transformMarkdown` → 마커(`# `, `> `, `- ` …)를 입력 즉시 **소비**하고
///   문단에 블록 속성(`.mintBlock`)을 부여한다. 화면에 마커는 남지 않는다.
/// - `serialize`/`buildDOM` → 저장은 항상 순수 마크다운. 로드 시 마커를 파싱해
///   블록으로 복원한다. 파일 포맷은 이전과 완전 호환.
/// - 블록 장식(불릿·번호·체크박스·인용 바·코드/수식 배경·구분선·이미지)은
///   `MintLayoutManager`가 그린다 — text storage 밖이라 undo·IME에 무해.
/// - 커서 효과(펄스 blink·이동 리플·커서 줄 하이라이트)는 뷰의 `draw`/
///   `drawInsertionPoint`에서 그린다 (에디터 v3.1 — 창 글로우 대체).
///
/// 에디터 본문의 가독 폭 상수 — 창을 넓혀도 한 줄이 끝없이 길어지지 않게
/// 편안한 폭으로 묶고 남는 폭은 좌우 여백으로 돌린다(글이 가운데 컬럼에 놓인다).
/// iA Writer·Ulysses·Bear가 프리미엄으로 느껴지는 핵심 — 긴 줄은 눈이 다음 줄을
/// 찾기 어려워 장시간 읽기를 피로하게 한다.
public enum EditorMetrics {
    /// 본문 최대 폭(pt) — 한글 약 38자·라틴 약 70자 수준의 차분한 measure.
    public static let maxContentWidth: CGFloat = 760
    /// 좁은 창에서의 기본 좌우 여백(pt) — 디자인 padding.
    public static let minSideInset: CGFloat = 56

    /// 뷰 폭에 맞는 좌우 inset — 폭이 넓어지면 여백을 키워 본문을 가운데로 모은다.
    public static func sideInset(forWidth width: CGFloat) -> CGFloat {
        max(minSideInset, ((width - maxContentWidth) / 2).rounded())
    }
}

/// 고스트 텍스트(M3)는 기존 방식 그대로: storage 밖에서 `draw(_:)`로만 그린다.
public struct MintBlockEditor: NSViewRepresentable {
    @Binding var text: String

    private let controller: CompletionController?
    private let theme: MintTheme
    /// 본문 줄 간격(pt) — 설정에서 조절. 낮추면 줄이 촘촘해진다.
    private let lineSpacing: CGFloat
    /// 에디터 포커스 요청 카운터(EntryStore.editorFocusRequests) — 값이 바뀌면
    /// 텍스트 뷰를 first responder로 만든다 (새 저널 → 바로 타이핑).
    private let focusRequest: Int

    public init(
        text: Binding<String>,
        controller: CompletionController? = nil,
        theme: MintTheme = .light,
        lineSpacing: CGFloat = CGFloat(CompletionSettings.defaultLineSpacing),
        focusRequest: Int = 0
    ) {
        self._text = text
        self.controller = controller
        self.theme = theme
        self.lineSpacing = lineSpacing
        self.focusRequest = focusRequest
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 스택을 직접 조립 — 커스텀 레이아웃 매니저(블록 장식)를 쓰기 위해.
        let storage = NSTextStorage()
        let layoutManager = MintLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = BlockTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        // 디자인: padding 46px 60px — inset은 좌우 동일 적용이라 56으로 근사.
        textView.textContainerInset = NSSize(width: 56, height: 44)
        // 커서는 잉크색(라이트=검정/다크=하양) — 높이는 커서 위치의 글자 크기를 따른다.
        textView.insertionPointColor = theme.ink
        // ⌘F 문서 내 검색 — 스크롤 뷰 상단의 표준 find bar.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // 이미지 파일 드롭 수락 — NSTextView 기본 타입에 이미지 타입을 더한다.
        textView.registerForDraggedTypes(
            textView.registeredDraggedTypes + [.fileURL, .png, .tiff])

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.palette = theme
        textView.lineSpacing = lineSpacing
        textView.load(markdown: text)
        context.coordinator.lastSyncedText = text
        // 최초 값은 소비된 것으로 간주 — 실제 포커스는 뷰가 창에 붙을 때(launch) 준다.
        context.coordinator.lastFocusRequest = focusRequest

        let scrollView = WritingScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        // 타자기 존을 직접 관리하므로 안전영역 기반 자동 인셋은 끈다 — 이 스크롤 뷰는
        // 타이틀바 밑이 아니라 툴바·상태 바 사이에 있어 자동 상단 인셋은 어차피 0이다.
        scrollView.automaticallyAdjustsContentInsets = false

        context.coordinator.attach(to: textView)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? BlockTextView else { return }

        if textView.palette.ink != theme.ink {
            textView.palette = theme
            textView.insertionPointColor = theme.ink
            textView.restyleAll()
        }
        // 줄 간격 설정이 바뀌면 전체 문단 스타일을 다시 적용한다.
        if textView.lineSpacing != lineSpacing {
            textView.lineSpacing = lineSpacing
            textView.restyleAll()
        }
        // 외부(저널 전환·로드)에서 본문이 바뀐 경우에만 다시 파싱한다.
        // serialize() 재비교가 아니라 "마지막 동기화 텍스트"와 비교한다 —
        // 직렬화 왕복의 미세한 비대칭이 렌더 → reload → publish → 렌더의
        // 무한 루프(비치볼)로 번지는 것을 차단 (r1 버그).
        if text != context.coordinator.lastSyncedText {
            textView.load(markdown: text)
            context.coordinator.lastSyncedText = text
            textView.ghostText = nil
            controller?.dismissSuggestion()
        }
        // 새 저널 등 포커스 요청 — reload 뒤에 first responder로 만든다.
        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MintBlockEditor
        /// 마지막으로 바인딩과 동기화된 마크다운 — updateNSView의 reload 기준.
        var lastSyncedText = ""
        /// 마지막으로 처리한 포커스 요청 값 — 값이 바뀔 때만 포커스를 옮긴다.
        var lastFocusRequest = 0

        init(_ parent: MintBlockEditor) {
            self.parent = parent
        }

        func attach(to textView: BlockTextView) {
            parent.controller?.suggestionDidChange = { [weak textView] suggestion in
                textView?.ghostText = suggestion
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? BlockTextView else { return }
            let serialized = textView.serialize()
            lastSyncedText = serialized
            parent.text = serialized
            forwardEditEvent(textView)
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? BlockTextView else { return }
            textView.syncTypingAttributes()
            // 커서가 선택된 이미지 밖으로 나가면 객체 선택을 푼다 (렌더 유지 조건 갱신 전에).
            textView.syncImageSelection()
            // 커서 줄 하이라이트를 새 커서 위치로 옮긴다 (이전 줄 무효화 포함).
            textView.refreshActiveLineHighlight()
            // 커서가 수식 문단에 들어오면 소스, 나가면 렌더로 전환.
            textView.refreshRenderedBlocks()
            // 드래그 선택 위 서식 툴바 표시/숨김.
            textView.updateSelectionToolbar()
            guard let controller = parent.controller else { return }
            let range = textView.selectedRange()
            if range.length > 0 {
                controller.dismissSuggestion()
            } else {
                controller.noteSelectionChange(caretLocation: range.location)
            }
        }

        public func textDidEndEditing(_ notification: Notification) {
            parent.controller?.dismissSuggestion()
        }

        /// Tab 수락 / → 한 단어 / Esc 거부 (PLAN §5, 에디터 v3).
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let controller = parent.controller else { return false }

            if commandSelector == #selector(NSStandardKeyBindingResponding.insertTab(_:)) {
                guard let accepted = controller.acceptSuggestion() else { return false }
                textView.insertText(accepted, replacementRange: textView.selectedRange())
                return true
            }

            if commandSelector == #selector(NSStandardKeyBindingResponding.moveRight(_:)) {
                let range = textView.selectedRange()
                guard range.length == 0,
                    let word = controller.acceptWord(insertionLocation: range.location)
                else { return false }
                textView.insertText(word, replacementRange: range)
                return true
            }

            if commandSelector == #selector(NSStandardKeyBindingResponding.cancelOperation(_:))
                || commandSelector == #selector(NSStandardKeyBindingResponding.complete(_:)) {
                guard controller.hasSuggestion else { return false }
                controller.dismissSuggestion()
                return true
            }

            return false
        }

        // MARK: 컨트롤러 이벤트 전달

        private func forwardEditEvent(_ textView: BlockTextView) {
            guard let controller = parent.controller else { return }
            let storage = textView.string as NSString
            let caret = textView.selectedRange().location
            guard caret != NSNotFound, caret <= storage.length else { return }

            // 코드·수식·구분선 블록에서는 제안하지 않는다 (디자인 v3 게이트).
            let paragraph = storage.paragraphRange(for: NSRange(location: caret, length: 0))
            let block = textView.blockInfo(in: paragraph).block
            let allowed = ![.code, .math, .divider, .image].contains(block)

            controller.noteEdit(
                prefix: Self.prefix(
                    of: storage, before: caret, limit: controller.settings.contextCharacters),
                caretLocation: caret,
                isComposing: textView.hasMarkedText(),
                caretAtParagraphEnd: allowed && Self.isCaretAtParagraphEnd(storage, caret: caret)
            )
        }

        private static func prefix(of storage: NSString, before caret: Int, limit: Int) -> String {
            String(storage.substring(to: caret).suffix(limit))
        }

        private static func isCaretAtParagraphEnd(_ storage: NSString, caret: Int) -> Bool {
            let paragraph = storage.paragraphRange(for: NSRange(location: caret, length: 0))
            guard paragraph.upperBound > caret else { return true }
            let tail = storage.substring(
                with: NSRange(location: caret, length: paragraph.upperBound - caret))
            return tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - 타자기 존 스크롤 뷰

/// 마지막으로 쓰는 줄이 창 바닥(상태 바 바로 위)에 붙지 않고, 화면 중하단의
/// 편안한 위치에 머물게 하는 스크롤 뷰.
///
/// 왜: 기본 NSTextView는 타이핑 중 커서가 보이도록 뷰 하단(=textContainerInset
/// 44pt)까지만 스크롤한다. 그래서 글이 한 화면을 넘기면 그 뒤로는 줄곧 커서가
/// **바닥을 긁으며** 써지고, 이는 답답함 → "그만 쓰고 싶다"로 이어진다.
/// 아래쪽에 뷰 높이의 일부만큼 스크롤 여백(contentInsets.bottom)을 두면,
/// `BlockTextView.scrollRangeToVisible`가 이 여백만큼 커서 아래를 함께 드러내
/// 활성 줄이 대략 화면 75% 지점에 park하게 한다 — iA Writer·Ulysses의 차분한
/// 글쓰기 존과 같은 감각. 한 화면 안에 드는 짧은 글엔 스크롤이 없어 영향이 없다.
final class WritingScrollView: NSScrollView {
    /// 활성 줄이 park할 지점을 남기기 위해 뷰 높이에 곱하는 하단 여백 비율.
    /// 0.25 → 커서가 바닥(≈93%)이 아니라 화면 75% 지점에 머문다(약 4~5줄 여유).
    private let gutterFraction: CGFloat = 0.25

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // 높이에 비례해 여백을 갱신 — 작은 창에선 작게, 큰 창에선 크게.
        let gutter = (newSize.height * gutterFraction).rounded()
        guard abs(contentInsets.bottom - gutter) > 0.5 else { return }
        contentInsets = NSEdgeInsets(top: contentInsets.top, left: 0, bottom: gutter, right: 0)
    }
}

// MARK: - 블록 모델

/// 문단 블록 타입 (디자인의 data-md와 1:1).
enum MintBlock: String {
    case p, h1, h2, h3, quote, bullet, number, todo, code, math, divider, image
}

/// 이미지 소스 한 줄(`![](src){width=NN align=X}`)에서 파싱한 표시 속성.
/// 마크다운 왕복은 소스 문자열 그대로라 별도 저장 없이 `markdown`으로 되돌린다.
struct ImageAttrs: Equatable {
    var src: String
    /// 컬럼 폭 대비 표시 너비(%). 기본 100(=폭에 맞춤).
    var width: Int = 100
    /// 가로 정렬 — "left" / "center"(기본) / "right".
    var align: String = "center"

    /// 소스 마크다운으로 직렬화 — 기본값(100%·center)이면 접미 `{...}`를 생략한다.
    var markdown: String {
        var opts: [String] = []
        if width != 100 { opts.append("width=\(width)") }
        if align != "center" { opts.append("align=\(align)") }
        let suffix = opts.isEmpty ? "" : "{\(opts.joined(separator: " "))}"
        return "![](\(src))\(suffix)"
    }
}

/// 렌더 모드 이미지 문단 하나 — 레이아웃 매니저 드로잉이 읽는 값 스냅샷.
struct ImageRender {
    let range: NSRange
    let image: NSImage
    /// 실제 그려질 크기(폭 % 반영 후).
    let size: NSSize
    let align: String
    /// 객체 선택 상태 — true면 선택 테두리를 그린다.
    let selected: Bool
}

extension NSAttributedString.Key {
    /// 문단의 블록 타입 (MintBlock rawValue).
    static let mintBlock = NSAttributedString.Key("mint.block")
    /// todo 체크 여부 (Bool).
    static let mintChecked = NSAttributedString.Key("mint.checked")
    /// number 블록의 마커 문자열 ("1." 등).
    static let mintMarker = NSAttributedString.Key("mint.marker")
}

// MARK: - 텍스트 뷰

/// 블록 변환·직렬화·고스트 렌더를 담당하는 NSTextView.
final class BlockTextView: NSTextView {

    /// 레이아웃 매니저(nonisolated 드로잉)에서도 읽는다 — 쓰기는 메인 스레드뿐.
    nonisolated(unsafe) var palette: MintTheme = .light

    /// 문서 끝 빈 문단(typingAttributes에만 존재)의 블록 스냅샷 —
    /// 레이아웃 매니저가 nonisolated 드로잉 중에 읽는다.
    nonisolated(unsafe) private(set) var tailBlockInfo:
        (block: String?, checked: Bool, marker: String?) = (nil, false, nil)

    /// typingAttributes 변경 후 호출해 스냅샷을 갱신한다.
    private func updateTailSnapshot() {
        tailBlockInfo = (
            typingAttributes[.mintBlock] as? String,
            typingAttributes[.mintChecked] as? Bool ?? false,
            typingAttributes[.mintMarker] as? String
        )
    }

    /// 본문 기본 폰트 — 디자인: Noto Serif KR 20px.
    let bodyFont = MintFonts.serif(20)

    /// 본문 줄 간격(pt) — 설정에서 주입. `lineHeightMultiple` 대신 `lineSpacing`을
    /// 쓰는 이유: 배수는 여백을 라인 위쪽에 몰아 글자가 커서 아래쪽에 붙지만,
    /// lineSpacing은 자연 줄 높이를 유지해 글자·커서 높이가 일치한다 (요구 1·4).
    var lineSpacing: CGFloat = CGFloat(CompletionSettings.defaultLineSpacing)

    /// 고스트 페이드 인 진행도(0…1) — 없던 제안이 새로 뜰 때만 0에서 1로 올린다.
    /// AI 제안이 커서 옆에 "쿵" 나타나 시선을 때리지 않고 부드럽게 스며들게 하려는 것.
    /// 한 단어(→) 수락으로 제안이 짧아질 때는 1을 유지해 다시 깜빡이지 않는다.
    private var ghostOpacity: CGFloat = 1
    /// 페이드 인 애니메이션 태스크 — 새 제안·폐기 때 취소하고 다시 건다.
    private var ghostFadeTask: Task<Void, Never>?

    /// 현재 고스트 텍스트. nil/빈 문자열이면 그리지 않는다.
    var ghostText: String? {
        didSet {
            guard ghostText != oldValue else { return }
            // 없던 자리에 제안이 새로 뜰 때만 페이드 인 — 짧아짐·사라짐은 즉시 반영.
            if let ghost = ghostText, !ghost.isEmpty, oldValue == nil {
                startGhostFadeIn()
            } else if ghostText == nil {
                ghostFadeTask?.cancel()
                ghostFadeTask = nil
                ghostOpacity = 1
            }
            needsDisplay = true
        }
    }

    /// 마커 소비/스타일 적용 중 재진입 방지.
    private var isTransforming = false

    /// 수식 렌더 폰트 크기 — 본문(serif 20)과 맞춘다.
    let mathFontSize: CGFloat = 20

    /// 현재 렌더 모드인 수식 문단들 (문단 range + 렌더된 LaTeX 이미지).
    /// `refreshRenderedBlocks()`이 갱신하고 레이아웃 매니저가 그린다.
    nonisolated(unsafe) private(set) var mathRenders: [(range: NSRange, image: NSImage)] = []

    /// 현재 렌더 모드인 이미지 문단들 — 문단 range·이미지·표시 크기·정렬·선택 여부.
    /// 정렬/크기는 소스(`![](src){width=NN align=X}`)에서 파싱해 담고, 레이아웃
    /// 매니저의 `drawImage`가 그대로 쓴다 (요구 3).
    nonisolated(unsafe) private(set) var imageRenders: [ImageRender] = []

    /// 객체로 선택된 이미지 문단의 시작 위치 — 클릭하면 소스(![](…)) 대신 이미지가
    /// 선택 테두리와 함께 남고, 정렬·줄바꿈 툴바가 뜬다 (요구 3).
    var selectedImageLocation: Int?

    /// 드래그 중 미리보기 너비(%) — refreshRenderedBlocks가 소스 대신 이 값을 쓴다.
    private var resizePreview: (loc: Int, width: Int)?
    /// 선택된 이미지를 감싸는 오버레이 박스 (요구: 이미지를 하나의 박스로).
    private var imageBox: ImageBoxOverlay?
    /// 이미지 이동 드래그 중 표시할 드롭 위치 y (뷰 좌표). nil이면 표시 안 함.
    var imageDropIndicatorY: CGFloat?

    // MARK: 커서 효과 (에디터 v3.1 — 글로우 대체)

    /// 마지막으로 그린 커서 줄 하이라이트 rect — 이동 시 이전 줄 무효화용.
    private var lastActiveLineRect: NSRect?

    /// 커서 줄 하이라이트를 다시 그린다 — 이전 줄과 새 줄만 무효화.
    func refreshActiveLineHighlight() {
        if let old = lastActiveLineRect { setNeedsDisplay(old) }
        if let new = activeLineRect() { setNeedsDisplay(new) }
    }

    /// 커서 줄 하이라이트 rect (뷰 좌표). 포커스 밖이면 nil.
    ///
    /// 밴드는 **글자 em 박스(ascender~descender)에 아주 작은 상하 마진**만 더한
    /// 높이로, em 박스 중심에 맞춰 그린다 — 글자가 정확히 중앙에 오고(요구 3),
    /// 위·아래 여백이 같아진다. 또 밴드 높이를 라인 advance(=글자 높이+줄 간격)로
    /// 상한 걸어, 줄 간격을 좁혀도 밴드가 옆 줄 글자를 침범하지 않는다.
    private func activeLineRect() -> NSRect? {
        guard let window, window.firstResponder === self,
            selectedRange().length == 0,
            selectedImageLocation == nil,  // 이미지 객체 선택 중엔 줄 하이라이트 없음
            let textContainer, let cr = caretRectInView()
        else { return nil }
        // 캐럿과 **같은 기준**(시스템 캐럿 rect + 폰트 메트릭)에서 만든다.
        // 시스템 캐럿 rect.top = ascender 라인 → baseline = top + ascender.
        // 하이라이트는 글자(ascender~descender)를 감싸도록, 위아래 작은 여백만 준다.
        let font = caretLineFont()
        let baseline = cr.minY + font.ascender
        let vpad: CGFloat = 2
        let top = baseline - font.ascender - vpad
        let bottom = baseline - font.descender + vpad  // descender 음수 → 아래로
        let x = textContainerOrigin.x + textContainer.lineFragmentPadding - 8
        let w = textContainer.size.width - textContainer.lineFragmentPadding * 2 + 16
        return NSRect(x: x, y: top, width: w, height: bottom - top)
    }

    /// 창에 처음 붙을 때 한 번만 자동 포커스 — 앱을 켜면 곧바로 쓸 수 있게.
    private var didInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didInitialFocus, window != nil else { return }
        didInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            DispatchQueue.main.async { [weak self] in
                // 포커스가 돌아오면 커서 문단의 수식을 소스 모드로 되돌린다.
                self?.refreshRenderedBlocks()
                self?.refreshActiveLineHighlight()
            }
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            // 포커스를 잃으면 커서가 수식 문단에 남아 있어도 렌더로 전환하고,
            // 커서 줄 하이라이트도 지운다.
            DispatchQueue.main.async { [weak self] in
                self?.refreshRenderedBlocks()
                self?.refreshActiveLineHighlight()
            }
        }
        return ok
    }

    // MARK: 마크다운 ↔ 블록 변환

    /// 마크다운을 파싱해 storage를 블록 문서로 채운다 (buildDOM).
    func load(markdown: String) {
        guard let storage = textStorage else { return }
        isTransforming = true
        let result = NSMutableAttributedString()
        var inCode = false
        let lines = markdown.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            var line = rawLine
            if line.trimmingCharacters(in: .whitespaces) == "```" {
                inCode.toggle()
                continue
            }
            var block = MintBlock.p
            var checked = false
            var marker: String?
            // 정렬 래퍼(<p align="…">…</p>)는 블록 판정 전에 벗긴다.
            var align: String?
            if !inCode {
                let full = NSRange(location: 0, length: (line as NSString).length)
                if let match = Self.alignWrapper.firstMatch(in: line, range: full) {
                    align = (line as NSString).substring(with: match.range(at: 1))
                    line = (line as NSString).substring(with: match.range(at: 2))
                }
            }
            if inCode {
                block = .code
            } else if line.hasPrefix("### ") {
                block = .h3; line = String(line.dropFirst(4))
            } else if line.hasPrefix("## ") {
                block = .h2; line = String(line.dropFirst(3))
            } else if line.hasPrefix("# ") {
                block = .h1; line = String(line.dropFirst(2))
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                block = .todo; checked = line.hasPrefix("- [x] ")
                line = String(line.dropFirst(6))
            } else if line.hasPrefix("> ") || line == ">" {
                block = .quote; line = String(line.dropFirst(min(2, line.count)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                block = .bullet; line = String(line.dropFirst(2))
            } else if let match = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
                block = .number
                marker = String(line[line.startIndex..<match.upperBound])
                    .trimmingCharacters(in: .whitespaces)
                line = String(line[match.upperBound...])
            } else if line.range(of: #"^---+\s*$"#, options: .regularExpression) != nil {
                block = .divider; line = ""
            } else if line.hasPrefix("$$"), line.hasSuffix("$$"), line.count >= 4 {
                block = .math; line = String(line.dropFirst(2).dropLast(2))
            } else if line.range(
                of: #"^!\[[^\]]*\]\([^)\s]+\)(?:\{[^}]*\})?$"#,
                options: .regularExpression) != nil {
                // 한 줄 전체가 이미지 마크다운 — 원문(![](src){…})을 소스로 보관하고
                // 커서가 밖이면 렌더 이미지로 덮어 그린다 (수식과 같은 방식).
                block = .image
            }
            var attrs = styleAttributes(for: block, checked: checked)
            attrs[.mintBlock] = block.rawValue
            if checked { attrs[.mintChecked] = true }
            if let marker { attrs[.mintMarker] = marker }
            if let align {
                attrs[.mintAlign] = align
                if let ps = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
                    as? NSMutableParagraphStyle {
                    ps.alignment = align == "right" ? .right : .center
                    attrs[.paragraphStyle] = ps
                }
            }
            let suffix = index < lines.count - 1 ? "\n" : ""
            switch block {
            case .code, .math, .divider, .image:
                // 코드·수식·이미지엔 인라인 서식이 없다 — 원문 그대로.
                result.append(NSAttributedString(string: line + suffix, attributes: attrs))
            default:
                for segment in InlineMarkdown.parse(line) {
                    var merged = attrs
                    for (key, value) in segment.attrs { merged[key] = value }
                    result.append(NSAttributedString(string: segment.text, attributes: merged))
                }
                result.append(NSAttributedString(string: suffix, attributes: attrs))
            }
        }
        storage.setAttributedString(result)
        decorateInline(in: NSRange(location: 0, length: storage.length))
        // 저널을 열면 맨 위·처음에 커서를 둔다 — 예전엔 문서 끝에 놓여, 뷰포트는
        // 위인데 커서는 아래라 첫 키 입력이 바닥으로 순간이동하는 혼란이 있었다.
        setSelectedRange(NSRange(location: 0, length: 0))
        // 뷰포트도 맨 위로 — 긴 저널을 열면 처음부터 보이게.
        scrollToBeginningOfDocument(nil)
        syncTypingAttributes()
        isTransforming = false
        selectedImageLocation = nil
        hideImageToolbar()
        hideSelectionToolbar()
        // 커서가 어느 문단에 있든(수식·이미지 포함) 로드 직후엔 전부 렌더로 강제한다 —
        // 소스가 잠깐 보였다 사라지지 않게. 사용자가 커서를 움직이면 평소 규칙으로 복귀.
        refreshRenderedBlocks(forceRender: true)
        needsDisplay = true
    }

    /// `<p align="center|right">…</p>` — 정렬 저장 래퍼 (.p 문단 전용).
    private static let alignWrapper = try! NSRegularExpression(
        pattern: #"^<p align="(center|right)">(.*)</p>$"#)

    /// storage를 순수 마크다운으로 되돌린다 (serialize).
    func serialize() -> String {
        let ns = string as NSString
        var out: [String] = []
        var inCode = false
        var location = 0
        repeat {
            let para = ns.paragraphRange(for: NSRange(location: location, length: 0))
            // 직렬화는 storage 속성만 신뢰한다 — typingAttributes 폴백을 쓰면
            // "빈 문서 + 블록 typingAttributes" 상태에서 저장 텍스트가 실제
            // 내용과 어긋나 reload 루프를 만든다 (r1 버그).
            let info = storageBlockInfo(in: para)
            let text = serializedContent(of: para, block: info.block)
            switch info.block {
            case .code:
                if !inCode { out.append("```"); inCode = true }
                out.append(text)
            default:
                if inCode { out.append("```"); inCode = false }
                switch info.block {
                case .h1: out.append("# " + text)
                case .h2: out.append("## " + text)
                case .h3: out.append("### " + text)
                case .quote: out.append("> " + text)
                case .bullet: out.append("- " + text)
                case .number: out.append((info.marker ?? "1.") + " " + text)
                case .todo: out.append("- [" + (info.checked ? "x" : " ") + "] " + text)
                case .math: out.append("$$" + text + "$$")
                case .divider: out.append("---")
                case .image: out.append(text)  // text = 원문 ![](src)
                default:
                    if let align = alignValue(at: para) {
                        out.append("<p align=\"\(align)\">\(text)</p>")
                    } else {
                        out.append(text)
                    }
                }
            }
            location = para.upperBound
        } while location < ns.length
        // 문서가 개행으로 끝나면 마지막 빈 문단도 한 줄이다.
        if ns.length > 0, ns.character(at: ns.length - 1) == 0x0A {
            if inCode { out.append("```"); inCode = false }
            out.append("")
        }
        if inCode { out.append("```") }
        return out.joined(separator: "\n")
    }

    /// storage 속성만으로 읽는 블록 정보 — 직렬화 전용 (문자 없는 문단은 항상 p).
    private func storageBlockInfo(in paragraph: NSRange)
        -> (block: MintBlock, checked: Bool, marker: String?)
    {
        guard let storage = textStorage, paragraph.location < storage.length else {
            return (.p, false, nil)
        }
        let attrs = storage.attributes(at: paragraph.location, effectiveRange: nil)
        let block = (attrs[.mintBlock] as? String).flatMap(MintBlock.init(rawValue:)) ?? .p
        return (block, attrs[.mintChecked] as? Bool ?? false, attrs[.mintMarker] as? String)
    }

    /// 문단의 블록 정보. 빈 마지막 문단은 typingAttributes에서 읽는다 (편집 규칙용).
    func blockInfo(in paragraph: NSRange) -> (block: MintBlock, checked: Bool, marker: String?) {
        let attrs: [NSAttributedString.Key: Any]
        if let storage = textStorage, paragraph.location < storage.length {
            attrs = storage.attributes(at: paragraph.location, effectiveRange: nil)
        } else {
            attrs = typingAttributes
        }
        let block = (attrs[.mintBlock] as? String).flatMap(MintBlock.init(rawValue:)) ?? .p
        return (block, attrs[.mintChecked] as? Bool ?? false, attrs[.mintMarker] as? String)
    }

    private func paragraphContent(_ paragraph: NSRange) -> String {
        let ns = string as NSString
        var text = ns.substring(with: paragraph)
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    /// 문단 내용 직렬화 — 코드·수식·구분선은 원문 그대로, 나머지는 인라인
    /// 서식을 마크다운 마커로 복원한다.
    private func serializedContent(of paragraph: NSRange, block: MintBlock) -> String {
        let plain = paragraphContent(paragraph)
        guard let storage = textStorage,
            ![MintBlock.code, .math, .divider, .image].contains(block)
        else { return plain }
        let contentRange = NSRange(
            location: paragraph.location, length: (plain as NSString).length)
        return InlineMarkdown.serialize(storage, in: contentRange)
    }

    /// 문단의 저장된 정렬 값 ("center"/"right") — 직렬화용.
    private func alignValue(at paragraph: NSRange) -> String? {
        guard let storage = textStorage, paragraph.location < storage.length else { return nil }
        return storage.attribute(.mintAlign, at: paragraph.location, effectiveRange: nil)
            as? String
    }

    /// 커서 문단에 블록을 부여하고 스타일을 다시 입힌다 (undo 등록 포함).
    func applyBlock(
        _ block: MintBlock, checked: Bool = false, marker: String? = nil,
        to paragraph: NSRange, registerUndo: Bool = true
    ) {
        guard let storage = textStorage else { return }
        let wasTransforming = isTransforming
        isTransforming = true
        var attrs = styleAttributes(for: block, checked: checked)
        attrs[.mintBlock] = block.rawValue
        if checked { attrs[.mintChecked] = true }
        if let marker { attrs[.mintMarker] = marker }
        if paragraph.length > 0 {
            if registerUndo {
                _ = shouldChangeText(in: paragraph, replacementString: nil)
            }
            // setAttributes는 인라인 서식 키까지 지운다 — 코드·수식·구분선·이미지가
            // 아니면 보존했다가 되살린 뒤 폰트·색을 다시 조립한다.
            let keepInline = ![MintBlock.code, .math, .divider, .image].contains(block)
            let preserved = keepInline ? inlineSnapshot(in: paragraph) : []
            storage.setAttributes(attrs, range: paragraph)
            for (range, inline) in preserved {
                storage.addAttributes(inline, range: range)
            }
            decorateInline(in: paragraph)
            applyStoredAlignment(base: attrs, in: paragraph)
            applyStoredLineSpacing(in: paragraph)
            if registerUndo { didChangeText() }
        }
        // 커서가 이 문단 안에 있을 때만 typingAttributes를 덮는다.
        let caret = selectedRange().location
        if caret >= paragraph.location, caret <= paragraph.upperBound {
            typingAttributes = attrs
            updateTailSnapshot()
        }
        isTransforming = wasTransforming
        needsDisplay = true
    }

    /// 팔레트/테마 변경 시 문서 전체를 다시 입힌다.
    func restyleAll() {
        let ns = string as NSString
        var location = 0
        while location < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let info = blockInfo(in: para)
            applyBlock(
                info.block, checked: info.checked, marker: info.marker,
                to: para, registerUndo: false)
            location = para.upperBound
        }
        syncTypingAttributes()
        // 테마가 바뀌면 잉크 색으로 수식을 다시 렌더한다.
        refreshRenderedBlocks()
        needsDisplay = true
    }

    /// 커서 문단의 속성을 typingAttributes로 동기화 — 빈 문단에서도 블록 유지.
    func syncTypingAttributes() {
        guard let storage = textStorage else { return }
        let caret = selectedRange().location
        guard caret != NSNotFound else { return }
        let ns = string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(caret, ns.length), length: 0))
        if para.location < storage.length {
            // 굵게 같은 인라인 서식이 커서 앞 글자에서 이어지도록 caret-1 기준 —
            // 블록 속성은 문단 안에서 균일해 어디를 읽어도 같다.
            let anchor = min(
                max(para.location, min(caret, ns.length) - 1), storage.length - 1)
            typingAttributes = storage.attributes(at: anchor, effectiveRange: nil)
        }
        updateTailSnapshot()
    }

    // MARK: 인라인 서식 (굵게·기울임·코드·색·정렬)

    /// mint 인라인 키 런 스냅샷 — setAttributes로 지워지기 전에 보관한다.
    private func inlineSnapshot(
        in range: NSRange
    ) -> [(NSRange, [NSAttributedString.Key: Any])] {
        guard let storage = textStorage, range.length > 0 else { return [] }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            let kept = attrs.filter { InlineMarkdown.inlineKeys.contains($0.key) }
            if !kept.isEmpty { runs.append((run, kept)) }
        }
        return runs
    }

    /// mint 인라인 키를 읽어 폰트·색을 조립한다 — 항상 블록 기본 폰트 위에서
    /// 호출돼야 한다 (setAttributes 직후 / 로드 직후).
    func decorateInline(in range: NSRange) {
        guard let storage = textStorage, range.length > 0 else { return }
        storage.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            var addition: [NSAttributedString.Key: Any] = [:]
            var base = attrs[.font] as? NSFont ?? bodyFont
            // 크기 조절은 블록 기본 폰트를 리사이즈한 것 위에 굵게·기울임을 쌓는다.
            if let size = attrs[.mintFontSize] as? Double,
                abs(base.pointSize - CGFloat(size)) > 0.1 {
                base = NSFontManager.shared.convert(base, toSize: CGFloat(size))
                addition[.font] = base
            }
            if attrs[.mintCode] as? Bool == true {
                addition[.font] = NSFont.monospacedSystemFont(
                    ofSize: base.pointSize * 0.78, weight: .regular)
                addition[.backgroundColor] = palette.codeBg
            } else {
                if attrs[.mintBold] as? Bool == true {
                    let converted = NSFontManager.shared.convert(
                        base, toHaveTrait: .boldFontMask)
                    if converted != base { addition[.font] = converted }
                    // 시스템 serif(New York) 폴백은 볼드가 한글 글리프에
                    // 적용되지 않는다 — 커버하지 못하면 스트로크로 가짜 볼드.
                    if !converted.coveredCharacterSet.contains(
                        UnicodeScalar(0xAC00)!) {
                        addition[.strokeWidth] = -2.5
                    }
                }
                // 기울임은 항상 obliqueness — 한글엔 이탤릭 페이스가 없어
                // 폰트 변환으론 라틴만 기울어진다.
                if attrs[.mintItalic] as? Bool == true {
                    addition[.obliqueness] = 0.18
                }
            }
            if let hex = attrs[.mintColor] as? String, let color = NSColor(inlineHex: hex) {
                addition[.foregroundColor] = color
            }
            if !addition.isEmpty { storage.addAttributes(addition, range: run) }
        }
    }

    /// 문단에 저장된 .mintAlign을 문단 스타일에 반영한다.
    private func applyStoredAlignment(
        base attrs: [NSAttributedString.Key: Any], in paragraph: NSRange
    ) {
        guard let storage = textStorage, paragraph.location < storage.length,
            let align = storage.attribute(
                .mintAlign, at: paragraph.location, effectiveRange: nil) as? String,
            let ps = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
                as? NSMutableParagraphStyle
        else { return }
        ps.alignment = align == "right" ? .right : .center
        storage.addAttribute(.paragraphStyle, value: ps, range: paragraph)
    }

    /// 문단에 저장된 .mintLineSpacing을 문단 스타일에 반영한다 (선택 줄 줄 간격, 요구 4).
    /// 정렬 반영(applyStoredAlignment) 뒤에 호출해 현재 문단 스타일을 이어받는다.
    private func applyStoredLineSpacing(in paragraph: NSRange) {
        guard let storage = textStorage, paragraph.location < storage.length,
            let spacing = storage.attribute(
                .mintLineSpacing, at: paragraph.location, effectiveRange: nil) as? Double
        else { return }
        let current =
            storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
            as? NSParagraphStyle ?? .default
        guard let ps = current.mutableCopy() as? NSMutableParagraphStyle else { return }
        ps.lineSpacing = CGFloat(spacing)
        storage.addAttribute(.paragraphStyle, value: ps, range: paragraph)
    }

    // MARK: 스타일 (디자인 CSS와 1:1)

    func styleAttributes(for block: MintBlock, checked: Bool) -> [NSAttributedString.Key: Any] {
        let t = palette
        var font = bodyFont
        var color = t.ink
        let ps = NSMutableParagraphStyle()
        // 자연 줄 높이 + 사용자 줄 간격 — 글자가 커서 높이의 중앙에 오도록
        // 라인 박스를 부풀리지 않는다 (요구 1·4, lineHeightMultiple 대체).
        ps.lineSpacing = lineSpacing

        switch block {
        case .p:
            // 문단 사이에 숨 쉴 여백 — Enter로 나뉜 문단이 랩된 줄과 구분돼 프로즈
            // 리듬이 산다. paragraphSpacing은 하드 리턴 뒤에만 붙고 랩된 줄
            // 사이(lineSpacing)에는 영향이 없다.
            ps.paragraphSpacing = 10
        case .h1:
            font = MintFonts.serif(31, weight: .bold)
            ps.paragraphSpacingBefore = 16
            ps.paragraphSpacing = 4
        case .h2:
            font = MintFonts.serif(25, weight: .semibold)
            ps.paragraphSpacingBefore = 12
            ps.paragraphSpacing = 2
        case .h3:
            font = MintFonts.serif(21, weight: .semibold)
            ps.paragraphSpacingBefore = 8
        case .quote:
            color = t.ink2
            ps.firstLineHeadIndent = 19
            ps.headIndent = 19
            ps.paragraphSpacingBefore = 6
            ps.paragraphSpacing = 6
        case .bullet:
            ps.firstLineHeadIndent = 26
            ps.headIndent = 26
        case .number:
            ps.firstLineHeadIndent = 34
            ps.headIndent = 34
        case .todo:
            ps.firstLineHeadIndent = 32
            ps.headIndent = 32
            if checked { color = t.ink3 }
        case .code:
            font = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
            ps.firstLineHeadIndent = 18
            ps.headIndent = 18
            ps.tailIndent = -18
        case .math:
            font = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
            ps.alignment = .center
            ps.paragraphSpacingBefore = 10
            ps.paragraphSpacing = 10
            ps.firstLineHeadIndent = 20
            ps.headIndent = 20
            ps.tailIndent = -48
        case .divider:
            ps.minimumLineHeight = 28
            ps.maximumLineHeight = 28
        case .image:
            // 소스(![](…)) 편집 모드에서 가운데 정렬 — 렌더 이미지도 중앙에 온다.
            color = t.ink3
            font = MintFonts.ui(13)
            ps.alignment = .center
            ps.paragraphSpacingBefore = 8
            ps.paragraphSpacing = 8
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: ps,
        ]
        if block == .todo, checked {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = t.ink3
        }
        return attrs
    }

    // MARK: 마커 소비 (transformMarkdown)

    override func didChangeText() {
        super.didChangeText()
        guard !isTransforming else { return }
        if !hasMarkedText() {
            transformMarkerIfNeeded()
            transformInlineMarkerIfNeeded()
        }
        // IME 조합 중에도 갱신 — 문단 위치가 밀리면 렌더 range를 다시 잡아야 한다.
        refreshRenderedBlocks()
    }

    /// 커서 바로 앞에서 완성된 인라인 마커(`***…***` `**…**` `*…*` `` `…` ``)를
    /// 소비해 서식 속성으로 바꾼다 — transformMarkdown의 인라인 판.
    private func transformInlineMarkerIfNeeded() {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let para = ns.paragraphRange(for: sel)
        let info = blockInfo(in: para)
        guard ![MintBlock.code, .math, .divider, .image].contains(info.block) else { return }
        let text = paragraphContent(para)
        let nsText = text as NSString
        let caretInPara = sel.location - para.location

        for rule in InlineMarkdown.typingRules {
            let matches = rule.pattern.matches(
                in: text, range: NSRange(location: 0, length: nsText.length))
            // 방금 타이핑으로 닫힌 마커만 — 커서 위치에서 끝나는 매치.
            guard let match = matches.first(where: { $0.range.upperBound == caretInPara })
            else { continue }
            let inner = nsText.substring(with: match.range(at: 1))
            let markerRange = NSRange(
                location: para.location + match.range.location, length: match.range.length)
            isTransforming = true
            if shouldChangeText(in: markerRange, replacementString: inner) {
                storage.replaceCharacters(in: markerRange, with: inner)
                storage.addAttributes(
                    rule.attrs,
                    range: NSRange(
                        location: markerRange.location, length: (inner as NSString).length))
                didChangeText()
            }
            isTransforming = false
            let newPara = (string as NSString).paragraphRange(
                for: NSRange(location: para.location, length: 0))
            applyBlock(
                info.block, checked: info.checked, marker: info.marker,
                to: newPara, registerUndo: false)
            // 변환 직후 이어지는 타이핑은 일반 글씨 — 서식이 계속 번지지 않게.
            var typing = styleAttributes(for: info.block, checked: info.checked)
            typing[.mintBlock] = info.block.rawValue
            if info.checked { typing[.mintChecked] = true }
            if let marker = info.marker { typing[.mintMarker] = marker }
            typingAttributes = typing
            updateTailSnapshot()
            return
        }
    }

    private func transformMarkerIfNeeded() {
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let para = ns.paragraphRange(for: sel)
        let info = blockInfo(in: para)
        let text = paragraphContent(para)

        if info.block == .bullet {
            // "- [ ] "를 두 단계로 쓰는 경우: bullet 상태에서 "[ ] " → todo.
            if let match = text.range(of: #"^\[\s?\]\s"#, options: .regularExpression) {
                consumeMarker(
                    length: text[text.startIndex..<match.upperBound].utf16.count,
                    in: para, block: .todo)
            }
            return
        }
        guard info.block == .p else { return }

        if text == "```" {
            consumeMarker(length: 3, in: para, block: .code)
        } else if text == "$$ " {
            consumeMarker(length: 3, in: para, block: .math)
        } else if text.hasPrefix("$$"), text.hasSuffix("$$"), text.count >= 5 {
            // "$$H_2$$"처럼 여닫는 마커까지 통째로 타이핑한 경우 — 마커를 벗겨
            // 수식 블록으로 바꾼다 ("$$ " 두 글자+공백 방식과 동일한 결과).
            consumeMathWrapper(in: para)
        } else if text == "---" {
            consumeDivider(in: para)
        } else if text.hasPrefix("### ") {
            consumeMarker(length: 4, in: para, block: .h3)
        } else if text.hasPrefix("## ") {
            consumeMarker(length: 3, in: para, block: .h2)
        } else if text.hasPrefix("# ") {
            consumeMarker(length: 2, in: para, block: .h1)
        } else if let match = text.range(of: #"^\[\s?\]\s"#, options: .regularExpression) {
            consumeMarker(
                length: text[text.startIndex..<match.upperBound].utf16.count,
                in: para, block: .todo)
        } else if text.hasPrefix("> ") {
            consumeMarker(length: 2, in: para, block: .quote)
        } else if text.hasPrefix("- ") || text.hasPrefix("* ") {
            consumeMarker(length: 2, in: para, block: .bullet)
        } else if let match = text.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
            let marker = String(text[text.startIndex..<match.upperBound])
                .trimmingCharacters(in: .whitespaces)
            consumeMarker(
                length: text[text.startIndex..<match.upperBound].utf16.count,
                in: para, block: .number, marker: marker)
        }
    }

    private func consumeMarker(
        length: Int, in paragraph: NSRange, block: MintBlock, marker: String? = nil
    ) {
        guard let storage = textStorage else { return }
        isTransforming = true
        let markerRange = NSRange(location: paragraph.location, length: length)
        if shouldChangeText(in: markerRange, replacementString: "") {
            storage.replaceCharacters(in: markerRange, with: "")
            didChangeText()
        }
        isTransforming = false
        let ns = string as NSString
        let newPara = ns.paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        applyBlock(block, marker: marker, to: newPara)
    }

    /// "$$…$$" 한 줄을 마커 없이 수식 블록으로 — 내용만 남기고 블록을 부여한다.
    private func consumeMathWrapper(in paragraph: NSRange) {
        guard let storage = textStorage else { return }
        let text = paragraphContent(paragraph)
        guard text.count >= 5 else { return }
        let inner = String(text.dropFirst(2).dropLast(2))
        isTransforming = true
        let contentRange = NSRange(
            location: paragraph.location, length: (text as NSString).length)
        if shouldChangeText(in: contentRange, replacementString: inner) {
            storage.replaceCharacters(in: contentRange, with: inner)
            didChangeText()
        }
        isTransforming = false
        let newPara = (string as NSString).paragraphRange(
            for: NSRange(location: paragraph.location, length: 0))
        applyBlock(.math, to: newPara)
        refreshRenderedBlocks()
    }

    private func consumeDivider(in paragraph: NSRange) {
        guard let storage = textStorage else { return }
        isTransforming = true
        let markerRange = NSRange(location: paragraph.location, length: 3)
        if shouldChangeText(in: markerRange, replacementString: "") {
            storage.replaceCharacters(in: markerRange, with: "")
            didChangeText()
        }
        isTransforming = false
        let ns = string as NSString
        let dividerPara = ns.paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        applyBlock(.divider, to: dividerPara)
        // 디자인처럼 아래에 새 문단을 만들고 커서를 옮긴다.
        setSelectedRange(NSRange(location: dividerPara.upperBound > dividerPara.location
            ? dividerPara.upperBound - 1 : dividerPara.location, length: 0))
        insertText("\n", replacementRange: selectedRange())
        let caretPara = (string as NSString).paragraphRange(
            for: NSRange(location: selectedRange().location, length: 0))
        applyBlock(.p, to: caretPara)
    }

    // MARK: 키 동작 (Enter/Backspace 블록 규칙)

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertNewline(sender) }
        let sel = selectedRange()
        let ns = string as NSString
        let para = ns.paragraphRange(for: sel)
        let info = blockInfo(in: para)

        // 빈 목록/코드 블록에서 Enter → 블록 해제 (디자인 동작).
        if sel.length == 0, paragraphContent(para).isEmpty,
            [.bullet, .number, .todo, .code].contains(info.block) {
            applyBlock(.p, to: para)
            return
        }

        super.insertNewline(sender)

        // 새 문단의 블록 상속 규칙.
        let caretPara = (string as NSString).paragraphRange(
            for: NSRange(location: selectedRange().location, length: 0))
        switch info.block {
        case .h1, .h2, .h3, .quote, .math, .divider, .image:
            applyBlock(.p, to: caretPara)
        case .todo:
            applyBlock(.todo, checked: false, to: caretPara)
        case .number:
            let next = (Int((info.marker ?? "1.").dropLast()) ?? 1) + 1
            applyBlock(.number, marker: "\(next).", to: caretPara)
        case .bullet:
            applyBlock(.bullet, to: caretPara)
        case .code:
            applyBlock(.code, to: caretPara)
        case .p:
            applyBlock(.p, to: caretPara)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        // 이미지가 객체 선택된 상태면 백스페이스로 문단째 지운다 (요구 3).
        if let loc = selectedImageLocation {
            let para = (string as NSString).paragraphRange(
                for: NSRange(location: min(loc, (string as NSString).length), length: 0))
            deleteImageParagraph(para)
            return
        }
        let sel = selectedRange()
        if sel.length == 0, !hasMarkedText() {
            let ns = string as NSString
            let para = ns.paragraphRange(for: sel)
            let info = blockInfo(in: para)
            // 블록 문단 맨 앞에서 Backspace → 블록 해제 (병합 대신).
            if sel.location == para.location, info.block != .p {
                applyBlock(.p, to: para)
                return
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: 체크박스 클릭

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager, let textContainer {
            let containerPoint = NSPoint(
                x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let index = layoutManager.characterIndex(
                for: containerPoint, in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil)
            let ns = string as NSString
            if ns.length > 0, index <= ns.length {
                let para = ns.paragraphRange(
                    for: NSRange(location: min(index, ns.length), length: 0))
                let info = blockInfo(in: para)
                // 체크박스 히트 존: 문단 들여쓰기(32px) 안쪽 (디자인: left+28).
                if info.block == .todo, containerPoint.x < 28 {
                    applyBlock(.todo, checked: !info.checked, to: para)
                    return
                }
                // 렌더된 이미지 클릭 — 항상 객체 선택(소스는 절대 노출하지 않는다).
                let isRendered = imageRenders.contains { $0.range.location == para.location }
                if info.block == .image, isRendered {
                    selectImageObject(at: para)
                    return
                }
            }
        }
        // 이미지가 아닌 곳을 누르면 객체 선택을 해제한다.
        clearImageSelection()
        super.mouseDown(with: event)
    }

    // MARK: 이미지 삽입 (붙여넣기 · 드롭 · 파일 선택)

    /// 클립보드에 이미지가 있으면 이미지 블록으로 붙여넣고, 아니면 기본 붙여넣기.
    override func paste(_ sender: Any?) {
        if insertImages(from: NSPasteboard.general) { return }
        super.paste(sender)
    }

    /// 툴바 버튼용 — 리스폰더 체인(NSApp.sendAction)으로 도달한다.
    @objc func insertImageFromMenu(_ sender: Any?) {
        presentImagePicker()
    }

    /// ⇧⌘I — 파일 선택 패널로 이미지를 고른다.
    func presentImagePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = MintImageStore.imageExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { insertImageFile(url) }
    }

    /// 파일 URL 하나를 읽어 images 폴더에 복사한 뒤 이미지 블록으로 삽입한다.
    private func insertImageFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
            let relative = MintImageStore.save(data, ext: url.pathExtension)
        else { return }
        insertImageBlock(relativePath: relative)
    }

    /// 페이스트보드에서 이미지(파일 URL 또는 비트맵)를 찾아 삽입한다. 하나라도 넣었으면 true.
    @discardableResult
    private func insertImages(from pasteboard: NSPasteboard) -> Bool {
        // 1) 이미지 파일 URL — 원본 확장자를 유지해 복사한다.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.filter {
                MintImageStore.imageExtensions.contains($0.pathExtension.lowercased())
            }
            if !images.isEmpty {
                images.forEach(insertImageFile)
                return true
            }
        }
        // 2) 비트맵 데이터(스크린샷·복사한 이미지) — PNG로 정규화해 저장한다.
        if let data = pasteboard.data(forType: .png),
            let relative = MintImageStore.save(data, ext: "png") {
            insertImageBlock(relativePath: relative)
            return true
        }
        if let tiff = pasteboard.data(forType: .tiff),
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:]),
            let relative = MintImageStore.save(png, ext: "png") {
            insertImageBlock(relativePath: relative)
            return true
        }
        return false
    }

    /// 페이스트보드에 삽입 가능한 이미지가 있는지 (드래그 수락 판정용).
    private func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            urls.contains(where: {
                MintImageStore.imageExtensions.contains($0.pathExtension.lowercased())
            }) {
            return true
        }
        return pasteboard.canReadItem(withDataConformingToTypes: [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
        ])
    }

    /// `![](상대경로)` 이미지 블록을 커서 위치에 새 문단으로 삽입한다 —
    /// 앞이 비어 있지 않으면 줄을 나누고, 뒤에는 일반 문단을 만들어 커서를 옮긴다
    /// (`consumeDivider`와 같은 흐름).
    func insertImageBlock(relativePath: String) {
        let markdown = "![](\(relativePath))"
        let ns = string as NSString
        let sel = selectedRange()
        let para = ns.paragraphRange(for: sel)
        let onEmptyLine = paragraphContent(para).isEmpty
        let prefix = onEmptyLine && sel.location == para.location ? "" : "\n"
        insertText(prefix + markdown + "\n", replacementRange: sel)

        // 방금 삽입한 이미지 문단(커서 바로 앞 줄)을 찾아 블록을 지정한다.
        let caret = selectedRange().location
        let imagePara = (string as NSString).paragraphRange(
            for: NSRange(location: max(0, caret - 1), length: 0))
        applyBlock(.image, to: imagePara)
        // 커서가 놓인 새 문단은 일반 문단으로.
        let caretPara = (string as NSString).paragraphRange(
            for: NSRange(location: selectedRange().location, length: 0))
        applyBlock(.p, to: caretPara)
        // 커서는 이미지 다음 문단에 있으므로 이미지가 곧바로 렌더된다.
        refreshRenderedBlocks()
    }

    // MARK: 이미지 객체 선택 (정렬·크기·줄바꿈)

    /// 렌더된 이미지를 객체로 선택한다 — 소스를 감춘 채 박스 오버레이와 툴바를 띄운다.
    private func selectImageObject(at para: NSRange) {
        selectedImageLocation = para.location
        // 커서를 문단 시작에 두되(길이 0) 렌더는 유지된다(refresh의 objectSelected 예외).
        setSelectedRange(NSRange(location: para.location, length: 0))
        window?.makeFirstResponder(self)
        refreshRenderedBlocks()
        showImageBox(for: para.location)  // 박스를 먼저 얹고
        presentImageToolbar(for: para)  // 툴바를 그 위에 올린다
    }

    /// 이미지 박스 오버레이를 만들고(또는 갱신) 이미지 위에 얹는다.
    private func showImageBox(for loc: Int) {
        let box: ImageBoxOverlay
        if let existing = imageBox {
            box = existing
        } else {
            box = ImageBoxOverlay(textView: self, theme: palette)
            imageBox = box
        }
        box.paraLocation = loc
        if box.superview !== self { addSubview(box) }
        repositionImageBox()
    }

    /// 객체 선택 해제 — 툴바·박스를 감추고 다시 그린다.
    func clearImageSelection() {
        guard selectedImageLocation != nil else { return }
        selectedImageLocation = nil
        hideImageToolbar()
        imageBox?.removeFromSuperview()
        imageBox = nil
        imageDropIndicatorY = nil
        needsDisplay = true
    }

    /// 선택 변화에 맞춰 이미지 상태를 정리한다 (요구 1):
    /// - 객체 선택 이미지를 벗어나면 선택 해제
    /// - 커서가 이미지 안으로 들어오면 자동으로 객체 선택해, 내부를 커서로
    ///   편집하지 못하게 만든다 (이미지는 항상 렌더 — 소스는 절대 노출 안 됨).
    func syncImageSelection() {
        let ns = string as NSString
        let sel = selectedRange()
        let caretPara = ns.paragraphRange(
            for: NSRange(location: min(sel.location, ns.length), length: 0))

        if let loc = selectedImageLocation, sel.length != 0 || caretPara.location != loc {
            clearImageSelection()
        }
        // 이미지 문단에 커서가 놓였는데 객체 선택이 아니면 자동 선택.
        // (로드·프로그램적 변경 중인 isTransforming 때는 건너뛴다.)
        guard sel.length == 0, !isTransforming, window?.firstResponder === self,
            caretPara.location < ns.length,
            selectedImageLocation != caretPara.location,
            blockInfo(in: caretPara).block == .image,
            Self.imageAttrs(
                from: paragraphContent(caretPara).trimmingCharacters(in: .whitespaces))
                .flatMap({ MintImageStore.image(for: $0.src) }) != nil
        else { return }
        // 커서는 그대로 두고(어차피 숨김) 객체 선택만 채택 — setSelectedRange
        // 재귀를 피한다. refresh가 뒤이어 렌더를 유지한다.
        selectedImageLocation = caretPara.location
        refreshRenderedBlocks()
        presentImageToolbar(for: caretPara)
        needsDisplay = true
    }

    /// 이미지가 객체로 선택된 동안엔 텍스트 입력을 막는다 — 내부는 편집 불가 (요구 1).
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard selectedImageLocation == nil else { return }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    /// 이미지 툴바 액션 실행 (요구 3).
    func performImage(_ action: ImageObjectAction) {
        guard let loc = selectedImageLocation else { return }
        let ns = string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(loc, ns.length), length: 0))
        switch action {
        case .align(let a): rewriteImage(para, setAlign: a)
        case .width(let w): rewriteImage(para, setWidth: w)
        case .lineBreak: imageLineBreak(after: para)
        case .delete: deleteImageParagraph(para)
        }
    }

    /// 이미지 소스 줄의 `{width align}` 속성을 새 값으로 바꿔 다시 쓴다 (undo 포함).
    private func rewriteImage(_ para: NSRange, setAlign: String? = nil, setWidth: Int? = nil) {
        guard let storage = textStorage else { return }
        let content = paragraphContent(para)
        guard var attrs = Self.imageAttrs(
            from: content.trimmingCharacters(in: .whitespaces))
        else { return }
        if let a = setAlign { attrs.align = a }
        if let w = setWidth { attrs.width = w }
        let newLine = attrs.markdown
        let contentRange = NSRange(
            location: para.location, length: (content as NSString).length)
        guard newLine != content,
            shouldChangeText(in: contentRange, replacementString: newLine)
        else { return }
        isTransforming = true
        storage.replaceCharacters(in: contentRange, with: newLine)
        isTransforming = false
        let newPara = (string as NSString).paragraphRange(
            for: NSRange(location: para.location, length: 0))
        applyBlock(.image, to: newPara, registerUndo: false)
        selectedImageLocation = newPara.location
        setSelectedRange(NSRange(location: newPara.location, length: 0))
        didChangeText()
        refreshRenderedBlocks()
        presentImageToolbar(for: newPara)
    }

    /// 이미지 뒤에 빈 문단을 만들고 커서를 옮긴다 — "줄바꿈"(요구 3).
    private func imageLineBreak(after para: NSRange) {
        clearImageSelection()
        let content = paragraphContent(para)
        let end = para.location + (content as NSString).length
        setSelectedRange(NSRange(location: end, length: 0))
        window?.makeFirstResponder(self)
        insertText("\n", replacementRange: selectedRange())
        let caret = selectedRange().location
        let newPara = (string as NSString).paragraphRange(
            for: NSRange(location: caret, length: 0))
        applyBlock(.p, to: newPara)
        refreshRenderedBlocks()
    }

    /// 이미지 문단을 개행째 지운다 (요구 3 · 백스페이스 공통).
    private func deleteImageParagraph(_ para: NSRange) {
        guard let storage = textStorage else { return }
        clearImageSelection()
        guard shouldChangeText(in: para, replacementString: "") else { return }
        isTransforming = true
        storage.replaceCharacters(in: para, with: "")
        isTransforming = false
        let ns = string as NSString
        setSelectedRange(NSRange(location: min(para.location, ns.length), length: 0))
        didChangeText()
        refreshRenderedBlocks()
    }

    /// 선택된 이미지 위에 정렬·크기·줄바꿈 툴바를 띄운다.
    /// `overrideWidth`는 드래그 리사이즈 중 실시간 % 표시용.
    private func presentImageToolbar(for para: NSRange, overrideWidth: Int? = nil) {
        guard imageRenders.contains(where: { $0.range.location == para.location }),
            let attrs = Self.imageAttrs(
                from: paragraphContent(para).trimmingCharacters(in: .whitespaces)),
            let rect = paragraphRectInView(para)
        else { return }

        let view = ImageObjectToolbarView(
            theme: palette, width: overrideWidth ?? attrs.width, align: attrs.align
        ) { [weak self] action in
            self?.performImage(action)
        }
        let host: NSHostingView<ImageObjectToolbarView>
        if let existing = imageToolbarHost {
            existing.rootView = view
            host = existing
        } else {
            host = NSHostingView(rootView: view)
            imageToolbarHost = host
        }
        let size = host.fittingSize
        // 이미지 위 중앙 — 위가 좁으면 아래로 내린다 (flipped 좌표).
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.maxY + 8 }
        origin.x = max(8, min(origin.x, bounds.width - size.width - 8))
        host.frame = NSRect(origin: origin, size: size)
        if host.superview !== self { addSubview(host) }
    }

    func hideImageToolbar() {
        imageToolbarHost?.removeFromSuperview()
    }

    /// 문단이 차지하는 **전체 컬럼 폭** rect (뷰 좌표) — 레이아웃 매니저의
    /// `paragraphRect`(이미지를 그리는 기준)와 정확히 같은 규칙으로 만든다.
    /// 이게 어긋나 있어서 핸들 히트 존이 이미지와 따로 놀았다(리사이즈 불가 버그).
    private func paragraphRectInView(_ para: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: para, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        rect.origin.y += textContainerOrigin.y
        // x·폭을 컬럼 전체로 맞춘다 (drawImage의 rect와 동일).
        rect.origin.x = textContainerOrigin.x + textContainer.lineFragmentPadding
        rect.size.width = textContainer.size.width - textContainer.lineFragmentPadding * 2
        return rect
    }

    // MARK: 이미지 크기 조절 (모서리 핸들 드래그, 요구 2)

    /// 렌더된 이미지가 실제로 그려지는 뷰 좌표 rect — `drawImage`와 같은 규칙.
    /// 핸들 히트 테스트·그리기의 기준.
    func imageDrawnRect(forParagraphAt loc: Int) -> NSRect? {
        guard let render = imageRenders.first(where: { $0.range.location == loc }),
            let row = paragraphRectInView(
                (string as NSString).paragraphRange(
                    for: NSRange(location: min(loc, (string as NSString).length), length: 0)))
        else { return nil }
        let box = row.insetBy(dx: 8, dy: 6)
        guard render.size.width > 0, render.size.height > 0 else { return nil }
        let scale = min(box.width / render.size.width, box.height / render.size.height, 1)
        let size = NSSize(width: render.size.width * scale, height: render.size.height * scale)
        let x: CGFloat
        switch render.align {
        case "left": x = box.minX
        case "right": x = box.maxX - size.width
        default: x = row.midX - size.width / 2
        }
        return NSRect(
            x: x, y: row.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// 100% 표시 너비 — 드래그 델타를 %로 환산할 때의 기준.
    func imageFitWidth(forParagraphAt loc: Int) -> CGFloat? {
        guard let render = imageRenders.first(where: { $0.range.location == loc })
        else { return nil }
        return imageDisplaySize(render.image, widthPercent: 100).width
    }

    /// 이미지 소스에서 현재 너비(%)를 읽는다.
    func imageWidthPercent(at loc: Int) -> Int {
        let para = (string as NSString).paragraphRange(
            for: NSRange(location: min(loc, (string as NSString).length), length: 0))
        return Self.imageAttrs(
            from: paragraphContent(para).trimmingCharacters(in: .whitespaces))?.width ?? 100
    }

    // MARK: - 이미지 박스 오버레이 연동 (요구 A·B)

    /// 오버레이(있으면)를 이미지 위치에 맞춰 다시 배치한다.
    func repositionImageBox() {
        guard let box = imageBox, let loc = selectedImageLocation,
            let rect = imageDrawnRect(forParagraphAt: loc)
        else { return }
        box.frame = rect.insetBy(dx: -box.inset, dy: -box.inset)
        box.needsDisplay = true
    }

    /// 크기 조절 미리보기 — 시작 너비%에 드래그 델타(pt)를 더해 %로 환산해 반영한다.
    func previewImageResize(at loc: Int, startWidth: Int, deltaWidth: CGFloat) {
        guard let fitW = imageFitWidth(forParagraphAt: loc), fitW > 0 else { return }
        let startDisplayW = fitW * CGFloat(startWidth) / 100
        let pct = Int(((startDisplayW + deltaWidth) / fitW * 100).rounded())
        let clamped = min(100, max(10, pct))
        resizePreview = (loc, clamped)
        refreshRenderedBlocks()  // 끝에서 repositionImageBox 호출됨
        let para = (string as NSString).paragraphRange(
            for: NSRange(location: min(loc, (string as NSString).length), length: 0))
        presentImageToolbar(for: para, overrideWidth: clamped)
    }

    /// 크기 조절 확정 — 미리보기 너비%를 소스에 기록한다.
    func commitImageResize(at loc: Int) {
        let finalWidth = resizePreview?.width
        resizePreview = nil
        let para = (string as NSString).paragraphRange(
            for: NSRange(location: min(loc, (string as NSString).length), length: 0))
        if let finalWidth, finalWidth != imageWidthPercent(at: loc) {
            rewriteImage(para, setWidth: finalWidth)
        } else {
            refreshRenderedBlocks()
            presentImageToolbar(for: para)
        }
    }

    /// 이동 드래그 중 — 드롭될 문단 위쪽에 표시선을 그린다.
    func updateImageDropIndicator(toViewPoint p: NSPoint) {
        let idx = min(characterIndexForInsertion(at: p), (string as NSString).length)
        let dropPara = (string as NSString).paragraphRange(
            for: NSRange(location: idx, length: 0))
        imageDropIndicatorY = paragraphRectInView(dropPara)?.minY
        needsDisplay = true
    }

    /// 이미지 문단을 드롭 지점의 문단 앞으로 옮긴다 (요구 B).
    func moveImageParagraph(at loc: Int, toViewPoint p: NSPoint) {
        imageDropIndicatorY = nil
        guard let storage = textStorage else { return }
        let ns = string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(loc, ns.length), length: 0))
        let lineText = paragraphContent(para)
        let dropIdx = min(characterIndexForInsertion(at: p), ns.length)
        let dropPara = ns.paragraphRange(for: NSRange(location: dropIdx, length: 0))
        guard dropPara.location != para.location else {
            refreshRenderedBlocks(); return
        }
        clearImageSelection()

        // 지울 범위: 이미지 문단(개행 포함). 마지막 줄이라 개행이 없으면 앞 개행을 지운다.
        var removeRange = para
        let endsNL =
            para.length > 0
            && ns.substring(
                with: NSRange(location: para.location + para.length - 1, length: 1)) == "\n"
        if !endsNL, para.location > 0 {
            removeRange = NSRange(location: para.location - 1, length: para.length + 1)
        }
        var insertLoc = dropPara.location

        guard shouldChangeText(
            in: NSRange(location: 0, length: ns.length), replacementString: nil)
        else { return }
        isTransforming = true
        storage.replaceCharacters(in: removeRange, with: "")
        // 삭제로 밀린 삽입 위치 보정.
        if insertLoc >= removeRange.location + removeRange.length {
            insertLoc -= removeRange.length
        } else if insertLoc > removeRange.location {
            insertLoc = removeRange.location
        }
        insertLoc = min(max(0, insertLoc), (string as NSString).length)
        storage.replaceCharacters(
            in: NSRange(location: insertLoc, length: 0), with: lineText + "\n")
        isTransforming = false

        let newPara = (string as NSString).paragraphRange(
            for: NSRange(location: insertLoc, length: 0))
        applyBlock(.image, to: newPara, registerUndo: false)
        setSelectedRange(NSRange(location: newPara.location, length: 0))
        didChangeText()
        // 옮긴 이미지를 다시 객체 선택해 박스를 이어서 보여준다.
        selectImageObject(at: newPara)
    }

    // MARK: 드래그 드롭 (이미지 파일)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteboardHasImage(sender.draggingPasteboard)
            ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        pasteboardHasImage(sender.draggingPasteboard)
            ? .copy : super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        pasteboardHasImage(sender.draggingPasteboard)
            ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard pasteboardHasImage(sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        // 드롭 지점으로 커서를 옮긴 뒤 그 자리에 삽입한다.
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        if index != NSNotFound {
            setSelectedRange(NSRange(location: min(index, (string as NSString).length), length: 0))
        }
        return insertImages(from: sender.draggingPasteboard)
    }

    // MARK: 수식·이미지 렌더

    /// 수식·이미지 문단 표시 갱신 — 커서가 밖에 있고 소스가 렌더되면 소스 글자를
    /// 투명 처리(temporary attribute — storage·undo·저장에 무해)하고, 레이아웃
    /// 매니저가 그 자리에 렌더 결과를 그린다. 커서가 들어오면 소스로 돌아온다.
    func refreshRenderedBlocks(forceRender: Bool = false) {
        guard let layoutManager, let storage = textStorage else { return }
        // 빠른 경로: 렌더 중인 블록도, 이미 렌더된 것도, 이미지 선택도 없고 소스에
        // 수식/이미지 마커("$$"·"![")조차 없으면 — 즉 대다수의 평문 저널이면 —
        // 문단 순회·임시속성 조작·전체 재그리기를 통째로 건너뛴다(키 입력마다 O(n)
        // 낭비 제거). 마커 검사는 NSString range 검색이라 문단 순회보다 훨씬 싸다.
        if mathRenders.isEmpty, imageRenders.isEmpty, selectedImageLocation == nil {
            let source = storage.string as NSString
            if source.range(of: "$$").location == NSNotFound,
                source.range(of: "![").location == NSNotFound {
                return
            }
        }
        layoutManager.removeTemporaryAttribute(
            .foregroundColor,
            forCharacterRange: NSRange(location: 0, length: storage.length))
        var maths: [(range: NSRange, image: NSImage)] = []
        var images: [ImageRender] = []
        let ns = string as NSString
        let sel = selectedRange()
        // 포커스가 사이드바 등 밖에 있으면 커서가 문단에 남아 있어도 렌더한다 —
        // 수식·이미지가 문서 마지막 문단일 때 소스가 계속 보이는 문제 방지.
        let focused = window?.firstResponder === self
        var location = 0
        while location < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: location, length: 0))
            defer { location = para.upperBound }
            let block = blockInfo(in: para).block
            guard block == .math || block == .image else { continue }

            let content = paragraphContent(para)
            let contentEnd = para.location + (content as NSString).length
            let objectSelected = block == .image && selectedImageLocation == para.location
            // 이미지는 소스를 **절대** 보여주지 않는다 — 항상 렌더(요구 1).
            // 수식만 커서가 닿으면 편집 모드(소스)로 전환한다.
            let editing =
                block == .math && !forceRender && focused
                && ((sel.length == 0 && sel.location >= para.location
                    && sel.location <= contentEnd)
                    || (sel.length > 0 && NSIntersectionRange(sel, para).length > 0))
            let source = content.trimmingCharacters(in: .whitespaces)

            let rendered: NSImage?
            var attrs: ImageAttrs?
            switch block {
            case .math:
                rendered = source.isEmpty ? nil : MathRenderer.image(
                    latex: source, color: palette.ink, fontSize: mathFontSize)
            case .image:
                attrs = Self.imageAttrs(from: source)
                rendered = attrs.flatMap { MintImageStore.image(for: $0.src) }
            default:
                rendered = nil
            }

            switch block {
            case .math:
                if let image = rendered {
                    // 렌더되는 한 줄 높이(마진)를 **항상** 유지한다 — 커서가 들어와도,
                    // 다른 곳 갔다 와도 풀리지 않게 (요구 2). 편집 모드면 소스만 보인다.
                    updateRenderedLineHeight(displayHeight(of: image), block: .math, in: para)
                    if !editing {
                        maths.append((para, image))
                        layoutManager.addTemporaryAttribute(
                            .foregroundColor, value: NSColor.clear, forCharacterRange: para)
                    }
                } else if source.isEmpty {
                    updateRenderedLineHeight(nil, block: .math, in: para)  // 빈 수식만 기본
                }
                // 소스가 있는데 파싱 불가면 직전 높이를 유지(아무것도 안 한다).
            case .image:
                guard let image = rendered else {
                    updateRenderedLineHeight(nil, block: .image, in: para)
                    continue
                }
                let a = attrs ?? ImageAttrs(src: "")
                // 드래그 리사이즈 중이면 미리보기 너비를 우선한다.
                let width = resizePreview?.loc == para.location
                    ? resizePreview!.width : a.width
                let size = imageDisplaySize(image, widthPercent: width)
                images.append(
                    ImageRender(
                        range: para, image: image, size: size, align: a.align,
                        selected: objectSelected))
                updateRenderedLineHeight(size.height, block: .image, in: para)
                layoutManager.addTemporaryAttribute(
                    .foregroundColor, value: NSColor.clear, forCharacterRange: para)
            default:
                break
            }
        }
        mathRenders = maths
        imageRenders = images
        repositionImageBox()  // 렌더/줄 높이 변화에 박스 위치를 맞춘다.
        needsDisplay = true
    }

    /// `![alt](src)` 한 줄에서 src(상대경로)만 뽑는다. 형식이 아니면 nil.
    static func imageSource(from line: String) -> String? {
        imageAttrs(from: line)?.src
    }

    /// `![](src){width=NN align=X}` 한 줄에서 소스·너비·정렬을 파싱한다. 형식이 아니면 nil.
    static func imageAttrs(from line: String) -> ImageAttrs? {
        let ns = line as NSString
        guard let match = imageLinePattern.firstMatch(
            in: line, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        let src = ns.substring(with: match.range(at: 1))
        guard !src.isEmpty else { return nil }
        var attrs = ImageAttrs(src: src)
        let optRange = match.range(at: 2)
        if optRange.location != NSNotFound {
            for token in ns.substring(with: optRange)
                .components(separatedBy: .whitespaces) where !token.isEmpty {
                let kv = token.components(separatedBy: "=")
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "width": if let w = Int(kv[1]) { attrs.width = min(100, max(10, w)) }
                case "align" where ["left", "center", "right"].contains(kv[1]):
                    attrs.align = kv[1]
                default: break
                }
            }
        }
        return attrs
    }

    private static let imageLinePattern = try! NSRegularExpression(
        pattern: #"^!\[[^\]]*\]\(([^)\s]+)\)(?:\{([^}]*)\})?$"#)

    /// drawMath와 같은 규칙(폭 초과 시 축소)으로 실제 그려질 수식 높이를 구한다.
    private func displayHeight(of image: NSImage) -> CGFloat {
        guard let container = textContainer, image.size.width > 0 else {
            return image.size.height
        }
        let rectWidth = container.size.width - container.lineFragmentPadding * 2
        // 컬럼 폭이 아직 안 잡혔으면(레이아웃 전·저널 전환 순간) 축소하지 않는다 —
        // 예전엔 max(40,…) 바닥값이 수식을 40pt로 줄여 줄 높이를 붕괴시켰다.
        guard rectWidth > 120 else { return image.size.height }
        let scale = min(1, (rectWidth - 32) / image.size.width)
        return image.size.height * scale
    }

    /// 이미지가 실제로 그려질 크기 — 컬럼 폭에 맞추고 세로는 480pt로 제한한 뒤,
    /// 사용자 지정 너비 %(요구 3)를 곱한다. (레이아웃 매니저와 같은 규칙.)
    func imageDisplaySize(_ image: NSImage, widthPercent: Int = 100) -> NSSize {
        guard image.size.width > 0, image.size.height > 0 else { return image.size }
        let rectWidth =
            (textContainer.map { $0.size.width - $0.lineFragmentPadding * 2 })
            ?? bounds.width
        let maxHeight: CGFloat = 480
        let pct = CGFloat(min(100, max(10, widthPercent))) / 100
        // 컬럼 폭이 아직 안 잡혔으면(레이아웃 전·전환 순간) 세로 상한만 적용 — 폭
        // 축소로 크기가 붕괴하지 않게.
        let fit: CGFloat
        if rectWidth > 120 {
            fit = min(1, min((rectWidth - 16) / image.size.width, maxHeight / image.size.height))
        } else {
            fit = min(1, maxHeight / image.size.height)
        }
        let scale = fit * pct
        return NSSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// 수식·이미지 문단의 줄 높이를 렌더 크기에 맞춘다 (nil이면 기본 스타일로 복원).
    /// 표시 전용 속성 변경 — 저장 텍스트·undo에 흔적이 없다.
    private func updateRenderedLineHeight(
        _ height: CGFloat?, block: MintBlock, in paragraph: NSRange
    ) {
        guard let storage = textStorage, paragraph.length > 0,
            paragraph.location < storage.length,
            let ps = (styleAttributes(for: block, checked: false)[.paragraphStyle]
                as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
        else { return }
        if let height {
            // 위아래 여유 12pt — 배경 박스(-6 inset)와 시각적으로 맞는 값.
            ps.minimumLineHeight = height + 12
        }
        let current =
            storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
            as? NSParagraphStyle
        guard current?.minimumLineHeight != ps.minimumLineHeight else { return }
        storage.addAttribute(.paragraphStyle, value: ps, range: paragraph)
    }

    /// 폭이 바뀌면 수식·이미지 축소 배율이 달라진다 — 줄 높이를 다시 맞춘다.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        guard widthChanged else { return }
        // 가독 폭 유지 — 넓어진 만큼 좌우 여백(inset)을 키워 본문을 가운데로 모은다.
        let inset = EditorMetrics.sideInset(forWidth: newSize.width)
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: textContainerInset.height)
        }
        // 폭이 바뀌면 수식·이미지 축소 배율이 달라진다 — 줄 높이를 다시 맞춘다.
        if !mathRenders.isEmpty || !imageRenders.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.refreshRenderedBlocks() }
        }
    }

    // MARK: 서식 툴바 (선택 위 플로팅)

    private var toolbarHost: NSHostingView<SelectionToolbarView>?
    private var toolbarShowTask: Task<Void, Never>?
    /// 이미지 객체 선택 시 뜨는 정렬·크기·줄바꿈 툴바 (요구 3).
    private var imageToolbarHost: NSHostingView<ImageObjectToolbarView>?

    /// 선택이 생기면 잠깐 안정된 뒤 툴바를 띄우고, 사라지면 감춘다.
    func updateSelectionToolbar() {
        toolbarShowTask?.cancel()
        let sel = selectedRange()
        guard sel.length > 0, !hasMarkedText() else {
            hideSelectionToolbar()
            return
        }
        // 드래그 중 깜빡임 방지 — 선택이 멈춘 뒤에만 표시한다.
        toolbarShowTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.presentSelectionToolbar()
        }
    }

    func hideSelectionToolbar() {
        toolbarShowTask?.cancel()
        toolbarHost?.removeFromSuperview()
    }

    private func presentSelectionToolbar() {
        guard let layoutManager, let textContainer else { return }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let view = SelectionToolbarView(
            theme: palette, state: currentSelectionState()
        ) { [weak self] action in
            self?.perform(action)
        }
        let host: NSHostingView<SelectionToolbarView>
        if let existing = toolbarHost {
            existing.rootView = view
            host = existing
        } else {
            host = NSHostingView(rootView: view)
            toolbarHost = host
        }
        let size = host.fittingSize
        // 선택 위 중앙 — 문서 맨 위라 걸리면 선택 아래로 내린다 (flipped 좌표).
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.maxY + 8 }
        origin.x = max(8, min(origin.x, bounds.width - size.width - 8))
        host.frame = NSRect(origin: origin, size: size)
        if host.superview !== self { addSubview(host) }
    }

    private func currentSelectionState() -> SelectionStyleState {
        var state = SelectionStyleState()
        guard let storage = textStorage else { return state }
        let sel = selectedRange()
        let ns = string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        state.block = blockInfo(in: para).block
        // 줄 간격은 문단 단위 — 선택 시작 문단의 저장값(없으면 전역 설정) 기준.
        state.lineSpacing =
            (para.location < storage.length
                ? storage.attribute(.mintLineSpacing, at: para.location, effectiveRange: nil)
                    as? Double : nil) ?? Double(lineSpacing)
        guard sel.location < storage.length else { return state }
        let attrs = storage.attributes(at: sel.location, effectiveRange: nil)
        state.bold = attrs[.mintBold] as? Bool == true
        state.italic = attrs[.mintItalic] as? Bool == true
        state.code = attrs[.mintCode] as? Bool == true
        state.align = attrs[.mintAlign] as? String
        state.colorHex = attrs[.mintColor] as? String
        state.fontSize =
            (attrs[.mintFontSize] as? Double)
            ?? Double((attrs[.font] as? NSFont ?? bodyFont).pointSize)
        return state
    }

    /// 툴바 액션 실행 — 끝나면 포커스를 에디터로 되돌리고 하이라이트를 갱신한다.
    func perform(_ action: SelectionToolbarAction) {
        switch action {
        case .toggleBold: toggleInlineStyle(.mintBold)
        case .toggleItalic: toggleInlineStyle(.mintItalic)
        case .toggleCode: toggleInlineStyle(.mintCode)
        case .color(let hex): applyInlineColor(hex)
        case .fontSize(let size): applyInlineFontSize(size)
        case .lineSpacing(let v): applyLineSpacing(v)
        case .align(let align): applyAlignment(align)
        case .block(let block): convertSelectionBlock(to: block)
        }
        window?.makeFirstResponder(self)
        presentSelectionToolbar()
    }

    /// 선택 범위의 인라인 속성 토글 — 전체가 켜져 있으면 끄고, 아니면 켠다.
    func toggleInlineStyle(_ key: NSAttributedString.Key) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        var allOn = true
        storage.enumerateAttribute(key, in: sel, options: []) { value, _, stop in
            if (value as? Bool) != true {
                allOn = false
                stop.pointee = true
            }
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        isTransforming = true
        if allOn {
            storage.removeAttribute(key, range: sel)
        } else {
            storage.addAttribute(key, value: true, range: sel)
            if key == .mintCode {
                // 인라인 코드는 배타 — 굵게·기울임·색과 겹치지 않는다.
                storage.removeAttribute(.mintBold, range: sel)
                storage.removeAttribute(.mintItalic, range: sel)
                storage.removeAttribute(.mintColor, range: sel)
            }
        }
        redecorateParagraphs(in: sel)
        isTransforming = false
        didChangeText()
    }

    /// 선택 범위 글자색 적용 (nil = 기본 잉크색으로 복원).
    func applyInlineColor(_ hex: String?) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        isTransforming = true
        if let hex {
            storage.addAttribute(.mintColor, value: hex, range: sel)
        } else {
            storage.removeAttribute(.mintColor, range: sel)
        }
        redecorateParagraphs(in: sel)
        isTransforming = false
        didChangeText()
    }

    /// 선택 범위 글자 크기 적용 — 블록 기본 크기와 같아지면 속성을 제거한다
    /// (저장 마크다운에 불필요한 `<font size>` 래퍼를 남기지 않는다).
    func applyInlineFontSize(_ size: Double) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        let ns = string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let info = blockInfo(in: para)
        let baseSize =
            (styleAttributes(for: info.block, checked: info.checked)[.font] as? NSFont)?
            .pointSize ?? bodyFont.pointSize
        isTransforming = true
        if abs(CGFloat(size) - baseSize) < 0.5 {
            storage.removeAttribute(.mintFontSize, range: sel)
        } else {
            storage.addAttribute(.mintFontSize, value: size, range: sel)
        }
        redecorateParagraphs(in: sel)
        isTransforming = false
        didChangeText()
    }

    /// 선택이 걸친 문단들의 정렬 지정 (nil = 왼쪽 기본).
    /// 저장은 .p 문단만 지원 — 다른 블록에선 화면 정렬만 바뀐다.
    func applyAlignment(_ align: String?) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let ns = string as NSString
        var location = sel.location
        repeat {
            let para = ns.paragraphRange(
                for: NSRange(location: min(location, ns.length), length: 0))
            if para.length > 0, para.location < storage.length {
                _ = shouldChangeText(in: para, replacementString: nil)
                isTransforming = true
                if let align {
                    storage.addAttribute(.mintAlign, value: align, range: para)
                } else {
                    storage.removeAttribute(.mintAlign, range: para)
                }
                let info = blockInfo(in: para)
                applyBlock(
                    info.block, checked: info.checked, marker: info.marker,
                    to: para, registerUndo: false)
                isTransforming = false
                didChangeText()
            }
            location = para.upperBound
        } while location < sel.upperBound
    }

    /// 선택이 걸친 문단들의 줄 간격(pt)을 지정한다 — 선택 줄에 한해 (요구 4).
    /// 표시 전용 속성(.mintLineSpacing)이라 마크다운엔 저장되지 않는다.
    func applyLineSpacing(_ value: Double) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let ns = string as NSString
        var location = sel.location
        repeat {
            let para = ns.paragraphRange(
                for: NSRange(location: min(location, ns.length), length: 0))
            if para.length > 0, para.location < storage.length {
                _ = shouldChangeText(in: para, replacementString: nil)
                isTransforming = true
                storage.addAttribute(.mintLineSpacing, value: value, range: para)
                let info = blockInfo(in: para)
                applyBlock(
                    info.block, checked: info.checked, marker: info.marker,
                    to: para, registerUndo: false)
                isTransforming = false
                didChangeText()
            }
            location = para.upperBound
        } while location < sel.upperBound
    }

    /// 선택이 걸친 문단들을 블록으로 전환 — 이미 그 블록이면 본문으로 토글.
    func convertSelectionBlock(to target: MintBlock) {
        let sel = selectedRange()
        let ns = string as NSString
        let firstPara = ns.paragraphRange(
            for: NSRange(location: min(sel.location, ns.length), length: 0))
        let resolved: MintBlock = blockInfo(in: firstPara).block == target ? .p : target
        var location = sel.location
        repeat {
            let para = ns.paragraphRange(
                for: NSRange(location: min(location, ns.length), length: 0))
            applyBlock(resolved, to: para)
            location = para.upperBound
        } while location < sel.upperBound
        refreshRenderedBlocks()
    }

    /// 범위에 걸친 문단들을 다시 장식 (블록 기본 + 인라인 조립, undo 미등록).
    private func redecorateParagraphs(in range: NSRange) {
        let ns = string as NSString
        var location = range.location
        repeat {
            let para = ns.paragraphRange(
                for: NSRange(location: min(location, ns.length), length: 0))
            let info = blockInfo(in: para)
            applyBlock(
                info.block, checked: info.checked, marker: info.marker,
                to: para, registerUndo: false)
            location = para.upperBound
        } while location < range.upperBound
    }

    /// ⌘F 검색 · ⌘G 다음/이전 매치 · ⌘B/⌘I 서식 토글(선택 있을 때만).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        // 서식·이미지 단축키는 메뉴 막대(MintCommands)로 옮겨 단일 소스로 관리한다 —
        // 여기선 문서 내 검색만 처리한다.
        if flags == .command {
            switch key {
            case "f":
                performFind(.showFindInterface)
                return true
            case "g":
                performFind(.nextMatch)
                return true
            default:
                break
            }
        } else if flags == [.command, .shift], key == "g" {
            performFind(.previousMatch)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: 메뉴 명령 (리스폰더 체인 — MintCommands가 NSApp.sendAction으로 호출)
    //
    // 선택이 있으면 선택에, 없으면 커서 문단에 적용된다(convert/align은 문단 단위,
    // toggleInlineStyle은 선택이 있어야 동작). 에디터가 first responder일 때만 도달한다.

    @objc func mintFormatBold(_ sender: Any?) { toggleInlineStyle(.mintBold) }
    @objc func mintFormatItalic(_ sender: Any?) { toggleInlineStyle(.mintItalic) }
    @objc func mintFormatCode(_ sender: Any?) { toggleInlineStyle(.mintCode) }
    @objc func mintHeading1(_ sender: Any?) { convertSelectionBlock(to: .h1) }
    @objc func mintHeading2(_ sender: Any?) { convertSelectionBlock(to: .h2) }
    @objc func mintHeading3(_ sender: Any?) { convertSelectionBlock(to: .h3) }
    @objc func mintBodyText(_ sender: Any?) { convertSelectionBlock(to: .p) }
    @objc func mintBulletList(_ sender: Any?) { convertSelectionBlock(to: .bullet) }
    @objc func mintNumberedList(_ sender: Any?) { convertSelectionBlock(to: .number) }
    @objc func mintQuoteBlock(_ sender: Any?) { convertSelectionBlock(to: .quote) }
    @objc func mintCodeBlock(_ sender: Any?) { convertSelectionBlock(to: .code) }
    @objc func mintAlignLeft(_ sender: Any?) { applyAlignment(nil) }
    @objc func mintAlignCenter(_ sender: Any?) { applyAlignment("center") }
    @objc func mintAlignRight(_ sender: Any?) { applyAlignment("right") }

    /// NSTextFinder 액션 실행 — performTextFinderAction은 sender의 tag로 동작을 읽는다.
    private func performFind(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    // MARK: 커서 펄스 · 리플 · 커서 줄 하이라이트 드로잉

    /// 일반 blink는 유지하되, 켜질 때마다 밝기가 아주 미세하게 물결치는 커서.
    /// 커서 — 특수효과 없이 기본 깜빡임만, 다만 폭을 얇게 그린다 (요구 2).
    /// 이미지가 객체로 선택된 동안엔 커서를 그리지 않는다 — 이미지 내부는 편집
    /// 대상이 아니라 조작 대상이므로 커서가 보이면 혼란스럽다 (요구 1).
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard selectedImageLocation == nil else {
            if !flag { setNeedsDisplay(rect.insetBy(dx: -2, dy: -2)) }
            return
        }
        // 시스템 캐럿 rect는 라인 전체를 덮어 글자 위로 떠 보인다. 베이스라인 위
        // "글자 실제 높이"만큼만 그려 글자에 딱 맞춘다. 라틴 capHeight로 자르면
        // 한글보다 짧아 보이므로(한글 온디바이스 저널), capHeight~ascender 사이로
        // 올려 한글 상단까지 덮는다(요구: 커서가 글자와 같은 키).
        let font = caretLineFont()
        let baseline = rect.minY + font.ascender
        let glyphTop = font.capHeight + (font.ascender - font.capHeight) * 0.4
        var caret = rect
        caret.origin.y = baseline - glyphTop
        caret.size.height = max(1, glyphTop - font.descender)  // descender 음수
        super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
    }

    /// 커서가 놓인 줄의 폰트 — 캐럿·하이라이트가 공유하는 메트릭 소스.
    private func caretLineFont() -> NSFont {
        (typingAttributes[.font] as? NSFont) ?? bodyFont
    }

    // MARK: 고스트 렌더 (M3 그대로)

    /// AI 제안이 처음 뜰 때 투명도를 0→1로 올려 부드럽게 스며들게 한다
    /// (약 150ms, ease-out). 경과 시간 기반이라 프레임 지터에 흔들리지 않는다.
    /// 커서 이동·이어지는 입력은 ghostText를 nil로 바꾸며 이 태스크를 취소한다
    /// (updateSelectionToolbar의 Task 패턴과 동일 — 메인 액터 상속).
    private func startGhostFadeIn() {
        ghostFadeTask?.cancel()
        ghostOpacity = 0
        needsDisplay = true
        let start = Date()
        let duration = 0.15
        ghostFadeTask = Task { [weak self] in
            while true {
                guard !Task.isCancelled, let self else { return }
                let t = min(1, Date().timeIntervalSince(start) / duration)
                self.ghostOpacity = CGFloat(t * (2 - t))  // ease-out quad
                self.needsDisplay = true
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 커서 줄 하이라이트 — 본문 아래에 깔리도록 텍스트보다 먼저 그린다.
        let lineRect = activeLineRect()
        lastActiveLineRect = lineRect
        if let lineRect, lineRect.intersects(dirtyRect) {
            palette.activeLine.setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: 6, yRadius: 6).fill()
        }

        super.draw(dirtyRect)

        // 이미지 이동 드래그 중 드롭 위치 표시선 (요구 B).
        if let y = imageDropIndicatorY {
            let inset = textContainerInset.width
            palette.blue.setFill()
            NSRect(x: inset, y: y - 1, width: bounds.width - inset * 2, height: 2).fill()
        }

        guard let ghost = ghostText, !ghost.isEmpty,
            !hasMarkedText(),
            selectedRange().length == 0,
            let caretRect = caretRectInView()
        else { return }

        // 커서 문단의 실제 폰트로 그린다 — 제목 줄에서도 크기가 맞는다.
        let font = (typingAttributes[.font] as? NSFont) ?? bodyFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.ghost.withAlphaComponent(ghostOpacity),
        ]
        // 프래그먼트 top(caretRect.minY)이 아니라 본문 글리프와 같은
        // 베이스라인에 맞춰야 실제 글자 높이와 일치한다 (줄 간격과 무관하게).
        let y = caretBaselineY().map { $0 - font.ascender } ?? caretRect.minY
        NSAttributedString(string: ghost, attributes: attributes)
            .draw(at: NSPoint(x: caretRect.maxX, y: y))
    }

    private func caretRectInView() -> NSRect? {
        guard let window else { return nil }
        let caret = selectedRange().location
        guard caret != NSNotFound else { return nil }
        let screenRect = firstRect(
            forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil)
        guard screenRect.height > 0 else { return nil }
        let windowRect = window.convertFromScreen(screenRect)
        return convert(windowRect, from: nil)
    }

    /// 커서 라인의 텍스트 베이스라인 y (뷰 좌표).
    private func caretBaselineY() -> CGFloat? {
        guard let layoutManager, let textContainer else { return nil }
        let ns = string as NSString
        guard ns.length > 0 else { return nil }
        let caret = min(selectedRange().location, ns.length)
        layoutManager.ensureLayout(for: textContainer)

        // caret == length면 마지막 글리프의 라인을 기준으로 삼는다.
        let charIndex = min(caret, ns.length - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
        let fragment = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex, effectiveRange: nil)
        guard fragment.height > 0 else { return nil }
        var lineTop = fragment.minY
        var baselineOffset = layoutManager.location(forGlyphAt: glyphIndex).y

        // 문서 끝 개행 뒤(extra line fragment)에 커서가 있으면 그 라인 기준.
        // 앞 라인과 스타일이 다를 수 있어 높이 비율로 베이스라인을 보정한다.
        if caret == ns.length, ns.hasSuffix("\n") {
            let extra = layoutManager.extraLineFragmentRect
            guard extra.height > 0 else { return nil }
            baselineOffset *= extra.height / fragment.height
            lineTop = extra.minY
        }
        return textContainerOrigin.y + lineTop + baselineOffset
    }

    // MARK: 타자기 존 스크롤

    /// 커서를 드러낼 때 커서 **아래로 여백(gutter)까지** 함께 보이도록 스크롤한다 —
    /// 활성 줄이 창 바닥에 붙지 않고 화면 중하단의 편안한 위치에 park한다.
    ///
    /// 기본 `scrollRangeToVisible`은 커서를 뷰 하단 끝에 딱 맞춰 park시켜, 글이 한
    /// 화면을 넘기면 그 뒤로 줄곧 바닥을 긁으며 써진다(답답함 → 그만 쓰고 싶음).
    /// 여백은 스크롤 뷰의 `contentInsets.bottom`(=`WritingScrollView`가 뷰 높이에
    /// 비례해 잡아 둔 값)에서 읽는다 — 그래야 문서 끝에서도 그 인셋만큼 더 스크롤할
    /// 수 있어 마지막 줄까지 실제로 들어 올려진다. 인셋이 0이거나(타자기 존 미적용)
    /// 드래그 선택(length>0)·수식 편집 등은 기본 동작으로 넘긴다.
    override func scrollRangeToVisible(_ range: NSRange) {
        let gutter = enclosingScrollView?.contentInsets.bottom ?? 0
        guard range.length == 0, gutter > 0, let window else {
            super.scrollRangeToVisible(range)
            return
        }
        let screen = firstRect(forCharacterRange: range, actualRange: nil)
        guard screen.height > 0 else {
            super.scrollRangeToVisible(range)
            return
        }
        let inView = convert(window.convertFromScreen(screen), from: nil)
        _ = scrollToVisible(
            NSRect(
                x: inView.minX, y: inView.minY,
                width: max(1, inView.width), height: inView.height + gutter))
    }
}

// MARK: - 블록 장식 레이아웃 매니저

/// 불릿·번호·체크박스·인용 바·코드/수식 배경·구분선·이미지를 그린다.
/// 전부 text storage 밖 — 문서·undo·IME에 흔적이 없다.
final class MintLayoutManager: NSLayoutManager {

    private var view: BlockTextView? {
        firstTextView as? BlockTextView
    }

    /// 문단 블록 정보 — storage 속성에서 직접 읽는다 (nonisolated 드로잉용).
    /// 문서 끝 빈 문단은 뷰의 tailBlockInfo 스냅샷으로 보완한다.
    private func blockInfo(
        _ storage: NSTextStorage, in paragraph: NSRange, view: BlockTextView
    ) -> (block: MintBlock, checked: Bool, marker: String?) {
        if paragraph.location < storage.length {
            let attrs = storage.attributes(at: paragraph.location, effectiveRange: nil)
            let block = (attrs[.mintBlock] as? String).flatMap(MintBlock.init(rawValue:)) ?? .p
            return (block, attrs[.mintChecked] as? Bool ?? false, attrs[.mintMarker] as? String)
        }
        let snapshot = view.tailBlockInfo
        return (
            snapshot.block.flatMap(MintBlock.init(rawValue:)) ?? .p,
            snapshot.checked, snapshot.marker
        )
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let view, let storage = textStorage else { return }
        let theme = view.palette
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }

        // 코드 블록 배경 — 연속 블록은 하나의 라운드 사각형으로 병합 (디자인).
        var location = 0
        var codeStart: Int? = nil
        while location < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let block = blockInfo(storage, in: para, view: view).block
            if block == .code {
                if codeStart == nil { codeStart = para.location }
            } else {
                if let start = codeStart {
                    drawGroupBackground(
                        charRange: NSRange(location: start, length: para.location - start),
                        origin: origin, color: theme.codeBg)
                    codeStart = nil
                }
                if block == .math {
                    drawGroupBackground(charRange: para, origin: origin, color: theme.codeBg)
                }
            }
            location = para.upperBound
        }
        if let start = codeStart {
            drawGroupBackground(
                charRange: NSRange(location: start, length: ns.length - start),
                origin: origin, color: theme.codeBg)
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let view, let storage = textStorage, storage.length > 0 else { return }
        let theme = view.palette
        let ns = storage.string as NSString
        let shownChars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        var location = shownChars.location
        while location < min(shownChars.upperBound + 1, ns.length + 1) {
            let para = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
            defer { location = max(para.upperBound, location + 1) }
            let info = blockInfo(storage, in: para, view: view)
            guard info.block != .p else { continue }
            guard let rect = paragraphRect(charRange: para, origin: origin) else { continue }
            let firstLine = firstLineRect(charRange: para, origin: origin) ?? rect

            switch info.block {
            case .quote:
                theme.ink2.setFill()
                NSRect(x: rect.minX, y: rect.minY + 2, width: 3, height: rect.height - 4)
                    .fill()
            case .bullet:
                draw(marker: "•", color: theme.ink2, size: 20,
                     x: leftEdge(origin) + 8, line: firstLine,
                     baseline: firstBaseline(charRange: para, line: firstLine))
            case .number:
                // 본문(bodyFont serif 20)과 같은 크기·베이스라인으로 정렬.
                draw(marker: info.marker ?? "1.", color: theme.ink2, size: 20,
                     x: leftEdge(origin) + 6, line: firstLine,
                     baseline: firstBaseline(charRange: para, line: firstLine))
            case .todo:
                // 체크박스는 글자 캡하이트의 세로 중앙에 맞춘다.
                let centerY = firstBaseline(charRange: para, line: firstLine)
                    .map { $0 - MintFonts.serif(20).capHeight / 2 } ?? firstLine.midY
                drawCheckbox(
                    checked: info.checked, theme: theme,
                    at: NSPoint(x: leftEdge(origin) + 4, y: centerY - 8))
            case .divider:
                theme.sepStrong.setFill()
                NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: 1).fill()
            case .math:
                if let render = view.mathRenders.first(
                    where: { $0.range.location == para.location }) {
                    drawMath(render.image, in: rect)
                } else {
                    // 편집 중이거나 아직 파싱 안 되는 소스 — "수식" 태그만.
                    let tag = NSAttributedString(
                        string: "수식",
                        attributes: [
                            .font: MintFonts.ui(10), .foregroundColor: theme.ink3,
                            .kern: 0.6,
                        ])
                    tag.draw(at: NSPoint(x: rect.maxX - tag.size().width - 12, y: rect.minY + 6))
                }
            case .image:
                if let render = view.imageRenders.first(
                    where: { $0.range.location == para.location }) {
                    drawImage(
                        render.image, in: rect, display: render.size,
                        align: render.align, selected: render.selected, theme: theme)
                } else {
                    // 편집 중이거나 파일을 못 읽음 — "이미지" 태그만.
                    let tag = NSAttributedString(
                        string: "이미지",
                        attributes: [
                            .font: MintFonts.ui(10), .foregroundColor: theme.ink3,
                            .kern: 0.6,
                        ])
                    tag.draw(at: NSPoint(x: rect.maxX - tag.size().width - 12, y: rect.minY + 6))
                }
            default:
                break
            }
        }
    }

    // MARK: 헬퍼

    /// 문단 좌측 기준선(들여쓰기 이전의 텍스트 시작 x).
    private func leftEdge(_ origin: NSPoint) -> CGFloat {
        guard let container = textContainers.first else { return origin.x }
        return origin.x + container.lineFragmentPadding
    }

    private func paragraphRect(charRange: NSRange, origin: NSPoint) -> NSRect? {
        guard let container = textContainers.first else { return nil }
        let range = charRange
        // 빈 문단(개행만)도 rect가 나오도록 개행 포함 그대로 사용.
        if range.length == 0 {
            guard let extra = extraLineRect(origin: origin) else { return nil }
            return extra
        }
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        rect.size.width = container.size.width - container.lineFragmentPadding * 2
        rect.origin.x = origin.x + container.lineFragmentPadding
        return rect
    }

    private func firstLineRect(charRange: NSRange, origin: NSPoint) -> NSRect? {
        guard charRange.length > 0 else { return nil }
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var effective = NSRange()
        var rect = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &effective)
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }

    private func extraLineRect(origin: NSPoint) -> NSRect? {
        var rect = extraLineFragmentRect
        guard rect.height > 0 else { return nil }
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }

    /// 첫 라인의 텍스트 베이스라인 y — 프래그먼트 중앙이 아니라 글리프
    /// 베이스라인(실측) 기준으로 마커를 놓아야 본문 글자와 높이가 맞는다.
    private func firstBaseline(charRange: NSRange, line: NSRect) -> CGFloat? {
        guard charRange.length > 0 else { return nil }
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        return line.minY + location(forGlyphAt: glyphs.location).y
    }

    private func draw(
        marker: String, color: NSColor, size: CGFloat,
        x: CGFloat, line: NSRect, baseline: CGFloat?
    ) {
        let font = MintFonts.serif(size)
        let attr = NSAttributedString(
            string: marker,
            attributes: [.font: font, .foregroundColor: color])
        let y = baseline.map { $0 - font.ascender }
            ?? line.minY + (line.height - attr.size().height) / 2
        attr.draw(at: NSPoint(x: x, y: y))
    }

    /// 렌더된 LaTeX 이미지를 수식 문단 중앙에 그린다 (폭 초과 시 축소).
    private func drawMath(_ image: NSImage, in rect: NSRect) {
        var size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let maxWidth = max(40, rect.width - 32)
        if size.width > maxWidth {
            let scale = maxWidth / size.width
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }
        let target = NSRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
            width: size.width, height: size.height)
        image.draw(
            in: target, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil)
    }

    /// 렌더된 이미지를 지정 크기(`display`)·정렬(`align`)로 그린다. 객체 선택 시엔
    /// 선택 테두리도 두른다 (요구 3). display는 뷰의 `imageDisplaySize`가 계산한 값.
    private func drawImage(
        _ image: NSImage, in rect: NSRect, display: NSSize,
        align: String, selected: Bool, theme: MintTheme
    ) {
        guard display.width > 0, display.height > 0 else { return }
        // 줄 높이(=display 높이+여유)를 넘지 않게 안전하게 한 번 더 맞춘다.
        let box = rect.insetBy(dx: 8, dy: 6)
        let scale = min(box.width / display.width, box.height / display.height, 1)
        let size = NSSize(width: display.width * scale, height: display.height * scale)
        // 가로 정렬 — 좌/우는 살짝 안쪽(8pt)에서 시작한다.
        let x: CGFloat
        switch align {
        case "left": x = box.minX
        case "right": x = box.maxX - size.width
        default: x = rect.midX - size.width / 2
        }
        let target = NSRect(
            x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(
            in: target, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil)
        // 선택 테두리·핸들은 ImageBoxOverlay(별도 뷰)가 그린다.
    }

    private func drawCheckbox(checked: Bool, theme: MintTheme, at point: NSPoint) {
        let box = NSRect(x: point.x, y: point.y, width: 16, height: 16)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        if checked {
            theme.blue.setFill()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
            let check = NSAttributedString(
                string: "✓",
                attributes: [
                    .font: MintFonts.ui(10.5, weight: .bold), .foregroundColor: NSColor.white,
                ])
            let size = check.size()
            check.draw(at: NSPoint(
                x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        } else {
            theme.ink3.setStroke()
            path.stroke()
        }
    }

    private func drawGroupBackground(charRange: NSRange, origin: NSPoint, color: NSColor) {
        guard let container = textContainers.first, charRange.length > 0 else { return }
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        var rect = boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x = origin.x + container.lineFragmentPadding
        rect.origin.y += origin.y
        rect.size.width = container.size.width - container.lineFragmentPadding * 2
        rect = rect.insetBy(dx: 0, dy: -6)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
    }

}

// MARK: - LaTeX 렌더러 (SwiftMath)

/// 수식 블록의 LaTeX → NSImage 렌더 캐시. 메인 스레드에서만 접근한다
/// (편집 갱신·드로잉 모두 메인).
enum MathRenderer {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]

    /// LaTeX가 파싱되지 않으면 nil — 뷰는 소스 텍스트를 그대로 보여준다.
    static func image(latex: String, color: NSColor, fontSize: CGFloat) -> NSImage? {
        let key = "\(fontSize)|\(color.description)|\(latex)"
        if let hit = cache[key] { return hit }
        let renderer = MTMathImage(
            latex: latex, fontSize: fontSize, textColor: color, labelMode: .display)
        let (error, image) = renderer.asImage()
        guard error == nil, let image, image.size.width > 0 else { return nil }
        if cache.count > 256 { cache.removeAll() }  // 폭주 방지 — 단순 전체 비움
        cache[key] = image
        return image
    }
}
