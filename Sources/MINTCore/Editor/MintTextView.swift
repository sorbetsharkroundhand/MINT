import SwiftUI
import AppKit

/// 저널 본문을 편집하는 커스텀 텍스트 뷰 (M1 타이핑/바인딩 + M3 고스트 자동완성).
///
/// SwiftUI `TextEditor` 대신 `NSTextView`를 직접 래핑한다. 인라인 고스트
/// 텍스트는 커서/레이아웃/`markedText`(한글 IME 조합)를 직접 제어해야 하는데,
/// `TextEditor`로는 그 제어가 부족하기 때문이다 (PLAN §3).
///
/// M3 동작 (PLAN §5):
/// - 편집·커서 이벤트를 `CompletionController`로 전달 (조합 중 여부 포함).
/// - 제안은 커서 위치에 **회색 고스트**로 그린다 — text storage에는 절대 넣지
///   않으므로 본문·저장(`journal.md`)·undo·바인딩을 오염시키지 않는다 (PLAN §9-3).
/// - `Tab` = 수락(본문 삽입) / `Esc` = 거부 / 입력·커서 이동 = 자동 폐기.
public struct MintTextView: NSViewRepresentable {
    @Binding var text: String

    /// 자동완성 배선. nil이면 M1과 동일한 순수 에디터로 동작(프리뷰 등).
    private let controller: CompletionController?

    /// 본문 폰트. `ContentView` placeholder의 SwiftUI `.serif`(New York)와 맞춘다.
    private let font: NSFont

    public init(
        text: Binding<String>,
        controller: CompletionController? = nil,
        font: NSFont = MintTextView.defaultSerifFont(size: 16)
    ) {
        self._text = text
        self.controller = controller
        self.font = font
    }

    /// SwiftUI `.system(design: .serif)`에 대응하는 AppKit serif 폰트.
    static func defaultSerifFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // scrollableTextView()는 리시버 클래스로 인스턴스를 만든다 → GhostTextView.
        let scrollView = GhostTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? GhostTextView else {
            assertionFailure("GhostTextView.scrollableTextView()가 서브클래스를 만들지 않음")
            return scrollView
        }

        textView.delegate = context.coordinator

