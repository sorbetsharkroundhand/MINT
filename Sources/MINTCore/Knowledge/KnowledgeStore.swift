import Foundation

/// 작품별 지식 사이드카 (PLAN §6 저장 형식) — 요약 피라미드의 디스크 형태.
///
/// `~/Documents/MINT/knowledge/<entryID>.json`. **전체가 파생 캐시다** —
/// 스키마가 바뀌면 `schemaVersion`을 올리고, 버전이 다른 파일은 버리고
/// 재구축한다. 마이그레이션 코드를 쌓지 않는다 (CLAUDE.md §2-1).
///
/// 소유자는 `BackgroundIndexer` 하나뿐이다 — 읽기·쓰기가 인덱서의 단일
/// 태스크 안에서만 일어나므로 actor 격리가 필요 없다. 예측 경로는 이 파일을
/// 절대 읽지 않는다 — 인덱서가 발행한 인메모리 `KnowledgeSnapshot`만 쓴다
/// (예측 시점 디스크 접근 금지, CLAUDE.md §2-2).
public struct KnowledgeSidecar: Codable, Equatable, Sendable {

    /// 지식 스키마 버전 — 구조가 바뀌면 올린다. 다른 버전 파일은 로드 시 폐기.
    /// v2 (M6-5a): 사건 로그 추가. v3 (M6-5b): 사건 추출이 StateDelta까지 뽑는다 —
    /// 디코딩 모양은 같지만 `events` 메모의 **의미**가 바뀌었다 (키 존재 = 델타
    /// 포함 추출 완료). v2 파일을 살리면 5a 시절 사건들이 델타 없이 영영 남아
    /// `상태@커서`에 구멍이 뚫린다 — 폐기·재구축이 정답이다 (CLAUDE.md §2-1,
    /// 마이그레이션 코드를 쌓지 않는 값. 결정 5가 피하려던 두 번째 비용이지만,
    /// 추출 형식 자체가 바뀌어 피할 수 없었다 — docs/m6-events.md 5b).
    public static let currentSchemaVersion = 3

    /// 씬 요약 노드 (PLAN §6.1) — 앵커는 씬 원문의 콘텐츠 해시.
    /// 해시가 같으면 재요약 금지 (백그라운드 3요건의 메모이제이션, CLAUDE.md §4).
    public struct SceneSummary: Codable, Equatable, Sendable {
        /// `DocumentOutline.Scene.contentHash` — 씬 원문 SHA-256 앞 16자.
        public var contentHash: String
        /// 요약 당시의 헤딩 경로 — B 블록 렌더링용 (해시가 키, 경로는 표시용).
        public var headingPath: [String]
        /// 1–2문장, ≤120자 (PLAN §6.1).
        public var summary: String
        public var updatedAt: Date
    }

    /// 장 요약 노드 — 앵커는 하위 씬 해시들의 결합 해시.
    /// 하위 씬이 하나라도 바뀌면 키가 바뀌어 자연히 더티가 된다 (상향 전파).
    public struct ChapterSummary: Codable, Equatable, Sendable {
        /// 장을 여는 레벨 1–2 헤딩 경로 (예: ["1부", "3장"]).
        public var headingPath: [String]
        /// 하위 씬 contentHash들을 이어 붙인 문자열의 해시 — 더티 판정 키.
        public var childrenHash: String
        /// ≤300자 (PLAN §6.1).
        public var summary: String
        public var updatedAt: Date
    }

    /// 작품 요약 — 앵커는 장(또는 씬 전체) 해시들의 결합 해시. ≤500자.
    public struct WorkSummary: Codable, Equatable, Sendable {
        public var childrenHash: String
        public var summary: String
        public var updatedAt: Date
    }

    public var schemaVersion: Int
    /// 지식 세대 — 전체 재구축(캐시 비우기)마다 증가. 디버깅·벤치 대조용.
    public var generation: Int
    public var entryID: UUID
    /// 씬 해시 → 요약. 현재 아웃라인에 없는 해시도 다음 저장까지는 남겨 둔다 —
    /// 타이핑 중 해시가 요동칠 때(문장 하나 지웠다 복원) 재요약을 아낀다.
    public var sceneSummaries: [String: SceneSummary]
    public var chapterSummaries: [ChapterSummary]
    public var workSummary: WorkSummary?
    /// 씬 해시 → 그 씬의 사건들 (PLAN §6.3, M6-5).
    ///
    /// **키 존재 자체가 메모다** — 빈 배열은 "추출했고 사건이 없었다"이고 키
    /// 부재는 "아직 안 뽑았다"다. 이 구분이 없으면 사건 없는 씬을 깊은 패스마다
    /// 다시 뽑는다 (CLAUDE.md §4 메모이제이션).
    public var events: [String: [StoryEvent]]

