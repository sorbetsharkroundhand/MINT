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
    /// 문단 정렬 "center"/"right" — 저장은 `<p align="…">` 래퍼 (.p 문단만 직렬화).
    static let mintAlign = NSAttributedString.Key("mint.align")
}

/// 인라인 마크다운 ↔ mint 인라인 속성 변환기 (파싱·직렬화 왕복 대칭).
enum InlineMarkdown {

    /// 인라인 서식 키 전체 — 블록 재스타일 시 보존 대상.
    static let inlineKeys: [NSAttributedString.Key] = [
        .mintBold, .mintItalic, .mintCode, .mintColor, .mintAlign,
    ]

    typealias Segment = (text: String, attrs: [NSAttributedString.Key: Any])

    // 마커 패턴. `(?<!\*)`/`(?!\*)` — `**굵게**` 진행 중에 `*기울임*`이
    // 먼저 오발동하지 않게 이웃 별표를 배제한다.
    private static let fontTag = regex(##"<font color="#([0-9A-Fa-f]{6})">(.*?)</font>"##)
    private static let codeSpan = regex(#"`([^`\n]+)`"#)
    private static let boldItalic = regex(#"(?<!\*)\*\*\*([^*\n]+)\*\*\*(?!\*)"#)
    private static let bold = regex(#"(?<!\*)\*\*([^*\n]+)\*\*(?!\*)"#)
    private static let italic = regex(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // 패턴은 전부 정적 리터럴 — 실패는 프로그래머 오류.
        try! NSRegularExpression(pattern: pattern)
    }

    private enum Kind { case color, code, boldItalic, bold, italic }

    /// 타이핑 변환용 규칙 — 커서 바로 앞에서 완성된 마커만 소비한다.
    /// 순서 중요: `***`가 `**`보다 먼저 매칭돼야 한다.
    /// (에디터 전용이라 MainActor — [Key: Any]가 Sendable이 아니다.)
    @MainActor
    static let typingRules: [(pattern: NSRegularExpression, attrs: [NSAttributedString.Key: Any])] = [
        (boldItalic, [.mintBold: true, .mintItalic: true]),
        (bold, [.mintBold: true]),
        (italic, [.mintItalic: true]),
        (codeSpan, [.mintCode: true]),
    ]

    // MARK: 파싱 (마크다운 → 세그먼트)

    /// 한 줄을 마커 없이 (텍스트, 인라인 속성) 세그먼트로 나눈다.
    static func parse(_ text: String) -> [Segment] {
        parse(text, inherited: [:])
    }

    private static func parse(
        _ text: String, inherited: [NSAttributedString.Key: Any]
    ) -> [Segment] {
        var segments: [Segment] = []
        let ns = text as NSString
        var location = 0
        while location < ns.length {
            let search = NSRange(location: location, length: ns.length - location)
            // 가장 앞에서 시작하는 마커 (동률이면 font > code > *** > ** > * 우선).
            var best: (match: NSTextCheckingResult, kind: Kind)?
            let candidates: [(NSRegularExpression, Kind)] = [
                (fontTag, .color), (codeSpan, .code),
                (boldItalic, .boldItalic), (bold, .bold), (italic, .italic),
            ]
            for (rx, kind) in candidates {
                guard let match = rx.firstMatch(in: text, range: search) else { continue }
                if best == nil || match.range.location < best!.match.range.location {
                    best = (match, kind)
                }
            }
            guard let (match, kind) = best else {
                segments.append((ns.substring(from: location), inherited))
                break
            }
            if match.range.location > location {
                segments.append(
                    (ns.substring(
                        with: NSRange(
                            location: location, length: match.range.location - location)),
                     inherited))
            }
            switch kind {
            case .color:
                // 색 안에 굵게 등이 중첩될 수 있다 — 내부를 재귀 파싱.
                var attrs = inherited
                attrs[.mintColor] = ns.substring(with: match.range(at: 1)).uppercased()
                segments += parse(ns.substring(with: match.range(at: 2)), inherited: attrs)
            case .code:
                var attrs = inherited
                attrs[.mintCode] = true
                segments.append((ns.substring(with: match.range(at: 1)), attrs))
            case .boldItalic:
                var attrs = inherited
                attrs[.mintBold] = true
                attrs[.mintItalic] = true
                segments.append((ns.substring(with: match.range(at: 1)), attrs))
            case .bold:
                var attrs = inherited
                attrs[.mintBold] = true
                segments.append((ns.substring(with: match.range(at: 1)), attrs))
            case .italic:
                var attrs = inherited
                attrs[.mintItalic] = true
                segments.append((ns.substring(with: match.range(at: 1)), attrs))
            }
            location = match.range.upperBound
        }
        return segments
    }

    // MARK: 직렬화 (속성 → 마크다운)

    /// 범위의 인라인 속성 런을 마커로 감싸 마크다운 한 줄로 되돌린다.
    static func serialize(_ storage: NSAttributedString, in range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var out = ""
        storage.enumerateAttributes(in: range, options: []) { attrs, run, _ in
            var text = (storage.string as NSString).substring(with: run)
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
            if let hex = attrs[.mintColor] as? String {
                text = "<font color=\"#\(hex)\">\(text)</font>"
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
