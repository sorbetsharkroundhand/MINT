import Foundation

/// The editor's inline grammar, with original UTF-16 spans and no AppKit attributes.
enum MarkdownInlineScanner {
    struct Style: Sendable, Equatable {
        var bold = false, italic = false, code = false
        var color: String?
        var fontSize: Double?
    }
    struct Span: Sendable {
        let text: String
        let sourceRange: NSRange
        let style: Style
    }
    // U+2028 stays inside a formatted paragraph; only Enter (LF) separates it.
    static let fontTag = regex(##"<font ((?:color="#[0-9A-Fa-f]{6}"|size="[0-9.]+")(?: (?:color="#[0-9A-Fa-f]{6}"|size="[0-9.]+"))*)>([^\n]*?)</font>"##)
    private static let fontColor = regex(##"color="#([0-9A-Fa-f]{6})""##)
    private static let fontSize = regex(#"size="([0-9.]+)""#)
    static let code = regex(#"`([^`\n]+)`"#)
    static let boldItalic = regex(#"(?<!\*)\*\*\*([^*\n]+)\*\*\*(?!\*)"#)
    static let bold = regex(#"(?<!\*)\*\*([^*\n]+)\*\*(?!\*)"#)
    static let italic = regex(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private enum Kind { case font, code, boldItalic, bold, italic }
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    static func scan(_ text: String) -> [Span] { scan(text, inherited: Style(), offset: 0) }

    private static func scan(_ text: String, inherited: Style, offset: Int) -> [Span] {
        let ns = text as NSString
        var location = 0, spans: [Span] = []
        func append(_ range: NSRange, _ style: Style) {
            spans.append(Span(text: ns.substring(with: range),
                              sourceRange: NSRange(location: offset + range.location, length: range.length), style: style))
        }
        while location < ns.length {
            let search = NSRange(location: location, length: ns.length - location)
            var best: (NSTextCheckingResult, Kind)?
            for (rx, kind) in [(fontTag, Kind.font), (code, .code), (boldItalic, .boldItalic), (bold, .bold), (italic, .italic)] {
                if let match = rx.firstMatch(in: text, range: search),
                   best == nil || match.range.location < best!.0.range.location { best = (match, kind) }
            }
            guard let (match, kind) = best else { append(search, inherited); break }
            if match.range.location > location {
                append(NSRange(location: location, length: match.range.location - location), inherited)
            }
            var style = inherited
            switch kind {
            case .font:
                let attributes = ns.substring(with: match.range(at: 1)) as NSString
                let all = NSRange(location: 0, length: attributes.length)
                if let color = fontColor.firstMatch(in: attributes as String, range: all) {
                    style.color = attributes.substring(with: color.range(at: 1)).uppercased()
                }
                if let size = fontSize.firstMatch(in: attributes as String, range: all),
                   let value = Double(attributes.substring(with: size.range(at: 1))) { style.fontSize = value }
                let body = match.range(at: 2)
                spans += scan(ns.substring(with: body), inherited: style, offset: offset + body.location)
            case .code: style.code = true; append(match.range(at: 1), style)
            case .boldItalic: style.bold = true; style.italic = true; append(match.range(at: 1), style)
            case .bold: style.bold = true; append(match.range(at: 1), style)
            case .italic: style.italic = true; append(match.range(at: 1), style)
            }
            location = match.range.upperBound
        }
        return spans
    }
}
