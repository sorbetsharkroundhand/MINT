import AppKit
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
        if ok { DispatchQueue.main.async { [weak self] in self?.emitCaretPosition() } }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onCaretMove?(nil) }
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
            let suffix = index < lines.count - 1 ? "\n" : ""
            result.append(NSAttributedString(string: line + suffix, attributes: attrs))
        }
        storage.setAttributedString(result)
        setSelectedRange(NSRange(location: storage.length, length: 0))
        syncTypingAttributes()
        isTransforming = false
        needsDisplay = true
    }

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
            let text = paragraphContent(para)
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
                default: out.append(text)
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
            storage.setAttributes(attrs, range: paragraph)
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
            typingAttributes = storage.attributes(at: para.location, effectiveRange: nil)
        }
        updateTailSnapshot()
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
        guard !isTransforming, !hasMarkedText() else { return }
        transformMarkerIfNeeded()
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

    // MARK: 고스트 렌더 (M3 그대로)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ghost = ghostText, !ghost.isEmpty,
            !hasMarkedText(),
            selectedRange().length == 0,
            let caretRect = caretRectInView()
        else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: palette.ghost,
        ]
        NSAttributedString(string: ghost, attributes: attributes)
            .draw(at: NSPoint(x: caretRect.maxX, y: caretRect.minY))
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
                     at: NSPoint(x: leftEdge(origin) + 8, y: firstLine.minY), line: firstLine)
            case .number:
                draw(marker: info.marker ?? "1.", color: theme.ink2, size: 17,
                     at: NSPoint(x: leftEdge(origin) + 6, y: firstLine.minY), line: firstLine)
            case .todo:
                drawCheckbox(
                    checked: info.checked, theme: theme,
                    at: NSPoint(x: leftEdge(origin) + 4, y: firstLine.midY - 8))
            case .divider:
                theme.sepStrong.setFill()
                NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: 1).fill()
            case .math:
                let tag = NSAttributedString(
                    string: "수식",
                    attributes: [
                        .font: MintFonts.ui(10), .foregroundColor: theme.ink3,
                        .kern: 0.6,
                    ])
                tag.draw(at: NSPoint(x: rect.maxX - tag.size().width - 12, y: rect.minY + 6))
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

    private func draw(marker: String, color: NSColor, size: CGFloat, at point: NSPoint, line: NSRect) {
        let attr = NSAttributedString(
            string: marker,
            attributes: [.font: MintFonts.serif(size), .foregroundColor: color])
        let markerSize = attr.size()
        attr.draw(at: NSPoint(x: point.x, y: line.minY + (line.height - markerSize.height) / 2))
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
