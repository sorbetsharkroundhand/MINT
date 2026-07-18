import Foundation

// Narrative Intelligence 공통 타입 (PLAN §6.5·§8) — 씬 메타·앎·관계·사실·복선·
// 브랜치·대화 인덱스. 원문을 복제하지 않고 씬 해시 + 짧은 인용(quote)으로
// 원문을 참조한다 (원문이 유일한 진실, CLAUDE.md §2-1). 인용은 본문 검색으로
// 위치를 되찾는 앵커라 문서 편집 후에도 안정적이다 (기존 requestSearchJump 통로).

// MARK: - 근거 (Source Evidence)

/// AI 판단의 근거 종류 — 명시적으로 읽은 것과 추론한 것을 같게 취급하지 않는다.
public enum EvidenceKind: String, Codable, Equatable, Sendable {
    /// 원문 인용이 실제 본문에서 발견됨 — 직접 근거.
    case direct = "직접"
    /// 인용이 없거나 본문에서 못 찾음 — 모델의 추론/종합.
    case inferred = "추론"
}

// MARK: - 인물 앎 (Character Knowledge)

/// 인물이 아는/의심하는/오해하는/숨기는 사실 하나의 변화 (PLAN §6.5).
/// StateDelta처럼 append-only — `KnowledgeSnapshot.knowledge(of:before:)`가
/// 커서 이전 델타를 접어 그 시점의 앎을 만든다.
public struct KnowledgeDelta: Codable, Equatable, Sendable {
    /// 닫힌 태도 집합 — 소형 모델의 자유 서술을 막는다 (StateDelta.Field와 같은 규율).
    public enum Stance: String, Codable, Equatable, Sendable, CaseIterable {
        case knows = "안다"
        case suspects = "의심"
        case misbelieves = "오해"
        case hides = "숨김"
    }

    public var characterID: UUID
    public var stance: Stance
    /// ≤60자 — "남편이 약을 바꿔치기했다" 같은 명제.
    public var fact: String
    /// 근거 앵커 — 이 앎이 생긴 씬.
    public var sceneHash: String
    /// 원문 인용 (≤60자) — 본문 검색으로 위치를 되찾는다. 없으면 추론 근거.
    public var quote: String?

    public init(
        characterID: UUID, stance: Stance, fact: String,
        sceneHash: String, quote: String? = nil
    ) {
        self.characterID = characterID
        self.stance = stance
        self.fact = fact
        self.sceneHash = sceneHash
        self.quote = quote
    }

    public var evidenceKind: EvidenceKind { quote == nil ? .inferred : .direct }
}

// MARK: - 인물 관계 (방향 있는 관계 변화)

/// (from → to) 방향의 관계 상태 변화 하나 — append-only, 시점 질의로 접는다.
/// StateDelta의 `관계` 필드는 인물 하나의 뭉뚱그린 값이라 쌍(pair) 추적이
/// 안 된다 — 방향 쌍이 필요해 별도 타입이다 (PLAN §6.5).
public struct RelationDelta: Codable, Equatable, Sendable {
    public var fromID: UUID
    public var toID: UUID
    /// ≤40자 — "의심과 통제" 같은 짧은 명사구.
    public var value: String
    public var sceneHash: String
    public var quote: String?

    public init(
        fromID: UUID, toID: UUID, value: String,
        sceneHash: String, quote: String? = nil
    ) {
        self.fromID = fromID
        self.toID = toID
        self.value = value
        self.sceneHash = sceneHash
        self.quote = quote
    }
}

// MARK: - 설정 사실 (Continuity Fact)

/// 작품 세계의 확정적 설정 하나 — "아내는 운전을 못 한다", "총알은 6발".
/// 충돌 감지(FactConflict)의 재료다 (PLAN §6.5).
public struct ContinuityFact: Codable, Equatable, Sendable, Identifiable {
    /// 대상 — 인물 이름·사물 등 자유 문자열 (등록 카드 강제 아님: 사물도 설정이다).
    public var subject: String
    /// ≤60자 명제.
    public var statement: String
    public var sceneHash: String
    public var quote: String?

    public init(subject: String, statement: String, sceneHash: String, quote: String? = nil) {
        self.subject = subject
        self.statement = statement
        self.sceneHash = sceneHash
        self.quote = quote
    }

    /// 안정 키 — 같은 대상·명제면 재추출 후에도 같다 (사용자 결정의 앵커).
    public var id: String { DocumentOutline.stableHash("\(subject)|\(statement)") }
}