    public init(entryID: UUID) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generation = 0
        self.entryID = entryID
        self.sceneSummaries = [:]
        self.chapterSummaries = []
        self.workSummary = nil
        self.events = [:]
    }

    // MARK: - 디스크 IO (인덱서 전용)

    /// `~/Documents/MINT/knowledge/` — 없으면 만든다.
    static func directory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MINT/knowledge", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for entryID: UUID) -> URL {
        directory().appendingPathComponent("\(entryID.uuidString).json")
    }

    /// 로드 — 파일이 없거나, 못 읽거나, **스키마 버전이 다르면** 빈 사이드카.
    /// 파생 캐시라 버리는 것이 곧 복구다 (CLAUDE.md §5-5).
    public static func load(entryID: UUID) -> KnowledgeSidecar {
        let url = fileURL(for: entryID)
        guard let data = try? Data(contentsOf: url) else {
            return KnowledgeSidecar(entryID: entryID)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let sidecar = try? decoder.decode(KnowledgeSidecar.self, from: data),
            sidecar.schemaVersion == currentSchemaVersion
        else {
            var fresh = KnowledgeSidecar(entryID: entryID)
            // 구버전을 버리고 재구축 — 세대를 올려 "다시 만든 지식"임을 남긴다.
            fresh.generation =
                ((try? decoder.decode(GenerationPeek.self, from: data))?.generation ?? 0) + 1
            return fresh
        }
        return sidecar
    }

    /// 버전 불일치 파일에서 세대 카운터만 건져 재구축 이력을 잇는다.
    private struct GenerationPeek: Codable { var generation: Int }

    /// 저장 (원자적 쓰기). 현재 아웃라인에 없는 씬 요약·사건은 여기서 정리한다 —
    /// 저장 시점이 곧 가비지 컬렉션이라 별도 청소 경로가 없다.
    ///
    /// 사건에는 이 정리가 곧 PLAN §8의 **톰스톤**이다: 블록이 수정되면 씬 해시가
    /// 바뀌어 그 씬의 사건이 고아가 되고, 여기서 사라진 뒤 다음 깊은 패스가
    /// 새 해시로 재추출한다. 무효화 전용 코드가 따로 없는 이유다.
    public func save(pruningTo liveHashes: Set<String>? = nil) {
        var snapshot = self
        if let liveHashes {
            snapshot.sceneSummaries = snapshot.sceneSummaries.filter {
                liveHashes.contains($0.key)
            }
            snapshot.events = snapshot.events.filter { liveHashes.contains($0.key) }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: Self.fileURL(for: entryID), options: .atomic)
    }

    /// 저널 삭제 시 사이드카도 지운다 (원문이 사라지면 파생물도 무의미).
    public static func remove(entryID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: entryID))
    }
}

/// 예측 조립이 읽는 인메모리 지식 스냅샷 (PLAN §11) — 인덱서가 패스를 마칠
/// 때마다 발행하는 **값 복사본**. MainActor(컨트롤러)가 pull해 격리 경계를
/// 넘긴다 (`DocumentContext`와 같은 패턴). 예측 경로에서 디스크·LLM을 건드리지
/// 않기 위한 유일한 통로다 (CLAUDE.md §2-2).
public struct KnowledgeSnapshot: Sendable, Equatable {
    public let entryID: UUID
    /// 스냅샷을 만든 시점의 아웃라인 — 씬 위치(utf16Range)로 시점 차단 질의를 한다.
    /// 이후의 타이핑으로 실제 본문과 어긋날 수 있다 — 오차는 다음 패스(유휴 ~5s)가
    /// 잡고, B 블록은 창 밖(커서에서 먼) 씬만 쓰므로 어긋남의 영향이 작다.
    public let outline: DocumentOutline
    /// 씬 콘텐츠 해시 → 요약문.
    public let summariesByHash: [String: String]
    /// 헤딩 경로("1부 > 3장" 조인 키) → 장 요약문.
    public let chapterSummariesByPath: [String: String]
    public let workSummary: String?
    /// 담화 순서(Pos = 씬 배열 인덱스)로 정렬된 사건들 (PLAN §6.3).
    /// 아웃라인에 없는 해시(톰스톤)는 여기서 이미 빠져 있다.
    public let events: [StoryEvent]
    /// 인물 id → `events` 인덱스 목록 — PLAN §6.3의 역색인.
    /// §11 엔티티 앵커 검색의 기반이자 `lastAppearance` 질의의 실체다.
    public let eventIndexByCharacter: [UUID: [Int]]
    /// 귀속된 발화들 (담화 순서, PLAN §6.4·§7 대화 귀속) — 결정적 추출이라
    /// 사이드카에 저장하지 않고 패스마다 재계산해 스냅샷에만 싣는다.
    public let utterances: [Utterance]
    /// 씬 해시 → 그 씬이 끝나는 UTF-16 위치. 시점 차단 질의를 예측 경로에서
    /// O(1)로 하기 위해 미리 접어 둔다 (조립은 조립만 — CLAUDE.md §2-2).
    private let sceneEndByHash: [String: Int]

