import AppKit
import SwiftMath
import SwiftUI

/// Notion식 블록 에디터 (에디터 v3 — 디자인 완전 이식).
///
/// 웹 목업의 세 축을 NSTextView(TextKit 1)로 옮긴 것:
/// - `transformMarkdown` → 마커(`# `, `> `, `- ` …)를 입력 즉시 **소비**하고
///   문단에 블록 속성(`.mintBlock`)을 부여한다. 화면에 마커는 남지 않는다.
/// - `serialize`/`buildDOM` → 저장은 항상 순수 마크다운. 로드 시 마커를 파싱해
///   블록으로 복원한다. 파일 포맷은 이전과 완전 호환.
/// - 블록 장식(불릿·번호·체크박스·인용 바·코드/수식 배경·구분선·커서 글로우)은
///   `MintLayoutManager`가 그린다 — text storage 밖이라 undo·IME에 무해.
///
/// 고스트 텍스트(M3)는 기존 방식 그대로: storage 밖에서 `draw(_:)`로만 그린다.
public struct MintBlockEditor: NSViewRepresentable {
    @Binding var text: String

    private let controller: CompletionController?
    private let theme: MintTheme
    /// 커서 이동 알림 — 창 좌표(top-left 원점)의 커서 중심점. 포커스를 잃으면 nil.
    /// ContentView가 창 전체 글로우 레이어를 이 점으로 움직인다 (디자인 caret glow).
    private let onCaretMove: ((CGPoint?) -> Void)?

    public init(
        text: Binding<String>,
        controller: CompletionController? = nil,
        theme: MintTheme = .light,
        onCaretMove: ((CGPoint?) -> Void)? = nil
    ) {
        self._text = text
        self.controller = controller
        self.theme = theme
        self.onCaretMove = onCaretMove
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
        textView.insertionPointColor = theme.blue

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.palette = theme
        textView.load(markdown: text)
        context.coordinator.lastSyncedText = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        // 최신 onCaretMove 클로저는 coordinator.parent를 통해 전달된다.
        textView.onCaretMove = { [weak coordinator = context.coordinator] point in
            coordinator?.parent.onCaretMove?(point)
        }
        // 스크롤 시에도 글로우가 커서를 따라가도록.
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main
        ) { [weak textView] _ in
            MainActor.assumeIsolated { textView?.emitCaretPosition() }
        }

        context.coordinator.attach(to: textView)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? BlockTextView else { return }