/// 두 설정 사실의 충돌 후보 — 깊은 패스의 LLM 검사가 제안하고, 판정은 사용자가
/// 한다 (실제 충돌/의도된 설정/무시 — 자동 수정 절대 금지, CLAUDE.md §1-5).
public struct FactConflict: Codable, Equatable, Sendable, Identifiable {
    public var aID: String
    public var bID: String
    /// ≤80자 — 왜 충돌로 보이는지.
    public var reason: String

    public init(aID: String, bID: String, reason: String) {
        self.aID = aID
        self.bID = bID
        self.reason = reason
    }

    /// 순서 무관 안정 키 — (a,b)와 (b,a)는 같은 충돌이다.
    public var id: String {
        DocumentOutline.stableHash([aID, bID].sorted().joined(separator: "|"))
    }
}

// MARK: - 복선 (Foreshadowing)

/// 복선 후보 하나 — AI는 candidate만 제안하고, 확정·무시·회수는 사용자의 몫이다.
public struct ForeshadowCandidate: Codable, Equatable, Sendable, Identifiable {
    /// ≤30자 라벨 — "향수 냄새"·"열리지 않는 서랍". 같은 라벨은 같은 복선으로
    /// 묶인다 (여러 씬에 걸친 reinforced 판정의 키).
    public var label: String
    /// ≤80자 — 무엇이 심어졌는지.
    public var detail: String
    public var sceneHash: String
    public var quote: String?

    public init(label: String, detail: String, sceneHash: String, quote: String? = nil) {
        self.label = label
        self.detail = detail
        self.sceneHash = sceneHash
        self.quote = quote
    }

    public var id: String { DocumentOutline.stableHash("\(label)|\(sceneHash)") }
}

/// 복선 생애 상태 — AI 제안은 항상 candidate, 나머지 전이는 사용자 결정
/// (NarrativeOverride로 저장).
public enum ForeshadowStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case candidate = "후보"
    case confirmed = "확정"
    case resolved = "회수"
    case ignored = "무시"
}

/// 라벨 하나로 묶인 복선 — 스냅샷이 씬별 후보를 라벨로 접어 만든다.
public struct ForeshadowThread: Equatable, Sendable, Identifiable {
    public var label: String
    public var detail: String
    /// 등장 씬 해시들 (담화 순서) — 2곳 이상이면 reinforced.
    public var sceneHashes: [String]
    public var quotes: [String]
    public var status: ForeshadowStatus
    public var userEdited: Bool

    public var id: String { label }
    public var isReinforced: Bool { sceneHashes.count >= 2 }
}

// MARK: - 씬 심화 추출 묶음 (사이드카 저장 단위)

/// 씬 하나의 심화 추출 결과 — 앎·관계·설정 사실·복선 후보 (PLAN §6.5).
/// 사건 추출과 **별도 호출**로 뽑는다: 필드 7종을 한 프롬프트에 욱여넣으면
/// 소형 모델의 형식 준수가 무너진다 (사건/요약 분리와 같은 실패 격리 규율).
/// 키 존재 = 추출 완료 메모 (`KnowledgeSidecar.events`와 같은 규약).
public struct SceneInsights: Codable, Equatable, Sendable {
    public var knowledge: [KnowledgeDelta]
    public var relations: [RelationDelta]
    public var facts: [ContinuityFact]
    public var foreshadows: [ForeshadowCandidate]
    public var updatedAt: Date

    public init(
        knowledge: [KnowledgeDelta] = [],
        relations: [RelationDelta] = [],
        facts: [ContinuityFact] = [],
        foreshadows: [ForeshadowCandidate] = [],
        updatedAt: Date = .now
    ) {
        self.knowledge = knowledge
        self.relations = relations
        self.facts = facts
        self.foreshadows = foreshadows
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        knowledge.isEmpty && relations.isEmpty && facts.isEmpty && foreshadows.isEmpty
    }
}

// MARK: - 씬 메타 (제목·유형·시점·장소)

/// 씬의 서사 유형 — 브랜치 판별의 축. 열린 확장을 위해 raw 문자열을 보존하되
/// 알려진 값은 여기로 정규화한다.
public enum SceneNarrativeType: String, Codable, Equatable, Sendable, CaseIterable {
    case present = "현재"
    case flashback = "회상"
    case dream = "꿈"
    case flashforward = "예상"
    case parallel = "병렬"
    case inserted = "삽입"