        // 저널 본문 — 서식 없는 순수 텍스트로 다룬다.
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 20, height: 24)

        // 스마트 치환류는 저널·코드성 입력을 방해하므로 끈다.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.string = text
        context.coordinator.attach(to: textView)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? GhostTextView else { return }
        // 외부(스토어 load 등)에서 text가 바뀐 경우에만 반영해
        // 편집 중 커서가 튀는 것을 막는다.
        if textView.string != text {
            textView.string = text
            // 프로그램적 교체는 delegate 알림이 없다 — 고스트를 직접 정리.
            textView.ghostText = nil
            controller?.dismissSuggestion()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// `NSTextView`의 편집·커서·키 이벤트를 SwiftUI 바인딩과
    /// `CompletionController`로 잇는다.
    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MintTextView

        init(_ parent: MintTextView) {
            self.parent = parent
        }

        /// makeNSView에서 호출 — 컨트롤러의 제안 변경을 고스트 렌더로 연결.
        func attach(to textView: GhostTextView) {
            parent.controller?.suggestionDidChange = { [weak textView] suggestion in
                textView?.ghostText = suggestion
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 한글 IME 조합 중(markedText)에도 string은 조합 결과를 담으므로
            // 그대로 바인딩에 반영한다. 자동완성 트리거만 게이트하면 된다.
            parent.text = textView.string
            forwardEditEvent(textView)
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let controller = parent.controller,
                let textView = notification.object as? NSTextView
            else { return }
            let range = textView.selectedRange()
            if range.length > 0 {
                // 드래그 선택 중에는 고스트를 유지할 이유가 없다.
                controller.dismissSuggestion()
            } else {
                controller.noteSelectionChange(caretLocation: range.location)
            }
        }

        public func textDidEndEditing(_ notification: Notification) {
            parent.controller?.dismissSuggestion()
        }

        /// `Tab` 수락 / `Esc` 거부 (PLAN §5).
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let controller = parent.controller else { return false }

            if commandSelector == #selector(NSStandardKeyBindingResponding.insertTab(_:)) {
                guard let accepted = controller.acceptSuggestion() else { return false }
                // 정규 편집 파이프라인으로 삽입 — undo·textDidChange·autosave가
                // 모두 정상 동작하고, 커서는 삽입 끝으로 이동한다.
                textView.insertText(accepted, replacementRange: textView.selectedRange())
                return true
            }

            // Esc는 cancelOperation:으로 오지만, NSTextView 기본 동작이
            // 완성 팝업(complete:)인 경로도 있어 둘 다 가로챈다.
            if commandSelector == #selector(NSStandardKeyBindingResponding.cancelOperation(_:))
                || commandSelector == #selector(NSStandardKeyBindingResponding.complete(_:)) {
                guard controller.hasSuggestion else { return false }
                controller.dismissSuggestion()
                return true
            }

            return false
        }

        // MARK: - 컨트롤러 이벤트 전달

        private func forwardEditEvent(_ textView: NSTextView) {
            guard let controller = parent.controller else { return }
            let storage = textView.string as NSString
            let caret = textView.selectedRange().location
            guard caret != NSNotFound, caret <= storage.length else { return }

            controller.noteEdit(
                prefix: Self.prefix(
                    of: storage, before: caret, limit: controller.settings.contextCharacters),
                caretLocation: caret,
                isComposing: textView.hasMarkedText(),  // IME 게이트 (PLAN §2)
                caretAtParagraphEnd: Self.isCaretAtParagraphEnd(storage, caret: caret)
            )
        }

        /// 커서 앞 컨텍스트 — 최대 `limit`자 (PLAN §4 "커서 앞 컨텍스트 추출").
        private static func prefix(of storage: NSString, before caret: Int, limit: Int) -> String {
            let head = storage.substring(to: caret)
            return String(head.suffix(limit))
        }

        /// 커서 뒤~문단 끝이 공백뿐인가.
        /// 고스트는 문단 끝에서만 띄운다 — 본문과 겹쳐 그리지 않기 위한 MVP
        /// 단순화 (docs/m3-ghost-text.md 결정 사항).
        private static func isCaretAtParagraphEnd(_ storage: NSString, caret: Int) -> Bool {
            let paragraph = storage.paragraphRange(for: NSRange(location: caret, length: 0))
            guard paragraph.upperBound > caret else { return true }
            let tail = storage.substring(
                with: NSRange(location: caret, length: paragraph.upperBound - caret))
            return tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 회색 인라인 고스트를 커서 위치에 그리는 `NSTextView` (M3).
///
/// 고스트는 text storage **밖**에서 `draw(_:)`로만 그린다 — 커서는 항상 고스트
/// 앞에 남고, 편집 파이프라인(undo·delegate·바인딩·저장)에 흔적이 없다 (PLAN §9-3).
/// 컨트롤러가 문단 끝에서만 제안을 발행하므로 한 줄 그리기로 충분하다.
final class GhostTextView: NSTextView {
    /// 현재 고스트 텍스트. nil/빈 문자열이면 그리지 않는다.
    var ghostText: String? {
        didSet {
            guard ghostText != oldValue else { return }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ghost = ghostText, !ghost.isEmpty,
            !hasMarkedText(),  // 조합 중에는 그리지 않는다 (컨트롤러 게이트의 이중 안전망)
            selectedRange().length == 0,
            let caretRect = caretRectInView()
        else { return }

        let ghostFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ghostFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        // 본문과 같은 폰트로 커서 라인 상단에 맞춰 그리면 베이스라인이 일치한다.
        NSAttributedString(string: ghost, attributes: attributes)
            .draw(at: NSPoint(x: caretRect.maxX, y: caretRect.minY))
    }

    /// 커서 사각형(뷰 좌표). IME 후보창 배치에 쓰이는 `firstRect(forCharacterRange:)`
    /// 경로를 재사용한다 — 빈 문서/문서 끝/개행 뒤 등 에지 케이스를 AppKit이 처리.
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
