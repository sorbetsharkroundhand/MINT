import CryptoKit
import Foundation

/// A scoped request for evidence-bounded review, never a verdict or writer canon.
public struct ContinuityCandidate: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case deadSpeaker, honorificBreak, knowledgeLeak, locationOverlap, ageArithmetic, objectReappearance, relationshipIdentity }
    public let id: String
    public let scope: StoryMemoryScope
    public let sourceRevision: String
    public let kind: Kind
    public let subjectID: UUID
    public let evidence: [EvidenceAnchor]
    public let factIDs: [String]
    public let requiresJudging: Bool
    private init(id: String, scope: StoryMemoryScope, sourceRevision: String, kind: Kind, subjectID: UUID, evidence: [EvidenceAnchor], factIDs: [String], requiresJudging: Bool) {
        self.id = id; self.scope = scope; self.sourceRevision = sourceRevision; self.kind = kind; self.subjectID = subjectID; self.evidence = evidence; self.factIDs = factIDs; self.requiresJudging = requiresJudging
    }

    /// Snapshot preparation already verified originals, registrations and writer authority.
    public static func prepare(snapshot: StoryKnowledgeSnapshot, before: Int) -> [Self] {
        guard !Task.isCancelled, (0...snapshot.sourceLength).contains(before) else { return [] }
        let observations = snapshot.observations(before: before)
        guard observations.count <= 8192 else { return [] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func encoded<T: Encodable>(_ value: T) -> String {
            (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        let scopeKey = encoded(snapshot.scope)
        func logical(_ fact: StoryFact) -> String { encoded([encoded(fact.content), encoded(fact.storyInterval)]) }
        var output: [Self] = [], comparisons = 0
        func append(_ kind: Kind, subject: UUID, _ a: StoryFact, _ b: StoryFact) {
            let key = encoded([scopeKey, kind.rawValue, subject.uuidString] + [logical(a), logical(b)].sorted())
            let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            guard !output.contains(where: { $0.id == id }) else { return }
            let pair: [StoryFact] = [a, b].sorted { (left: StoryFact, right: StoryFact) -> Bool in
                let leftOffset = left.evidence.utf16Hint ?? left.discourseRange.lowerBound
                let rightOffset = right.evidence.utf16Hint ?? right.discourseRange.lowerBound
                if leftOffset != rightOffset { return leftOffset < rightOffset }
                return left.derivedID < right.derivedID
            }
            output.append(.init(id: id, scope: snapshot.scope, sourceRevision: snapshot.sourceRevision,
                kind: kind, subjectID: subject, evidence: pair.map(\.evidence), factIDs: pair.map(\.derivedID), requiresJudging: true))
            output.sort(by: ordered)
            if output.count > 128 { output.removeLast() }
        }
        let groups = Dictionary(grouping: observations.compactMap { fact -> (String, StoryFact)? in
            guard let slot = slot(fact.content) else { return nil }
            return (slot, fact)
        }, by: { $0.0 })
        for key in groups.keys.sorted() {
            guard !Task.isCancelled else { return [] }
            let values = (groups[key] ?? []).map { $0.1 }
            if key.hasPrefix("object:") {
                // Unknown time cannot be silently omitted from a purported transition chain.
                guard values.allSatisfy({ start($0.storyInterval) != nil }) else { continue }
                let ordered = values.sorted {
                    let a = start($0.storyInterval)!, b = start($1.storyInterval)!
                    if a.timelineID != b.timelineID { return a.timelineID.uuidString < b.timelineID.uuidString }
                    if a.tick != b.tick { return a.tick < b.tick }
                    return $0.discourseRange.upperBound < $1.discourseRange.upperBound
                }
                var previous: StoryFact?
                for fact in ordered {
                    guard !Task.isCancelled else { return [] }
                    guard authoritative(fact) else { previous = nil; continue }
                    if let prior = previous, start(prior.storyInterval)?.timelineID == start(fact.storyInterval)?.timelineID,
                       case .objectState(let a) = prior.content, case .objectState(let b) = fact.content,
                       ["파괴됨", "소실"].contains(a.value), ["온전함", "존재"].contains(b.value) {
                        append(.objectReappearance, subject: a.objectID, prior, fact)
                    }
                    previous = fact
                }
                continue
            }
            var seen: Set<String> = []
            let unique = values.filter { authoritative($0) && seen.insert(logical($0)).inserted }
            for index in unique.indices {
                for other in unique.indices where other > index {
                    comparisons += 1
                    // An over-budget pass publishes nothing rather than an incomplete claim set.
                    guard !Task.isCancelled, comparisons <= 65536 else { return [] }
                    let a = unique[index], b = unique[other]
                    guard a.storyInterval.overlap(with: b.storyInterval) == .overlapping else { continue }
                    switch (a.content, b.content) {
                    case (.characterKnowledge(let x), .characterKnowledge(let y)):
                        if (x.stance == .unaware && y.stance == .knows) || (x.stance == .knows && y.stance == .unaware) {
                            append(.knowledgeLeak, subject: x.characterID, a, b)
                        }
                    case (.characterState(let x), .characterState(let y)):
                        if x.value != y.value { append(.locationOverlap, subject: x.characterID, a, b) }
                    case (.relationship(let x), .relationship(let y)):
                        if opposing(x.value, y.value) { append(.relationshipIdentity, subject: x.fromID, a, b) }
                    default: break
                    }
                }
            }
        }
        return Task.isCancelled ? [] : output
    }

    private static func authoritative(_ fact: StoryFact) -> Bool {
        if case .writerDecision = fact.origin { return true }
        return fact.confidence.map { $0 >= 0.8 } ?? false
    }
    private static func slot(_ content: StoryFact.Content) -> String? {
        switch content {
        case .characterKnowledge(let x): "knowledge:\(x.characterID):\(x.fact)"
        case .characterState(let x) where x.field == .location: "location:\(x.characterID)"
        case .relationship(let x): "relationship:\(x.fromID):\(x.toID)"
        case .objectState(let x) where x.field == .condition: "object:\(x.objectID)"
        default: nil
        }
    }
    private static func start(_ interval: StoryInterval) -> StoryInstant? {
        switch interval {
        case .unknown: nil
        case .point(let instant): instant
        case .range(let start, _): start
        }
    }
    private static func opposing(_ a: String, _ b: String) -> Bool {
        [("배우자", "배우자 아님"), ("친부", "친부 아님"), ("친모", "친모 아님"), ("동일인", "다른 인물")].contains {
            ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a)
        }
    }
    private static func ordered(_ a: Self, _ b: Self) -> Bool {
        let left = a.evidence.last?.utf16Hint ?? 0, right = b.evidence.last?.utf16Hint ?? 0
        return left == right ? a.id < b.id : left < right
    }
}
