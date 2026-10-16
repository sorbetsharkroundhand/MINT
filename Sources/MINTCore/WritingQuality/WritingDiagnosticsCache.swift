import Foundation

/// Active-document, byte-accounted LRU. Only successfully assessed relative results enter it.
final class WritingDiagnosticsCache {
    struct Key: Hashable, Sendable {
        var digest: String
        var languageTag: String
        var profileRevision: UInt64
        var providerRevision: String
        var ruleRevision: Int
    }
    private final class Entry {
        let key: Key, text: String, diagnostics: [WritingDiagnostic], cost: Int
        weak var previous: Entry?
        var next: Entry?
        init(key: Key, text: String, diagnostics: [WritingDiagnostic], cost: Int) {
            self.key = key; self.text = text; self.diagnostics = diagnostics; self.cost = cost
        }
    }
    let budgetBytes: Int
    private(set) var costBytes = 0
    private var entries: [Key: Entry] = [:]
    private var first: Entry?, last: Entry?
    var count: Int { entries.count }
    init(budgetBytes: Int = 16 * 1024 * 1024) { self.budgetBytes = max(0, budgetBytes) }
    func value(for key: Key, text: String) -> [WritingDiagnostic]? {
        guard let entry = entries[key], entry.text.utf16.elementsEqual(text.utf16) else { return nil }
        unlink(entry); prepend(entry)
        return entry.diagnostics
    }
    @discardableResult
    func insert(_ diagnostics: [WritingDiagnostic], text: String, for key: Key) -> Bool {
        if let old = entries.removeValue(forKey: key) { unlink(old); costBytes -= old.cost }
        let cost = 256 + Self.stringCost(text) + Self.stringCost(key.digest) + Self.stringCost(key.languageTag)
            + Self.stringCost(key.providerRevision) + diagnostics.reduce(0) { $0 + Self.diagnosticCost($1) }
        guard cost <= budgetBytes else { return false }
        while costBytes > budgetBytes - cost, let oldest = last {
            entries.removeValue(forKey: oldest.key); unlink(oldest); costBytes -= oldest.cost
        }
        let entry = Entry(key: key, text: text, diagnostics: diagnostics, cost: cost)
        entries[key] = entry; prepend(entry); costBytes += cost
        return true
    }
    func clear() { entries.removeAll(); first = nil; last = nil; costBytes = 0 }
    static func stringCost(_ text: String) -> Int { 32 + text.utf8.count + text.utf16.count * 2 }
    static func diagnosticCost(_ value: WritingDiagnostic) -> Int {
        256 + [value.id, value.ruleID, value.providerID, value.message, value.reason ?? "", value.languageTag]
            .reduce(0) { $0 + stringCost($1) } + value.alternatives.reduce(0) { $0 + stringCost($1) }
            + value.relatedRanges.count * 32
    }
    private func unlink(_ entry: Entry) {
        let previous = entry.previous, next = entry.next
        if let previous { previous.next = next } else if first === entry { first = next }
        if let next { next.previous = previous } else if last === entry { last = previous }
        entry.previous = nil; entry.next = nil
    }
    private func prepend(_ entry: Entry) {
        entry.next = first; first?.previous = entry; first = entry
        if last == nil { last = entry }
    }
}
