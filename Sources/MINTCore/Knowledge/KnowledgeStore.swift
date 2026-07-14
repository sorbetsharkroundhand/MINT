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
    public static let currentSchemaVersion = 1

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

    public init(entryID: UUID) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generation = 0
        self.entryID = entryID
        self.sceneSummaries = [:]
        self.chapterSummaries = []
        self.workSummary = nil
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

    /// 저장 (원자적 쓰기). 현재 아웃라인에 없는 씬 요약은 여기서 정리한다 —
    /// 저장 시점이 곧 가비지 컬렉션이라 별도 청소 경로가 없다.
    public func save(pruningTo liveHashes: Set<String>? = nil) {
        var snapshot = self
        if let liveHashes {
            snapshot.sceneSummaries = snapshot.sceneSummaries.filter {
                liveHashes.contains($0.key)
            }
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

    public init(
        entryID: UUID,
        outline: DocumentOutline,
        summariesByHash: [String: String],
        chapterSummariesByPath: [String: String] = [:],
        workSummary: String? = nil
    ) {
        self.entryID = entryID
        self.outline = outline
        self.summariesByHash = summariesByHash
        self.chapterSummariesByPath = chapterSummariesByPath
        self.workSummary = workSummary
    }
}