    /// LLM 출력·사용자 입력의 관대한 정규화 — 모르는 값은 present로
    /// (브랜치는 확신이 있을 때만 만든다, 품질 > 적극성).
    public static func normalize(_ raw: String) -> SceneNarrativeType {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = SceneNarrativeType(rawValue: cleaned) { return exact }
        if cleaned.contains("회상") || cleaned.contains("과거") { return .flashback }
        if cleaned.contains("꿈") { return .dream }
        if cleaned.contains("예상") || cleaned.contains("미래") { return .flashforward }
        if cleaned.contains("병렬") || cleaned.contains("동시") { return .parallel }
        if cleaned.contains("삽입") || cleaned.contains("액자") { return .inserted }
        return .present
    }

    /// 작품 내 시간 관계 기본값 — 유형에서 파생, 사용자가 브랜치에서 고칠 수 있다.
    public var defaultChrono: ChronoRelation {
        switch self {
        case .present, .inserted: .unknown
        case .flashback, .dream: .before
        case .flashforward: .after
        case .parallel: .simultaneous
        }
    }
}

/// 작품 세계 시간축에서의 상대 관계 — 절대 시각을 알 수 없는 경우가 대부분이라
/// 상대 관계만 표현한다 (before/after/simultaneous/unknown).
public enum ChronoRelation: String, Codable, Equatable, Sendable, CaseIterable {
    case before = "과거"
    case after = "미래"
    case simultaneous = "동시"
    case unknown = "불명"
}

// MARK: - Narrative Branch (파생 — 저장하지 않는다)

/// 서사 브랜치 — **연속된 비(非)현재 씬 묶음**에서 결정적으로 파생된다.
/// 한 문장의 과거 언급은 씬 유형을 바꾸지 않으므로 브랜치가 되지 않는다 —
/// 씬 전체가 회상일 때만 갈라진다 (요구사항 §8의 "의미 있는 Thread" 판별).
/// 파생이라 저장·무효화가 없다: 씬 유형(사이드카+오버라이드)이 바뀌면
/// 다음 스냅샷에서 브랜치도 저절로 바뀐다.
public struct NarrativeBranch: Equatable, Sendable, Identifiable {
    public var type: SceneNarrativeType
    /// 아웃라인 씬 인덱스 구간 (담화 순서) — 시작·복귀 지점이 여기서 나온다.
    public var sceneRange: Range<Int>
    /// 구간 첫 씬의 해시 — 오버라이드(이름·시간 관계)의 안정 키.
    public var anchorHash: String
    /// 표시 이름 — 기본은 유형 라벨, 사용자가 바꿀 수 있다.
    public var name: String
    public var chrono: ChronoRelation
    public var userEdited: Bool

    public var id: String { anchorHash }

    /// 씬 유형 배열 → 브랜치 목록 (main은 브랜치로 만들지 않는다 — 레일 자체가 main).
    public static func derive(
        types: [SceneNarrativeType],
        anchorHashes: [String],
        nameOverrides: [String: String] = [:],
        chronoOverrides: [String: ChronoRelation] = [:]
    ) -> [NarrativeBranch] {
        var branches: [NarrativeBranch] = []
        var index = 0
        while index < types.count {
            let type = types[index]
            guard type != .present else {
                index += 1
                continue
            }
            var end = index + 1
            while end < types.count, types[end] == type { end += 1 }
            let anchor = anchorHashes[index]
            branches.append(
                NarrativeBranch(
                    type: type,
                    sceneRange: index..<end,
                    anchorHash: anchor,
                    name: nameOverrides[anchor] ?? type.rawValue,
                    chrono: chronoOverrides[anchor] ?? type.defaultChrono,
                    userEdited: nameOverrides[anchor] != nil || chronoOverrides[anchor] != nil))
            index = end
        }
        return branches
    }
}

// MARK: - 대화 인덱스 (파생 — 결정적, LLM 없음)

/// 대화 하나 — 원문을 복제하지 않고 위치·첫 대사만 참조한다 (요구사항 §13).
/// DialogueAttribution의 발화들에서 결정적으로 묶는다.
public struct Conversation: Equatable, Sendable, Identifiable {
    public var participants: [UUID]
    /// 대화가 시작하는 씬 해시 (씬 밖이면 nil).
    public var sceneHash: String?
    public var utf16Start: Int
    public var utf16End: Int
    public var utteranceCount: Int
    /// 첫 대사 앞부분 (≤40자) — 목록 미리보기 + 원문 점프 질의.
    public var firstLine: String

