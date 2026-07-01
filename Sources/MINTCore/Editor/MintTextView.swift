import SwiftUI
import AppKit

/// 저널 본문을 편집하는 커스텀 텍스트 뷰(M1).
///
/// SwiftUI `TextEditor` 대신 `NSTextView`를 직접 래핑한다. M3의 인라인
/// 고스트 텍스트 자동완성은 커서/레이아웃/`markedText`(한글 IME 조합)를
/// 직접 제어해야 하는데, `TextEditor`로는 그 제어가 부족하기 때문이다.
///
/// M1 범위: 순수 타이핑 + `text` 양방향 바인딩. 자동완성·IME 게이트는 없다.
/// (M3에서 이 파일에 고스트 렌더/`Tab` 수락/`hasMarkedText()` 게이트를 얹는다.)
public struct MintTextView: NSViewRepresentable {
    @Binding var text: String

    /// 본문 폰트. `ContentView` placeholder의 SwiftUI `.serif`(New York)와 맞춘다.
    private let font: NSFont

    public init(text: Binding<String>, font: NSFont = MintTextView.defaultSerifFont(size: 16)) {
        self._text = text
        self.font = font
    }

    /// SwiftUI `.system(design: .serif)`에 대응하는 AppKit serif 폰트.
    static func defaultSerifFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
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
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 외부(스토어 load 등)에서 text가 바뀐 경우에만 반영해
        // 편집 중 커서가 튀는 것을 막는다.
        if textView.string != text {
            textView.string = text
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// `NSTextView`의 편집 이벤트를 SwiftUI 바인딩으로 되돌린다.
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MintTextView

        init(_ parent: MintTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 한글 IME 조합 중(markedText)에도 string은 조합 결과를 담으므로
            // M1에서는 그대로 바인딩에 반영한다. (M3의 자동완성 트리거만
            // hasMarkedText()로 게이트하면 된다.)
            parent.text = textView.string
        }
    }
}