        if textView.palette.ink != theme.ink {
            textView.palette = theme
            textView.insertionPointColor = theme.blue
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
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MintBlockEditor
        nonisolated(unsafe) var scrollObserver: NSObjectProtocol?
        /// 마지막으로 바인딩과 동기화된 마크다운 — updateNSView의 reload 기준.
        var lastSyncedText = ""

        init(_ parent: MintBlockEditor) {
            self.parent = parent
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
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
            textView.emitCaretPosition()
            // 커서가 수식 문단에 들어오면 소스, 나가면 렌더로 전환.
            textView.refreshMathPresentation()
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
            let allowed = ![.code, .math, .divider].contains(block)

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

// MARK: - 블록 모델

/// 문단 블록 타입 (디자인의 data-md와 1:1).
enum MintBlock: String {
    case p, h1, h2, h3, quote, bullet, number, todo, code, math, divider
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

    /// 현재 고스트 텍스트. nil/빈 문자열이면 그리지 않는다.
    var ghostText: String? {
        didSet {
            guard ghostText != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 마커 소비/스타일 적용 중 재진입 방지.
    private var isTransforming = false

    /// 수식 렌더 폰트 크기 — 본문(serif 20)과 맞춘다.
    let mathFontSize: CGFloat = 20

    /// 현재 렌더 모드인 수식 문단들 (문단 range + 렌더된 LaTeX 이미지).
    /// `refreshMathPresentation()`이 갱신하고 레이아웃 매니저가 그린다.
    nonisolated(unsafe) private(set) var mathRenders: [(range: NSRange, image: NSImage)] = []

    /// 커서 이동 알림 (창 좌표 top-left 원점). MintBlockEditor가 연결한다.
    var onCaretMove: ((CGPoint?) -> Void)?

    /// 현재 커서 중심점을 창 좌표(top-left 원점)로 발행한다. 포커스 밖이면 nil.
    func emitCaretPosition() {
        guard let window, window.firstResponder === self,
            selectedRange().length == 0,
            let contentView = window.contentView
        else {
            onCaretMove?(nil)
            return
        }
        let caret = selectedRange().location
        guard caret != NSNotFound else {
            onCaretMove?(nil)
            return
        }
        let screenRect = firstRect(
            forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil)
        guard screenRect.height > 0 else {
            onCaretMove?(nil)
            return
        }
        let baseRect = window.convertFromScreen(screenRect)
        // AppKit 창 좌표는 좌하단 원점 — SwiftUI(.global)의 좌상단 원점으로 뒤집는다.
        onCaretMove?(
            CGPoint(x: baseRect.midX, y: contentView.bounds.height - baseRect.midY))
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            DispatchQueue.main.async { [weak self] in
                self?.emitCaretPosition()
                // 포커스가 돌아오면 커서 문단의 수식을 소스 모드로 되돌린다.
                self?.refreshMathPresentation()
            }
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onCaretMove?(nil)
            // 포커스를 잃으면 커서가 수식 문단에 남아 있어도 렌더로 전환.
            DispatchQueue.main.async { [weak self] in self?.refreshMathPresentation() }
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
            case .code, .math, .divider:
                // 코드·수식엔 인라인 서식이 없다 — 원문 그대로.
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
        setSelectedRange(NSRange(location: storage.length, length: 0))
        syncTypingAttributes()
        isTransforming = false
        hideSelectionToolbar()
        refreshMathPresentation()
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
        guard let storage = textStorage, ![MintBlock.code, .math, .divider].contains(block)
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
            // setAttributes는 인라인 서식 키까지 지운다 — 코드·수식·구분선이
            // 아니면 보존했다가 되살린 뒤 폰트·색을 다시 조립한다.
            let keepInline = ![MintBlock.code, .math, .divider].contains(block)
            let preserved = keepInline ? inlineSnapshot(in: paragraph) : []
            storage.setAttributes(attrs, range: paragraph)
            for (range, inline) in preserved {
                storage.addAttributes(inline, range: range)
            }
            decorateInline(in: paragraph)
            applyStoredAlignment(base: attrs, in: paragraph)
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
        refreshMathPresentation()
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
            let base = attrs[.font] as? NSFont ?? bodyFont
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

    // MARK: 스타일 (디자인 CSS와 1:1)

    func styleAttributes(for block: MintBlock, checked: Bool) -> [NSAttributedString.Key: Any] {
        let t = palette
        var font = bodyFont
        var color = t.ink
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = 1.5  // 디자인 line-height 1.95(웹 박스 기준) 근사

        switch block {
        case .p:
            break
        case .h1:
            font = MintFonts.serif(31, weight: .bold)
            ps.lineHeightMultiple = 1.2
            ps.paragraphSpacingBefore = 16
            ps.paragraphSpacing = 4
        case .h2:
            font = MintFonts.serif(25, weight: .semibold)
            ps.lineHeightMultiple = 1.25
            ps.paragraphSpacingBefore = 12
            ps.paragraphSpacing = 2
        case .h3:
            font = MintFonts.serif(21, weight: .semibold)
            ps.lineHeightMultiple = 1.3
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
            ps.lineHeightMultiple = 1.5
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
        refreshMathPresentation()
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
        guard ![MintBlock.code, .math, .divider].contains(info.block) else { return }
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
        refreshMathPresentation()
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
        case .h1, .h2, .h3, .quote, .math, .divider:
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
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: 수식 LaTeX 렌더

    /// 수식 문단 표시 갱신 — 커서가 밖에 있고 LaTeX가 파싱되면 소스 글자를
    /// 투명 처리(temporary attribute — storage·undo·저장에 무해)하고, 레이아웃
    /// 매니저가 그 자리에 렌더된 수식을 그린다. 커서가 들어오면 소스로 돌아온다.
    func refreshMathPresentation() {
        guard let layoutManager, let storage = textStorage else { return }
        layoutManager.removeTemporaryAttribute(
            .foregroundColor,
            forCharacterRange: NSRange(location: 0, length: storage.length))
        var renders: [(range: NSRange, image: NSImage)] = []
        let ns = string as NSString
        let sel = selectedRange()
        // 포커스가 사이드바 등 밖에 있으면 커서가 문단에 남아 있어도 렌더한다 —
        // 수식이 문서 마지막 문단일 때 소스가 계속 보이는 문제 방지.
        let focused = window?.firstResponder === self
        var location = 0
        while location < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: location, length: 0))
            defer { location = para.upperBound }
            guard blockInfo(in: para).block == .math else { continue }

            let content = paragraphContent(para)
            let contentEnd = para.location + (content as NSString).length
            // 커서/선택이 문단에 닿아 있으면 편집 모드 — 소스를 보여준다.
            let editing =
                focused
                && ((sel.length == 0 && sel.location >= para.location
                    && sel.location <= contentEnd)
                    || (sel.length > 0 && NSIntersectionRange(sel, para).length > 0))
            let latex = content.trimmingCharacters(in: .whitespaces)
            guard !latex.isEmpty, !editing,
                let image = MathRenderer.image(
                    latex: latex, color: palette.ink, fontSize: mathFontSize)
            else {
                // 소스 모드 — 렌더 때 키워 둔 줄 높이를 기본 스타일로 되돌린다.
                updateMathLineHeight(nil, in: para)
                continue
            }

            renders.append((para, image))
            // 블록 높이가 수식을 따라가게 — 분수·시그마처럼 세로로 큰 수식이
            // 배경 박스 밖으로 넘치지 않는다.
            updateMathLineHeight(displayHeight(of: image), in: para)
            layoutManager.addTemporaryAttribute(
                .foregroundColor, value: NSColor.clear, forCharacterRange: para)
        }
        mathRenders = renders
        needsDisplay = true
    }

    /// drawMath와 같은 규칙(폭 초과 시 축소)으로 실제 그려질 이미지 높이를 구한다.
    private func displayHeight(of image: NSImage) -> CGFloat {
        guard let container = textContainer, image.size.width > 0 else {
            return image.size.height
        }
        let rectWidth = container.size.width - container.lineFragmentPadding * 2
        let maxWidth = max(40, rectWidth - 32)
        let scale = min(1, maxWidth / image.size.width)
        return image.size.height * scale
    }

    /// 수식 문단의 줄 높이를 렌더 이미지에 맞춘다 (nil이면 기본 스타일로 복원).
    /// 표시 전용 속성 변경 — 저장 텍스트·undo에 흔적이 없다.
    private func updateMathLineHeight(_ imageHeight: CGFloat?, in paragraph: NSRange) {
        guard let storage = textStorage, paragraph.length > 0,
            paragraph.location < storage.length,
            let ps = (styleAttributes(for: .math, checked: false)[.paragraphStyle]
                as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
        else { return }
        if let imageHeight {
            // 위아래 여유 12pt — 배경 박스(-6 inset)와 시각적으로 맞는 값.
            ps.minimumLineHeight = imageHeight + 12
        }
        let current =
            storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
            as? NSParagraphStyle
        guard current?.minimumLineHeight != ps.minimumLineHeight else { return }
        storage.addAttribute(.paragraphStyle, value: ps, range: paragraph)
    }

    /// 폭이 바뀌면 수식 축소 배율이 달라진다 — 줄 높이를 다시 맞춘다.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, !mathRenders.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.refreshMathPresentation() }
        }
    }

    // MARK: 서식 툴바 (선택 위 플로팅)

    private var toolbarHost: NSHostingView<SelectionToolbarView>?
    private var toolbarShowTask: Task<Void, Never>?

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
        guard sel.location < storage.length else { return state }
        let attrs = storage.attributes(at: sel.location, effectiveRange: nil)
        state.bold = attrs[.mintBold] as? Bool == true
        state.italic = attrs[.mintItalic] as? Bool == true
        state.code = attrs[.mintCode] as? Bool == true
        state.align = attrs[.mintAlign] as? String
        state.colorHex = attrs[.mintColor] as? String
        return state
    }

    /// 툴바 액션 실행 — 끝나면 포커스를 에디터로 되돌리고 하이라이트를 갱신한다.
    func perform(_ action: SelectionToolbarAction) {
        switch action {
        case .toggleBold: toggleInlineStyle(.mintBold)
        case .toggleItalic: toggleInlineStyle(.mintItalic)
        case .toggleCode: toggleInlineStyle(.mintCode)
        case .color(let hex): applyInlineColor(hex)
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
        refreshMathPresentation()
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

    /// ⌘B / ⌘I — 선택이 있을 때만 서식 토글로 소비한다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            selectedRange().length > 0 {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b":
                toggleInlineStyle(.mintBold)
                return true
            case "i":
                toggleInlineStyle(.mintItalic)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: 고스트 렌더 (M3 그대로)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ghost = ghostText, !ghost.isEmpty,
            !hasMarkedText(),
            selectedRange().length == 0,
            let caretRect = caretRectInView()
        else { return }

        // 커서 문단의 실제 폰트로 그린다 — 제목 줄에서도 크기가 맞는다.
        let font = (typingAttributes[.font] as? NSFont) ?? bodyFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.ghost,
        ]
        // lineHeightMultiple(1.5)의 여백은 라인 프래그먼트 위쪽에 붙는다 —
        // 프래그먼트 top(caretRect.minY)이 아니라 본문 글리프와 같은
        // 베이스라인에 맞춰야 실제 글자 높이와 일치한다.
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
}

// MARK: - 블록 장식 레이아웃 매니저

/// 불릿·번호·체크박스·인용 바·코드/수식 배경·구분선·커서 글로우를 그린다.
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

    /// 첫 라인의 텍스트 베이스라인 y — lineHeightMultiple(1.5)의 여백이 라인
    /// 위쪽에 붙으므로, 프래그먼트 중앙이 아니라 글리프 베이스라인 기준으로
    /// 마커를 놓아야 본문 글자와 높이가 맞는다.
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