    public var id: String { "\(utf16Start)-\(utteranceCount)" }

    /// 발화 목록 → 대화 묶음. 씬이 바뀌거나 발화 간격이 크면 새 대화다.
    /// O(발화 수) — 패스마다 재계산해도 밀리초 단위 (Utterance와 같은 예산).
    public static func index(
        utterances: [Utterance], outline: DocumentOutline,
        maxGapUTF16: Int = 400
    ) -> [Conversation] {
        guard !utterances.isEmpty else { return [] }
        var conversations: [Conversation] = []
        var current: [Utterance] = []

        func sceneHash(at offset: Int) -> String? {
            outline.sceneIndex(at: offset).map { outline.scenes[$0].contentHash }
        }

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let ids = Array(Set(current.map(\.speakerID) + current.compactMap(\.listenerID)))
            conversations.append(
                Conversation(
                    participants: ids,
                    sceneHash: sceneHash(at: first.utf16Start),
                    utf16Start: first.utf16Start,
                    utf16End: last.utf16Start + (last.text as NSString).length,
                    utteranceCount: current.count,
                    firstLine: String(first.text.prefix(40))))
            current = []
        }

        for utterance in utterances {
            if let last = current.last {
                let gap = utterance.utf16Start - (last.utf16Start + (last.text as NSString).length)
                let crossedScene =
                    sceneHash(at: last.utf16Start) != sceneHash(at: utterance.utf16Start)
                if gap > maxGapUTF16 || crossedScene { flush() }
            }
            current.append(utterance)
        }
        flush()
        return conversations
    }
}

// MARK: - 사용자 수정 (NarrativeOverride) — 원문 스토어에 산다

/// AI 분석 결과에 대한 사용자 수정 하나 (CLAUDE.md §1-5 "사용자 수정이 자동
/// 추출을 이긴다"). **파생 캐시(사이드카)가 아니라 entries.json에 저장한다** —
/// 사이드카는 스키마 변경 시 통째로 버려지므로 사용자 결정을 담을 수 없다.
/// 스냅샷 조립이 마지막에 이 목록을 얹는다 — 재분석은 원본 캐시만 갱신하고
/// 오버라이드는 건드리지 않으므로 덮어쓰기가 구조적으로 불가능하다.
public struct NarrativeOverride: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Equatable, Sendable {
        /// 씬 제목 (키 = 씬 해시).
        case sceneTitle
        /// 씬 서사 유형 — 브랜치 편집의 원자 단위 (키 = 씬 해시).
        case sceneType
        /// 사건 중요도 1–5 (키 = 사건 키 `StoryEvent.stableKey`).
        case eventImportance
        /// 사건 요약 (키 = 사건 키).
        case eventSummary
        /// 복선 상태 (키 = 복선 라벨, 값 = ForeshadowStatus rawValue).
        case foreshadowStatus
        /// 설정 충돌 판정 (키 = FactConflict.id, 값 = 충돌/의도됨/무시).
        case conflictResolution
        /// 브랜치 이름 (키 = 브랜치 anchorHash).
        case branchName
        /// 브랜치 시간 관계 (키 = anchorHash, 값 = ChronoRelation rawValue).
        case branchChrono
    }

    public var kind: Kind
    /// 대상의 안정 키 — 씬 해시·사건 키·라벨 등.
    public var key: String
    public var value: String
    /// 재앵커 스니펫 — 씬 오버라이드는 씬 첫머리 산문(≤40자)을 함께 저장한다.
    /// 씬 원문이 수정돼 해시가 바뀌면 이 스니펫으로 새 씬을 찾아 이어 붙인다.
    public var anchor: String?
    public var updatedAt: Date

    public init(
        kind: Kind, key: String, value: String,
        anchor: String? = nil, updatedAt: Date = .now
    ) {
        self.kind = kind
        self.key = key
        self.value = value
        self.anchor = anchor
        self.updatedAt = updatedAt
    }

    public var id: String { "\(kind.rawValue)|\(key)" }
}

/// 충돌 판정 값 (conflictResolution 오버라이드의 닫힌 값 집합).
public enum ConflictResolution: String, Codable, Equatable, Sendable {
    case confirmed = "충돌"
    case intended = "의도됨"
    case ignored = "무시"
}

