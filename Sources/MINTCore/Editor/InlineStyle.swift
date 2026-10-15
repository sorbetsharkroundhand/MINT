import AppKit

/// 인라인 서식 속성 키 (서식 툴바 · `**…**` 타이핑 변환).
///
/// 폰트·색 같은 실제 표시 속성은 이 키에서 파생돼 `decorateInline`이 조립한다.
/// 저장은 항상 마크다운 마커(`**` `*` `` ` `` `<font>` `<p align>`)로 되돌린다 —
/// 파일 포맷은 순수 텍스트를 유지하고, 속성은 로드 때 다시 파싱된다.
extension NSAttributedString.Key {
    static let mintBold = NSAttributedString.Key("mint.bold")
    static let mintItalic = NSAttributedString.Key("mint.italic")
    static let mintCode = NSAttributedString.Key("mint.code")
    /// 글자색 hex ("FF453A") — 저장은 `<font color="#…">` 태그.
    static let mintColor = NSAttributedString.Key("mint.color")
    /// 글자 크기 pt (Double) — 저장은 `<font size="…">` 태그. 블록 기본 크기와
    /// 같으면 속성을 두지 않는다 (서식 툴바 크기 조절).
    static let mintFontSize = NSAttributedString.Key("mint.fontSize")
    /// 문단 정렬 "center"/"right" — 저장은 `<p align="…">` 래퍼 (.p 문단만 직렬화).
    static let mintAlign = NSAttributedString.Key("mint.align")
    /// 문단별 줄 간격 pt (Double) — 선택 줄에 한해 조절 (요구 4). 표시 전용이라
    /// 마크다운으로는 저장되지 않고, 재로드 시 전역 설정값으로 돌아간다.
    static let mintLineSpacing = NSAttributedString.Key("mint.lineSpacing")
}

/// 인라인 마크다운 ↔ mint 인라인 속성 변환기 (파싱·직렬화 왕복 대칭).
enum InlineMarkdown {

    /// 인라인 서식 키 전체 — 블록 재스타일 시 보존 대상.
    static let inlineKeys: [NSAttributedString.Key] = [
        .mintBold, .mintItalic, .mintCode, .mintColor, .mintFontSize, .mintAlign,
        .mintLineSpacing,
    ]

    typealias Segment = (text: String, attrs: [NSAttributedString.Key: Any])

    /// Marker priority and nested-font semantics are shared with prose projection.
    @MainActor
    static let typingRules: [(pattern: NSRegularExpression, attrs: [NSAttributedString.Key: Any])] = [
        (MarkdownInlineScanner.boldItalic, [.mintBold: true, .mintItalic: true]),
        (MarkdownInlineScanner.bold, [.mintBold: true]),
        (MarkdownInlineScanner.italic, [.mintItalic: true]),
        (MarkdownInlineScanner.code, [.mintCode: true]),
    ]

    static func parse(_ text: String) -> [Segment] {
        MarkdownInlineScanner.scan(text).map { span in
            var attrs: [NSAttributedString.Key: Any] = [:]
            if span.style.bold { attrs[.mintBold] = true }
            if span.style.italic { attrs[.mintItalic] = true }
            if span.style.code { attrs[.mintCode] = true }
            if let color = span.style.color { attrs[.mintColor] = color }
            if let size = span.style.fontSize { attrs[.mintFontSize] = size }
            return (span.text, attrs)
        }
    }

    // MARK: 직렬화 (속성 → 마크다운)

    /// 범위의 인라인 속성 런을 마커로 감싸 마크다운 한 줄로 되돌린다.
    /// 인라인 수식 원자(attachment)는 `$latex$`로 — 굵게 등 다른 마커로
    /// 감싸지 않는다 (원자는 서식의 대상이 아니라 객체다, 이슈 #20).
    static func serialize(_ storage: NSAttributedString, in range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var out = ""
        storage.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            var text = (storage.string as NSString).substring(with: run)
            if let atom = attrs[.attachment] as? MathAtomAttachment {
                out += "$\(atom.latex)$"
                return
            }
            if attrs[.mintCode] as? Bool == true {
                text = "`\(text)`"
            } else {
                let isBold = attrs[.mintBold] as? Bool == true
                let isItalic = attrs[.mintItalic] as? Bool == true
                if isBold && isItalic {
                    text = "***\(text)***"
                } else if isBold {
                    text = "**\(text)**"
                } else if isItalic {
                    text = "*\(text)*"
                }
            }
            var tagAttrs: [String] = []
            if let hex = attrs[.mintColor] as? String {
                tagAttrs.append("color=\"#\(hex)\"")
            }
            if let size = attrs[.mintFontSize] as? Double {
                tagAttrs.append("size=\"\(String(format: "%g", size))\"")
            }
            if !tagAttrs.isEmpty {
                text = "<font \(tagAttrs.joined(separator: " "))>\(text)</font>"
            }
            out += text
        }
        return out
    }
}

extension NSColor {
    /// "FF453A" 형태의 인라인 색상 hex → NSColor.
    convenience init?(inlineHex: String) {
        var value: UInt64 = 0
        guard inlineHex.count == 6, Scanner(string: inlineHex).scanHexInt64(&value) else {
            return nil
        }
        self.init(hex: UInt32(value))
    }
}