    public init(
        entryID: UUID,
        outline: DocumentOutline,
        summariesByHash: [String: String],
        chapterSummariesByPath: [String: String] = [:],
        workSummary: String? = nil,
        events: [String: [StoryEvent]] = [:],
        utterances: [Utterance] = []
    ) {
        self.entryID = entryID
        self.outline = outline
        self.summariesByHash = summariesByHash
        self.chapterSummariesByPath = chapterSummariesByPath
        self.workSummary = workSummary
        self.utterances = utterances

        // 사건을 담화 순서로 편다 — 저장은 해시 키(삽입에 불변), 순서는 여기서
        // 아웃라인으로부터 파생한다 (docs/m6-events.md 결정 1).
        var ends: [String: Int] = [:]
        var ordered: [StoryEvent] = []
        for scene in outline.scenes {
            ends[scene.contentHash] = scene.utf16Range.upperBound
            // 같은 씬 안에서는 중요도 높은 사건이 먼저 — 예산 삭감이 뒤에서
            // 잘리므로 중요한 것이 살아남는다 (PLAN §11).
            let sceneEvents = (events[scene.contentHash] ?? [])
                .sorted { $0.importance > $1.importance }
            ordered.append(contentsOf: sceneEvents)
        }
        self.events = ordered
        self.sceneEndByHash = ends

        var index: [UUID: [Int]] = [:]
        for (offset, event) in ordered.enumerated() {
            for participant in event.participants {
                index[participant, default: []].append(offset)
            }
        }
        self.eventIndexByCharacter = index
    }

    // MARK: - 표준 질의 (PLAN §8) — ContextAssembler는 이것만 쓴다

    /// 주어진 위치 **이전에 완전히 끝난** 씬의 사건들 (담화 순서).
    /// 커서 이후 지식 누출 차단(CLAUDE.md §2-4)이 여기서 결정적으로 성립한다 —
    /// 3장을 고치는 중에 9장의 사건이 새어 들어가지 않는다.
    public func events(before utf16Offset: Int) -> [StoryEvent] {
        events.filter { (sceneEndByHash[$0.sceneHash] ?? .max) <= utf16Offset }
    }

    /// 인물이 마지막으로 등장한 사건 (그 위치 이전) — PLAN §8 `lastAppearance`.
    /// 역색인을 뒤에서부터 훑으므로 사건이 많아도 첫 적중에서 끝난다.
    public func lastAppearance(of characterID: UUID, before utf16Offset: Int) -> StoryEvent? {
        guard let offsets = eventIndexByCharacter[characterID] else { return nil }
        for offset in offsets.reversed() {
            let event = events[offset]
            if (sceneEndByHash[event.sceneHash] ?? .max) <= utf16Offset { return event }
        }
        return nil
    }