/// 오버라이드 목록의 질의 헬퍼 — 스냅샷 조립·UI가 같은 해석을 쓴다.
public struct NarrativeOverrides: Equatable, Sendable {
    public let all: [NarrativeOverride]
    private let byID: [String: NarrativeOverride]

    public init(_ overrides: [NarrativeOverride]) {
        self.all = overrides
        self.byID = Dictionary(
            overrides.map { ($0.id, $0) },
            uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
    }

    public static let empty = NarrativeOverrides([])

    public func value(_ kind: NarrativeOverride.Kind, key: String) -> String? {
        byID["\(kind.rawValue)|\(key)"]?.value
    }

    /// kind 하나의 (키 → 값) 사전 — 브랜치 파생 등 일괄 적용용.
    public func map(of kind: NarrativeOverride.Kind) -> [String: String] {
        var result: [String: String] = [:]
        for override in all where override.kind == kind {
            result[override.key] = override.value
        }
        return result
    }

    /// **씬 키 재앵커** — 씬 원문이 수정되면 해시가 바뀌어 오버라이드가 고아가
    /// 된다. anchor 스니펫이 포함된 씬을 현재 아웃라인에서 찾아 키를 잇는다.
    /// 실패한 오버라이드는 stale로 남는다 (조용히 지우지 않는다 — 요구사항 §9).
    public func rekeyedForScenes(
        outline: DocumentOutline, body: String
    ) -> (overrides: NarrativeOverrides, stale: [NarrativeOverride]) {
        let liveHashes = Set(outline.scenes.map(\.contentHash))
        let text = body as NSString
        var updated: [NarrativeOverride] = []
        var stale: [NarrativeOverride] = []
        for override in all {
            let sceneKeyed = override.kind == .sceneTitle || override.kind == .sceneType
                || override.kind == .branchName || override.kind == .branchChrono
            guard sceneKeyed, !liveHashes.contains(override.key) else {
                updated.append(override)
                continue
            }
            // 앵커 스니펫으로 새 씬 찾기 — 스니펫을 포함하는 첫 씬으로 재키.
            if let anchor = override.anchor, !anchor.isEmpty,
                let scene = outline.scenes.first(where: { scene in
                    let range = NSRange(
                        location: scene.utf16Range.lowerBound,
                        length: scene.utf16Range.count)
                    return text.range(of: anchor, options: [], range: range).location
                        != NSNotFound
                })
            {
                var rekeyed = override
                rekeyed.key = scene.contentHash
                updated.append(rekeyed)
            } else {
                stale.append(override)
                updated.append(override)  // 보존 — 원문이 돌아오면 다시 산다
            }
        }
        return (NarrativeOverrides(updated), stale)
    }
}

// MARK: - 문장 경계 절단

/// 길이 상한을 지키되 **문장 중간에서 자르지 않는** 절단 (요구사항 §2의 근본
/// 수정 절반 — 나머지 절반은 생성 토큰 예산). 상한 안의 마지막 문장 종결부호까지
/// 살리고, 종결부호가 하나도 없으면 어절 경계, 그것도 없으면 prefix 폴백.
public enum SentenceClamp {
    static let terminals: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
    static let closers: Set<Character> = ["”", "\"", "」", "』", "’", "'"]

    public static func clamp(_ text: String, to limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        let head = collapsed.prefix(limit)
        // 상한 안의 마지막 종결부호(+닫는 따옴표)에서 끊는다.
        var cut: String.Index?
        var index = head.startIndex
        while index < head.endIndex {
            if terminals.contains(head[index]) {
                var end = head.index(after: index)
                while end < head.endIndex,
                    terminals.contains(head[end]) || closers.contains(head[end])
                {
                    end = head.index(after: end)
                }
                cut = end
                index = end
            } else {
                index = head.index(after: index)
            }
        }
        if let cut { return String(head[..<cut]).trimmingCharacters(in: .whitespaces) }
        // 종결부호가 없다 — 마지막 어절 경계에서. (한 어절이 상한을 넘으면 prefix.)
        if let space = head.lastIndex(of: " "), space > head.startIndex {
            let clipped = String(head[..<space]).trimmingCharacters(in: .whitespaces)
            if clipped.count >= limit / 2 { return clipped + "…" }
        }
        return String(head)
    }
}
