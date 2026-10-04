import Foundation

/// Experimental strategies; the existing strategy remains the release default.
public enum GhostContextMode: String, CaseIterable, Codable, Sendable {
    case raw = "A"
    case rawWithNameAnchor = "B"
    case current = "C"

    public var label: String {
        switch self {
        case .raw: "A · 원문만"
        case .rawWithNameAnchor: "B · 원문과 이전 이름 언급"
        case .current: "C · 현재 방식"
        }
    }
}

extension ContextAssembler {
    static func assembleRaw(
        prefix: String, prefixStartUTF16: Int, style: PromptStyle,
        mode: GhostContextMode, counter: TokenCounter?, budget: Int?
    ) -> (prompt: AssembledPrompt, report: ContextReport) {
        var window = String(prefix.suffix(12_000))
        func prompt(_ text: String) -> AssembledPrompt {
            switch style {
            case .continuation: .continuation(text)
            case .instruct: .instruct(system: instructSystem, user: instructUser(prefix: text))
            }
        }
        func cost(_ text: String, counter: TokenCounter) -> Int {
            switch prompt(text) {
            case .continuation(let text): counter.count(text)
            case .instruct(let system, let user): counter.count(system) + counter.count(user)
            }
        }
        if let counter {
            let limit = max(0, budget ?? defaultPromptTokenBudget)
            while !window.isEmpty, cost(window, counter: counter) > limit {
                window = rawSuffixTrimmed(window)
            }
        }
        let end = max(0, prefixStartUTF16) + prefix.utf16.count
        let report = ContextReport(items: [], contextMode: mode,
            rawUTF16Range: (end - window.utf16.count)..<end)
        return (prompt(window), report)
    }

    /// Prefer a word boundary, but always make progress for unbroken input.
    /// String indices preserve grapheme clusters; source ranges use UTF-16.
    static func rawSuffixTrimmed(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let keep = Int(Double(text.count) * 0.8)
        guard keep > 0 else { return "" }
        let cut = text.index(text.endIndex, offsetBy: -keep)
        if let boundary = text[cut...].firstIndex(where: { $0.isWhitespace }) {
            let next = text.index(after: boundary)
            if next < text.endIndex { return String(text[next...]) }
        }
        return String(text[cut...])
    }
}