    /// 그 위치 시점의 인물 상태 — PLAN §8 `state_at`, §6.2의 fold.
    ///
    /// 커서 이전에 끝난 씬의 델타를 **담화 순서로 접는다**: 같은 필드는 나중
    /// 델타가 이긴다 (상태는 덮어쓰지 않고 append, 질의가 최신을 뽑는다).
    /// 시점 차단·톰스톤 제외는 `events(before:)`와 같은 씬 위치 비교라 여기서도
    /// 결정적으로 성립한다 — 9장에서 죽은 인물이 3장 수정 중에 "사망"으로
    /// 주입되지 않는다 (CLAUDE.md §2-4).
    ///
    /// 역색인이 담화 순서 오름차순이므로 앞에서부터 그대로 접으면 된다 —
    /// 인물 하나의 사건 수는 작아 예측 경로 예산 안이다 (조립은 조립만).
    public func stateAt(
        of characterID: UUID, before utf16Offset: Int
    ) -> [StateDelta.Field: String] {
        guard let offsets = eventIndexByCharacter[characterID] else { return [:] }
        var state: [StateDelta.Field: String] = [:]
        for offset in offsets {
            let event = events[offset]
            guard (sceneEndByHash[event.sceneHash] ?? .max) <= utf16Offset else { continue }
            for delta in event.deltas where delta.characterID == characterID {
                state[delta.field] = delta.value
            }
        }
        return state
    }

    // MARK: - 대화 질의 (PLAN §6.4·§10 대화 모드)

    /// 인물 말투 프로필 — 기본 존대 수준 + 최근 대사 예문 (PLAN §6.4).
    public struct SpeechProfile: Equatable, Sendable {
        /// 그 인물 발화 다수결 — 갈리면 nil (섣부른 신호보다 침묵).
        public let defaultPoliteness: Politeness?
        /// 최근 우선 예문, 문서 순서 (PLAN §6.4 "최근 우선, 결정적 수집").
        public let examples: [String]
    }

    /// (A→B) 방향 존대 사용 — 한국어 대화 예측의 핵심 신호 (PLAN §6.4 매트릭스).
    public enum HonorificUsage: String, Equatable, Sendable {
        case honorific = "존댓말"
        case plain = "반말"
        case mixed = "혼재"
    }

    /// 커서 이전 발화로 만드는 말투 프로필. 발화가 없으면 nil.
    public func speechProfile(
        of characterID: UUID, before utf16Offset: Int, maxExamples: Int = 2
    ) -> SpeechProfile? {
        let mine = utterances.filter {
            $0.speakerID == characterID && $0.utf16Start < utf16Offset
        }
        guard !mine.isEmpty else { return nil }
        var honorific = 0
        var plain = 0
        for utterance in mine {
            switch utterance.politeness {
            case .honorific: honorific += 1
            case .plain: plain += 1
            case nil: break
            }
        }
        let base: Politeness? =
            honorific > plain ? .honorific : plain > honorific ? .plain : nil
        let examples = mine.suffix(maxExamples).map {
            String($0.text.prefix(DialogueAttribution.maxExampleCharacters))
        }
        return SpeechProfile(defaultPoliteness: base, examples: examples)
    }

    /// (from → to) 방향의 존대 사용 — 커서 이전 발화만 fold (시점 차단).
    /// 어색한 존대가 반말로 무너지는 시점이 있다면 커서 위치가 그걸 반영한다.
    public func honorific(
        from speakerID: UUID, to listenerID: UUID, before utf16Offset: Int
    ) -> HonorificUsage? {
        var honorific = 0
        var plain = 0
        for utterance in utterances {
            guard utterance.utf16Start < utf16Offset,
                utterance.speakerID == speakerID,
                utterance.listenerID == listenerID
            else { continue }
            switch utterance.politeness {
            case .honorific: honorific += 1
            case .plain: plain += 1
            case nil: break
            }
        }
        if honorific == 0, plain == 0 { return nil }
        if plain == 0 { return .honorific }
        if honorific == 0 { return .plain }
        return .mixed
    }

    /// 다음 화자 추정 (PLAN §10 대화 모드 ①) — 직전 발화의 청자가 1순위,
    /// 없으면 직전 두 발화의 교대. 추정 불가면 nil (침묵이 정답).
    /// 반환: (다음 화자, 그 상대 = 직전 화자).
    public func expectedSpeaker(
        before utf16Offset: Int
    ) -> (speakerID: UUID, addresseeID: UUID)? {
        let prior = utterances.filter { $0.utf16Start < utf16Offset }
        guard let last = prior.last else { return nil }
        if let listener = last.listenerID {
            return (listener, last.speakerID)
        }
        // 청자 미상(3인 런 등) — 마지막과 다른 직전 화자로 교대 추정.
        if let previous = prior.last(where: { $0.speakerID != last.speakerID }) {
            return (previous.speakerID, last.speakerID)
        }
        return nil
    }
}
