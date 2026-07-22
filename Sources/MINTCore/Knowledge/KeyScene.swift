import Foundation

/// 작가가 관리하는 선택적 핵심 장면 (PLAN §14 M11).
///
/// 분석 청크와 달리 원문 전체를 덮지 않으며, 내용 해시가 아닌 UUID가 정체성이다.
/// entries.json에 저장되므로 재분석은 이 값을 지우거나 덮을 수 없다.
public struct KeyScene: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case planned
        case drafted
        case confirmed

        public var label: String {
            switch self {
            case .planned: "계획"
            case .drafted: "초고"
            case .confirmed: "확정"
            }
        }
    }

    public let id: UUID
    public var chapterAnchor: [String]
    public var title: String
    public var summary: String
    public var sourceRange: Range<Int>?
    /// 원문 수정 뒤 범위를 되찾는 짧은 근거. 저장 시 40자로 제한한다.
    public var anchorSnippet: String?
    public var status: Status
    public var importance: Int
    public var characters: [UUID]
    public var povCharacter: UUID?
    public var linkedEventKeys: [String]
    public var authorConfirmed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), chapterAnchor: [String] = [], title: String = "",
        summary: String = "", sourceRange: Range<Int>? = nil,
        anchorSnippet: String? = nil, status: Status = .planned,
        importance: Int = 3, characters: [UUID] = [], povCharacter: UUID? = nil,
        linkedEventKeys: [String] = [], authorConfirmed: Bool = false,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.chapterAnchor = chapterAnchor
        self.title = title
        self.summary = summary
        self.sourceRange = sourceRange
        self.anchorSnippet = anchorSnippet.map { String($0.prefix(40)) }
        self.status = status
        self.importance = min(5, max(1, importance))
        self.characters = characters
        self.povCharacter = povCharacter
        self.linkedEventKeys = linkedEventKeys
        self.authorConfirmed = authorConfirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 저장하지 않는 규칙 기반 제안. 작가가 승인할 때만 KeyScene이 된다.
public struct StoryEventCandidate: Equatable, Sendable, Identifiable {
    public var ephemeralID: String
    public var proposedRange: Range<Int>?
    public var proposedTitle: String
    public var proposedSummary: String
    public var evidence: [String]
    public var importanceSignals: [String]
    public var confidence: Double
    public var inputHash: String

    public var id: String {
        ephemeralID
    }
}

/// M11 P0의 결정적 후보 감지기. 기존 사건·상태 변화만 재사용하며 LLM을 부르지 않는다.
public enum KeySceneCandidateDetector {
    public static let ruleVersion = "keyscene-candidate-v1"

    public static func detect(
        outline: DocumentOutline, events: [StoryEvent], body _: String,
        existing: [KeyScene], ignoredInputHashes: Set<String> = []
    ) -> [StoryEventCandidate] {
        let existingKeys = Set(existing.flatMap(\.linkedEventKeys))
        let sceneByHash = Dictionary(
            uniqueKeysWithValues: outline.scenes.map { ($0.contentHash, $0) }
        )
        return events.compactMap { event in
            guard event.importance >= 4 || !event.deltas.isEmpty,
                  !existingKeys.contains(event.stableKey),
                  let scene = sceneByHash[event.sceneHash],
                  !existing.contains(where: {
                      $0.summary == event.summary
                          || ($0.sourceRange?.overlaps(scene.utf16Range) == true
                              && $0.title == SentenceClamp.clamp(event.summary, to: 24))
                  })
            else { return nil }
            var signals: [String] = []
            if event.importance >= 4 { signals.append("중요도 \(event.importance)") }
            if !event.deltas.isEmpty { signals.append("상태 변화 \(event.deltas.count)개") }
            let inputHash = DocumentOutline.stableHash(
                "\(ruleVersion)|\(scene.contentHash)|\(event.stableKey)"
            )
            guard !ignoredInputHashes.contains(inputHash) else { return nil }
            return StoryEventCandidate(
                ephemeralID: inputHash,
                proposedRange: scene.utf16Range,
                proposedTitle: SentenceClamp.clamp(event.summary, to: 24),
                proposedSummary: event.summary,
                evidence: event.quote.map { [$0] } ?? [],
                importanceSignals: signals,
                confidence: event.importance >= 5 ? 0.9 : 0.75,
                inputHash: inputHash
            )
        }
    }
}

/// KeyScene 범위 재앵커. 찾지 못해도 원본을 돌려주고 stale로 표시한다.
public enum KeySceneReconciler {
    public struct Result: Equatable, Sendable {
        public var scenes: [KeyScene]
        public var staleIDs: Set<UUID>
    }

    public static func reconcile(_ scenes: [KeyScene], in body: String) -> Result {
        let text = body as NSString
        var stale: Set<UUID> = []
        let reconciled = scenes.map { scene -> KeyScene in
            guard scene.sourceRange != nil else { return scene }
            guard let snippet = scene.anchorSnippet?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !snippet.isEmpty
            else {
                if !isValid(scene.sourceRange, length: text.length) { stale.insert(scene.id) }
                return scene
            }

            let matches = ranges(of: snippet, in: text)
            guard !matches.isEmpty else {
                stale.insert(scene.id)
                return scene
            }
            let oldStart = scene.sourceRange?.lowerBound ?? 0
            let best = matches.min { abs($0.location - oldStart) < abs($1.location - oldStart) }!
            var updated = scene
            let oldLength = max(scene.sourceRange?.count ?? best.length, best.length)
            updated.sourceRange = best.location ..< min(text.length, best.location + oldLength)
            return updated
        }
        return Result(scenes: reconciled, staleIDs: stale)
    }

    public static func snippet(in body: String, range: Range<Int>?) -> String? {
        guard let range else { return nil }
        let text = body as NSString
        let lower = min(max(0, range.lowerBound), text.length)
        let upper = min(max(lower, range.upperBound), text.length)
        guard upper > lower else { return nil }
        let raw = text.substring(with: NSRange(location: lower, length: upper - lower))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return String(raw.prefix(40))
    }

    private static func isValid(_ range: Range<Int>?, length: Int) -> Bool {
        guard let range else { return true }
        return range.lowerBound >= 0 && range.upperBound <= length && !range.isEmpty
    }

    private static func ranges(of needle: String, in text: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var search = NSRange(location: 0, length: text.length)
        while search.length > 0 {
            let found = text.range(of: needle, options: [], range: search)
            guard found.location != NSNotFound else { break }
            result.append(found)
            let next = found.location + max(found.length, 1)
            search = NSRange(location: next, length: text.length - next)
        }
        return result
    }
}
