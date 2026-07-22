import Foundation
import SwiftUI

/// 저널 종류 — 일반 글쓰기와 소설 쓰기를 구분한다.
/// 본문은 같은 마크다운이지만, 사이드바 아이콘·에디터 크롬이 다르고
/// 이후 기능(자동완성 프롬프트·통계 등)이 여기서 갈라진다.
public enum EntryKind: String, Codable, Sendable {
    case journal
    case novel

    public var label: String {
        switch self {
        case .journal: "저널"
        case .novel: "소설"
        }
    }
}

/// 인물 카드가 작품에서 맡는 구조적 역할. 이름과 별개로 두어 이름 미상 화자를
/// `화자` 카드로 보여 주면서도 실제 이름이라고 오해하지 않게 한다 (PLAN §7).
public enum CharacterRole: String, Codable, Sendable, Equatable {
    case narrator = "화자"
}

/// 스토리 바이블 v0 — 사용자가 직접 쓰는 인물 카드 (PLAN §6.2·§7).
///
/// 사용자 저작 데이터이므로 파생 캐시(지식 사이드카)가 아니라 원문 스토어에
/// 산다 — 원문이 유일한 진실(CLAUDE.md §2-1). M6 자동 추출이 도입돼도 이
/// 카드는 잠금 취급이라 자동이 덮지 않는다 (CLAUDE.md §1-5).
public struct CharacterCard: Identifiable, Codable, Equatable, Sendable {
    /// 자동 화자 카드를 사용자가 삭제했을 때 다시 만들지 않는 거부 표식.
    public static let narratorRejectionMarker = "__MINT_AUTO_NARRATOR__"

    public var id: UUID
    /// 정식 이름 — 최근 창 언급 감지(카드 선택)의 키 (PLAN §11).
    public var name: String
    /// 별칭·호칭, 쉼표 구분 원문 그대로 보관 — 배열로 쪼개 저장하면 입력 중
    /// 쉼표·공백이 바인딩 왕복에서 먹혀 타이핑을 방해한다. 파싱은 조립기가 한다.
    public var aliases: String
    /// 성격·말투·관계 자유 기술 — 프롬프트 A 헤더에 그대로 실린다 (짧을수록 좋다).
    public var note: String
    /// 사용자 편집 잠금 (PLAN §6.2, CLAUDE.md §1-5 "사용자 수정이 자동 추출을
    /// 이긴다") — true면 백그라운드 프로파일링이 소개를 채우지 않는다.
    /// 소개를 직접 고치면 UI가 자동으로 잠근다. 옵셔널인 이유: 이전 저장
    /// 파일엔 키가 없어 nil(잠기지 않음)로 로드된다 (`folderID`와 같은 패턴).
    public var locked: Bool?
    /// HIGH 신뢰 감지로 자동 등록된 카드 (요구사항 §16) — UI가 표식을 달아
    /// 사용자가 알아보고 지울 수 있게 한다. 사용자가 카드를 편집하면 해제된다.
    public var autoRegistered: Bool?
    /// 이름과 분리된 구조적 역할. 레거시 카드에는 키가 없어 nil로 읽힌다.
    public var role: CharacterRole?

    public init(
        id: UUID = UUID(),
        name: String = "",
        aliases: String = "",
        note: String = "",
        locked: Bool? = nil,
        autoRegistered: Bool? = nil,
        role: CharacterRole? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.note = note
        self.locked = locked
        self.autoRegistered = autoRegistered
        self.role = role
    }
}

/// 저널 한 편 (에디터 v3 — 다중 저널).
public struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var body: String
    /// 소속 폴더. nil이면 루트 (파일시스템 v1 — 이전 파일엔 키가 없어 nil로 로드).
    public var folderID: UUID?
    /// 사용자가 직접 제목을 바꿨는가 — true면 본문에서 자동 파생하지 않는다.
    /// 레거시 파일엔 없는 키(옵셔널) — nil이면 "기본 제목일 때만" 자동 파생을 허용해
    /// 예전에 붙여 둔 이름은 보존한다.
    public var titleIsCustom: Bool?
    /// 저널 종류. 레거시 파일엔 없는 키 — nil이면 일반 글쓰기(journal).
    public var kind: EntryKind?
    /// 작품 장르 (소설 메타, PLAN §5) — 예측 프롬프트 A 헤더에 실린다.
    /// 사용자 저작 데이터라 파생 캐시가 아닌 여기 산다. 레거시 파일엔 없는 키.
    public var genre: String?
    /// 스토리 바이블 v0 — 인물 카드 (PLAN §7). 레거시 파일엔 없는 키.
    public var characters: [CharacterCard]?
    /// 인물 감지에서 사용자가 "무시"한 이름들 (M6, PLAN §7 거부 목록) —
    /// 같은 후보를 다시 묻지 않는다. 사용자 결정이므로 파생 캐시가 아니라 여기 산다.
    public var rejectedCharacterNames: [String]?
    /// 폴더 안 표시 순서 (사이드바 DnD 재정렬). 레거시 파일엔 없는 키 —
    /// nil이면 로드 시 기존 표시 순서(작성일 내림차순)로 시드된다.
    public var sortOrder: Double?
    /// AI 분석 결과에 대한 사용자 수정 (Narrative Intelligence, PLAN §6.5).
    /// **사용자 결정이라 파생 캐시(사이드카)가 아니라 여기 산다** — 사이드카는
    /// 스키마 변경 시 통째로 버려지지만 이 목록은 살아남아, 재분석·재구축이
    /// 사용자 수정을 절대 덮지 못한다 (CLAUDE.md §1-5). 레거시 파일엔 없는 키.
    public var narrativeOverrides: [NarrativeOverride]?
    /// 높은 신뢰 규칙으로 자동 기록한 대화 (PLAN §6.6). 사용자에게 보이고 삭제할
    /// 수 있는 기억이라 entries.json에 두며, 재분석이 임의로 지우지 않는다.
    public var recordedConversations: [RecordedConversation]?
    /// 작가가 직접 관리하는 sparse 핵심 장면 (PLAN §14 M11). 파생 캐시가 아닌
    /// 사용자 데이터이며, 레거시 entries.json에는 키가 없어 nil로 로드된다.
    public var keyScenes: [KeyScene]?
    /// 사용자가 무시한 비영속 후보의 입력 해시. 같은 입력을 다시 묻지 않는다.
    public var rejectedKeySceneCandidateHashes: [String]?

    public init(
        id: UUID = UUID(),
        title: String = "새 저널",
        createdAt: Date = .now,
        body: String = "",
        folderID: UUID? = nil,
        titleIsCustom: Bool? = nil,
        kind: EntryKind? = nil,
        genre: String? = nil,
        characters: [CharacterCard]? = nil,
        rejectedCharacterNames: [String]? = nil,
        sortOrder: Double? = nil,
        narrativeOverrides: [NarrativeOverride]? = nil,
        recordedConversations: [RecordedConversation]? = nil,
        keyScenes: [KeyScene]? = nil,
        rejectedKeySceneCandidateHashes: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.body = body
        self.folderID = folderID
        self.titleIsCustom = titleIsCustom
        self.kind = kind
        self.genre = genre
        self.characters = characters
        self.rejectedCharacterNames = rejectedCharacterNames
        self.sortOrder = sortOrder
        self.narrativeOverrides = narrativeOverrides
        self.recordedConversations = recordedConversations
        self.keyScenes = keyScenes
        self.rejectedKeySceneCandidateHashes = rejectedKeySceneCandidateHashes
    }

    /// 옵셔널 kind의 확정값 — 레거시(nil)는 전부 일반 글쓰기.
    public var resolvedKind: EntryKind {
        kind ?? .journal
    }

    /// 자동으로 붙는 기본 제목들 — 이 이름이면 본문에서 파생해도 사용자 의도를 해치지 않는다.
    static let placeholderTitles: Set<String> = ["새 저널", "새 소설", "저널", "제목 없음", ""]

    /// 본문에서 제목을 자동 파생해도 되는가.
    var allowsAutoTitle: Bool {
        if let titleIsCustom { return !titleIsCustom }
        // 레거시 파일: 기본 제목일 때만 자동 파생 — 직접 붙인 이름은 그대로 둔다.
        return Self.placeholderTitles.contains(title)
    }
}

/// 저널을 프로젝트처럼 묶는 폴더 (파일시스템 v1). parentID로 중첩된다.
public struct JournalFolder: Identifiable, Codable, Equatable, Sendable {
    /// 자동 생성 폴더의 기본 이름 — AI 명명(renameFolderIfPlaceholder)은 이름이
    /// 아직 이 값일 때만 덮어쓴다 (사용자가 먼저 바꾸면 그쪽이 이긴다).
    public static let placeholderName = "새 폴더"

    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var createdAt: Date
    /// 형제 폴더 사이 표시 순서 (사이드바 DnD 재정렬). 레거시 파일엔 없는 키 —
    /// nil이면 로드 시 기존 배열 순서로 시드된다.
    public var sortOrder: Double?

    public init(
        id: UUID = UUID(),
        name: String = JournalFolder.placeholderName,
        parentID: UUID? = nil,
        createdAt: Date = .now,
        sortOrder: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

/// 사이드바 정렬 비교에 필요한 공통 필드 — JournalEntry·JournalFolder 공용.
protocol SortOrderable {
    var id: UUID { get }
    var createdAt: Date { get }
    var sortOrder: Double? { get }
}

extension JournalEntry: SortOrderable {}
extension JournalFolder: SortOrderable {}

/// 여러 저널을 로컬 JSON 하나에 보관하는 스토어 (에디터 v3).
///
/// - 저장 위치: `~/Documents/MINT/entries.json`
/// - 본문 타이핑은 디바운스 autosave, 생성/삭제/이름변경 같은 구조 변경은 즉시 저장.
/// - 첫 실행 시 M1의 단일 문서(`journal.md`)가 있으면 첫 저널로 이관한다
///   (원본 파일은 안전을 위해 남겨둔다).
/// - 목록은 항상 1편 이상 유지한다 — 마지막 저널을 지우면 빈 저널을 새로 만든다.
@MainActor
public final class EntryStore: ObservableObject {
    @Published public private(set) var entries: [JournalEntry]
    @Published public private(set) var folders: [JournalFolder]
    @Published public private(set) var activeID: UUID
    /// 사이드바에서 펼쳐진 폴더들 — 함께 저장해 재실행 시 트리 모양을 유지한다.
    @Published public private(set) var expandedFolderIDs: Set<UUID>
    /// 에디터에 포커스를 달라는 요청 카운터 — 새 저널 생성 시 올려, 곧바로 타이핑할
    /// 수 있게 한다("＋ 누르고 다시 클릭해야 써지는" 마찰 제거). 이름 변경과 충돌하지
    /// 않도록 선택(select)에서는 올리지 않는다.
    @Published public private(set) var editorFocusRequests = 0

    /// 에디터 포커스를 명시적으로 요청한다.
    public func requestEditorFocus() {
        editorFocusRequests += 1
    }

    /// 사이드바 검색 필드에 포커스를 달라는 요청 카운터 (⌘⇧F).
    @Published public private(set) var searchFocusRequests = 0

    public func requestSearchFocus() {
        searchFocusRequests += 1
    }

    /// 전역 검색 결과 클릭 → 에디터가 해당 저널의 매치 위치로 스크롤·표시하라는
    /// 요청. seq가 바뀔 때만 한 번 소비된다 (같은 결과를 다시 눌러도 다시 이동).
    public struct SearchJump: Equatable, Sendable {
        public let entryID: UUID
        public let query: String
        public let seq: Int
    }

    @Published public private(set) var searchJump: SearchJump?

    /// 검색 결과 선택 — 저널을 열고 본문 매치 위치로 이동을 요청한다.
    /// 타임라인의 씬·사건·경고 클릭(M7)도 이 통로를 쓴다: 본문 스니펫을
    /// 질의로 넘기면 마크다운 오프셋 ↔ 에디터 스토리지 오프셋의 좌표 불일치를
    /// 구조적으로 피한다 (에디터는 자기 텍스트에서 스니펫을 찾아 이동).
    public func requestSearchJump(_ id: UUID, query: String) {
        select(id)
        searchJump = SearchJump(entryID: id, query: query, seq: (searchJump?.seq ?? 0) + 1)
    }

    /// 문서 종류 전환 (저널⇄소설) — 원문은 그대로, 메타만 바뀐다.
    /// 소설로 바꾸면 다음 유휴부터 이해 파이프라인이 돌기 시작한다.
    public func setKind(_ kind: EntryKind, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].resolvedKind != kind
        else { return }
        entries[index].kind = kind
        scheduleSave()
        // 전환도 인덱서에겐 신호 — 소설이 됐으면 유휴 타이머를 감는다.
        documentDidChange?(id)
    }

    /// 제목·본문에서 질의어를 포함하는 저널 (대소문자 무시). 전역 검색용.
    public func search(_ query: String) -> [JournalEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return entries.filter {
            $0.title.range(of: q, options: .caseInsensitive) != nil
                || $0.body.range(of: q, options: .caseInsensitive) != nil
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// 본문 autosave까지 기다리는 시간. 입력이 멈춘 뒤에만 쓴다.
    private let autosaveDelay: Duration
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    /// 앱 수명주기 훅(AppDelegate)이 종료·백그라운드 전환 직전 flush할 수 있도록
    /// 하는 약참조. 메인 스레드에서만 읽고 쓴다.
    public nonisolated(unsafe) weak static var current: EntryStore?

    /// 본문 편집·문서 전환 알림 (M6) — BackgroundIndexer가 배선한다.
    /// 지식 로직은 여기 두지 않는다 (CLAUDE.md §4) — 신호만 내보낸다.
    public var documentDidChange: ((UUID) -> Void)?

    private struct Snapshot: Codable {
        var entries: [JournalEntry]
        var activeID: UUID?
        // 파일시스템 v1 이전 파일엔 없는 키 — 옵셔널로 하위 호환.
        var folders: [JournalFolder]?
        var expandedFolderIDs: [UUID]?
    }

    public init(autosaveDelay: Duration = .milliseconds(800)) {
        self.autosaveDelay = autosaveDelay
        let dir = Self.storageDirectory()
        fileURL = dir.appendingPathComponent("entries.json", isDirectory: false)

        let loaded = Self.loadSnapshot(from: fileURL) ?? Self.migratedOrEmptySnapshot(in: dir)
        var entries = loaded.entries
        if entries.isEmpty { entries = [JournalEntry()] }
        // 마이그레이션: 예전 파생 버그로 제목에 인라인 마크업(<font …>)이 얼어붙은
        // 항목 정리. 파생 제목은 본문에서 다시 만들고, 직접 지은 이름은 글자를
        // 보존한 채 태그만 벗긴다 (제목에 태그가 남는 건 어느 쪽이든 의도가 아니다).
        for index in entries.indices where entries[index].title.contains("<") {
            if entries[index].titleIsCustom == true {
                let cleaned = Self.strippedInlineTags(entries[index].title)
                    .trimmingCharacters(in: .whitespaces)
                entries[index].title = cleaned.isEmpty ? "제목 없음" : cleaned
            } else {
                let derived = Self.derivedTitle(from: entries[index].body)
                entries[index].title = derived.isEmpty ? "새 저널" : derived
                entries[index].titleIsCustom = false
            }
        }
        var folders = loaded.folders ?? []
        // 마이그레이션: sortOrder 없는 항목(DnD 재정렬 도입 이전 파일)은 기존 표시
        // 순서 그대로 시드한다 — 엔트리는 폴더별 작성일 내림차순(M5), 폴더는 배열
        // 순서. 메모리만 바꾸고 저장은 첫 구조 변경 때 이뤄진다.
        if entries.contains(where: { $0.sortOrder == nil })
            || folders.contains(where: { $0.sortOrder == nil }) {
            Self.seedSortOrders(entries: &entries, folders: &folders)
        }
        self.entries = entries
        self.folders = folders
        expandedFolderIDs = Set(loaded.expandedFolderIDs ?? [])
            .intersection(folders.map(\.id))
        activeID = loaded.activeID.flatMap { id in
            entries.contains(where: { $0.id == id }) ? id : nil
        } ?? entries[0].id
        Self.current = self
    }

    /// `~/Documents/MINT/` 경로. 디렉터리가 없으면 만든다.
    private static func storageDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MINT", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func loadSnapshot(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// M1 단일 문서(journal.md) 이관 — 없으면 빈 저널 하나로 시작.
    private static func migratedOrEmptySnapshot(in dir: URL) -> Snapshot {
        let legacy = dir.appendingPathComponent("journal.md", isDirectory: false)
        guard let body = try? String(contentsOf: legacy, encoding: .utf8),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return Snapshot(entries: [JournalEntry()], activeID: nil)
        }
        let modified =
            (try? FileManager.default.attributesOfItem(atPath: legacy.path)[.modificationDate])
                as? Date ?? .now
        let entry = JournalEntry(
            title: Self.derivedTitle(from: body), createdAt: modified, body: body
        )
        return Snapshot(entries: [entry], activeID: entry.id)
    }

    /// sortOrder가 없는 파일을 위한 시드 — 사용자가 보던 순서를 그대로 굳힌다.
    /// 엔트리는 폴더별 작성일 내림차순(도입 전 표시 순서), 폴더는 배열 순서.
    /// nil이 섞인 형제 그룹만 다시 시드한다 — 이미 손으로 정렬한 폴더는 건드리지 않는다.
    private static func seedSortOrders(
        entries: inout [JournalEntry], folders: inout [JournalFolder]
    ) {
        let entryGroups = Dictionary(grouping: entries.indices) { entries[$0].folderID }
        for indices in entryGroups.values
            where indices.contains(where: { entries[$0].sortOrder == nil }) {
            let ordered = indices.sorted { entries[$0].createdAt > entries[$1].createdAt }
            for (position, index) in ordered.enumerated() {
                entries[index].sortOrder = Double(position)
            }
        }
        let folderGroups = Dictionary(grouping: folders.indices) { folders[$0].parentID }
        for indices in folderGroups.values
            where indices.contains(where: { folders[$0].sortOrder == nil }) {
            for (position, index) in indices.sorted().enumerated() {
                folders[index].sortOrder = Double(position)
            }
        }
    }

    /// 첫 비어 있지 않은 줄에서 마크다운 마커·인라인 마크업을 벗겨 제목으로 쓴다.
    /// 본문이 길어도 앞부분만 훑는다 — 매 키 입력마다 호출되므로 비용을 묶어 둔다.
    /// 파생할 내용이 없으면 빈 문자열(호출부에서 기본 제목으로 대체).
    /// 인라인 래퍼 태그(<font …>·</font>·<p align="…">·</p>)만 벗긴다 —
    /// 안의 글자는 남는다. 제목 파생·마이그레이션 공용.
    static func strippedInlineTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"</?(?:font|p)\b[^>]*>"#,
            with: "", options: .regularExpression
        )
    }

    static func derivedTitle(from body: String) -> String {
        for line in body.prefix(500).split(separator: "\n") {
            var stripped = strippedInlineTags(
                String(line)
                    // 블록 마커 (#·>·목록·번호) 제거.
                    .replacingOccurrences(
                        of: #"^(#{1,3}\s+|>\s?|- \[[ x]\]\s?|[-*]\s+|\d+\.\s+)"#,
                        with: "", options: .regularExpression
                    )
            )
            // 인라인 마커(*** ** * `)도 글자만 남긴다.
            .replacingOccurrences(
                of: #"[*`]+"#,
                with: "", options: .regularExpression
            )
            stripped = stripped.trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            // 산문이 아닌 줄(수식·이미지·코드 펜스·구분선)은 제목이 될 수 없다.
            if stripped.hasPrefix("$$") || stripped.hasPrefix("![") { continue }
            if stripped.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
                continue
            }
            return String(stripped.prefix(30))
        }
        return ""
    }

    // MARK: - 조회

    public var activeEntry: JournalEntry? {
        entries.first(where: { $0.id == activeID })
    }

    /// 한 폴더의 하위 폴더들 (nil = 루트). 사용자 정렬(sortOrder) 순.
    public func childFolders(of parentID: UUID?) -> [JournalFolder] {
        folders.filter { $0.parentID == parentID }
            .sorted(by: Self.bySortOrder)
    }

    /// 한 폴더에 담긴 저널들 (nil = 루트). 사용자 정렬(sortOrder) 순 — DnD 재정렬
    /// 도입으로 작성일 내림차순(M5)은 초기 시드로만 남는다. 이에 따라 setDate(L9)는
    /// 더 이상 목록 위치를 바꾸지 않는다 (검색 결과는 여전히 작성일 순).
    public func childEntries(of folderID: UUID?) -> [JournalEntry] {
        entries.filter { $0.folderID == folderID }
            .sorted(by: Self.bySortOrder)
    }

    /// sortOrder 오름차순, nil은 뒤로. 동률은 작성일 내림차순 → id로 안정화.
    private static func bySortOrder(
        _ a: some SortOrderable, _ b: some SortOrderable
    ) -> Bool {
        switch (a.sortOrder, b.sortOrder) {
        case let (x?, y?) where x != y: return x < y
        case (.some, .none): return true
        case (.none, .some): return false
        default:
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    public func isExpanded(_ folderID: UUID) -> Bool {
        expandedFolderIDs.contains(folderID)
    }

    /// 폴더 안에 저널이나 하위 폴더가 하나라도 있는지 — 삭제 확인 알림용.
    public func folderHasContents(_ folderID: UUID) -> Bool {
        entries.contains(where: { $0.folderID == folderID })
            || folders.contains(where: { $0.parentID == folderID })
    }

    /// id와 그 아래 모든 하위 폴더 id — 재귀 삭제 범위.
    private func descendantFolderIDs(of folderID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [folderID]
        var queue = [folderID]
        while let current = queue.popLast() {
            for child in folders where child.parentID == current {
                if result.insert(child.id).inserted { queue.append(child.id) }
            }
        }
        return result
    }

    /// 툴바 제목 — "7월 3일 금요일".
    public var activeDateLabel: String {
        guard let entry = activeEntry else { return "" }
        return Self.fullDateFormatter.string(from: entry.createdAt)
    }

    /// 사이드바 보조 라벨 — 오늘/어제/요일 한 글자/짧은 날짜.
    public func dayLabel(for entry: JournalEntry) -> String {
        let calendar = Self.koCalendar
        if calendar.isDateInToday(entry.createdAt) { return "오늘" }
        if calendar.isDateInYesterday(entry.createdAt) { return "어제" }
        let days =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: entry.createdAt),
                to: calendar.startOfDay(for: .now)
            ).day ?? .max
        if days < 7 { return Self.weekdayFormatter.string(from: entry.createdAt) }
        return Self.shortDateFormatter.string(from: entry.createdAt)
    }

    // MARK: - 변경

    public func select(_ id: UUID) {
        guard id != activeID, entries.contains(where: { $0.id == id }) else { return }
        activeID = id
        // 전환은 잦고 activeID만 바뀐다 — 동기 디스크 쓰기 대신 디바운스 저장.
        scheduleSave()
        // 문서 전환도 인덱서에겐 "활동" — 새 문서의 유휴 타이머를 감는다 (M6).
        documentDidChange?(id)
    }

    @discardableResult
    public func newEntry(in folderID: UUID? = nil, kind: EntryKind = .journal) -> UUID {
        // titleIsCustom=false — 이름을 직접 바꾸기 전까지 본문에서 계속 파생한다.
        // (nil이면 첫 파생 직후 제목이 플레이스홀더가 아니게 돼 한 글자에서 얼어붙는다.)
        let entry = JournalEntry(
            title: kind == .novel ? "새 소설" : "새 저널", folderID: folderID,
            titleIsCustom: false, kind: kind,
            // 새 저널은 목록 맨 위 — 첫 형제보다 작은 sortOrder.
            sortOrder: (childEntries(of: folderID).first?.sortOrder ?? 0) - 1
        )
        entries.insert(entry, at: 0)
        activeID = entry.id
        // 새 저널이 접힌 폴더 안에 숨지 않게 부모를 펼친다.
        if let folderID { expandedFolderIDs.insert(folderID) }
        // 새 저널은 곧바로 쓸 수 있게 에디터로 포커스를 옮긴다.
        editorFocusRequests += 1
        saveNow()
        return entry.id
    }

    public func delete(_ id: UUID) {
        entries.removeAll(where: { $0.id == id })
        if entries.isEmpty { entries = [JournalEntry()] }
        if !entries.contains(where: { $0.id == activeID }) { activeID = entries[0].id }
        saveNow()
        pruneOrphanImages()
    }

    /// 어떤 저널에서도 더 이상 참조하지 않는 이미지 파일을 정리한다 (삭제 후, L4).
    private func pruneOrphanImages() {
        var referenced: Set<String> = []
        for entry in entries {
            let ns = entry.body as NSString
            Self.imageRefPattern.enumerateMatches(
                in: entry.body, range: NSRange(location: 0, length: ns.length)
            ) { match, _, _ in
                if let m = match, m.numberOfRanges > 1 {
                    referenced.insert(ns.substring(with: m.range(at: 1)))
                }
            }
        }
        MintImageStore.pruneUnreferenced(keeping: referenced)
    }

    // 정적 리터럴 실패는 프로그래머 오류라 복구할 수 없다.
    // swiftlint:disable:next force_try
    private static let imageRefPattern = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(([^)\s]+)\)"#
    )

    /// 저널의 작성일을 바꾼다 — 어제 일을 오늘 적었을 때 날짜를 맞추도록 (L9).
    public func setDate(_ id: UUID, to date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].createdAt != date
        else { return }
        entries[index].createdAt = date
        saveNow()
    }

    /// 저널을 다른 폴더(또는 루트=nil)로 옮긴다 — 이미 만든 글도 정리할 수 있게.
    /// (컨텍스트 메뉴 "이동"용 — 위치는 대상 폴더 맨 끝.)
    public func move(_ id: UUID, toFolder folderID: UUID?) {
        moveEntry(id, toFolder: folderID, before: nil)
    }

    // MARK: - 정렬·이동 (사이드바 DnD)

    /// 저널을 대상 폴더로 옮기고 beforeID 앞에 놓는다 (nil = 맨 끝).
    /// 같은 폴더 안이면 순수 재정렬. 이동 후 형제 그룹 전체를 0…n으로 재번호한다 —
    /// 목록이 작아 분수 순서 관리보다 단순한 쪽을 택한다.
    public func moveEntry(_ id: UUID, toFolder folderID: UUID?, before beforeID: UUID?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        // 드래그한 항목을 뺀 형제 목록에 삽입 위치를 잡는다 — 같은 목록 안 이동도
        // 인덱스가 어긋나지 않는다.
        var siblings = childEntries(of: folderID).filter { $0.id != id }
        let insertAt = beforeID.flatMap { b in siblings.firstIndex { $0.id == b } }
            ?? siblings.count
        var moved = entries[index]
        let orderUnchanged = moved.folderID == folderID
            && childEntries(of: folderID).firstIndex(where: { $0.id == id }) == insertAt
        guard !orderUnchanged else { return }
        moved.folderID = folderID
        siblings.insert(moved, at: insertAt)
        renumberEntries(siblings)
        entries[index].folderID = folderID
        // 옮긴 저널이 접힌 폴더에 숨지 않게 대상 폴더를 펼친다.
        if let folderID { expandedFolderIDs.insert(folderID) }
        saveNow()
    }

    /// 폴더를 다른 부모로 옮기고 beforeID 앞에 놓는다 (nil = 맨 끝).
    /// 자기 자신·자기 자손으로의 이동은 거부한다 (순환 방지).
    @discardableResult
    public func moveFolder(_ id: UUID, toParent parentID: UUID?, before beforeID: UUID?) -> Bool {
        guard canMoveFolder(id, toParent: parentID),
              let index = folders.firstIndex(where: { $0.id == id })
        else { return false }
        var siblings = childFolders(of: parentID).filter { $0.id != id }
        let insertAt = beforeID.flatMap { b in siblings.firstIndex { $0.id == b } }
            ?? siblings.count
        var moved = folders[index]
        let orderUnchanged = moved.parentID == parentID
            && childFolders(of: parentID).firstIndex(where: { $0.id == id }) == insertAt
        guard !orderUnchanged else { return true }
        moved.parentID = parentID
        siblings.insert(moved, at: insertAt)
        renumberFolders(siblings)
        folders[index].parentID = parentID
        if let parentID { expandedFolderIDs.insert(parentID) }
        saveNow()
        return true
    }

    /// 폴더를 해당 부모로 옮겨도 되는가 — 드롭 중 시각 피드백(forbidden)용.
    /// 자기 자신 또는 자기 자손 폴더 안으로는 옮길 수 없다.
    public func canMoveFolder(_ id: UUID, toParent parentID: UUID?) -> Bool {
        guard let parentID else { return true }
        return !descendantFolderIDs(of: id).contains(parentID)
    }

    /// 저널을 저널 위에 떨어뜨리면 둘을 묶는 새 폴더를 만든다 (사이드바 DnD).
    /// 대상 저널이 있던 폴더 아래, 폴더 블록 맨 끝에 생긴다. 이름은 플레이스홀더 —
    /// 호출부가 AI 명명(requestFolderName)을 이어서 요청한다.
    @discardableResult
    public func createFolder(merging draggedID: UUID, onto targetID: UUID) -> UUID? {
        guard draggedID != targetID,
              let target = entries.first(where: { $0.id == targetID }),
              entries.contains(where: { $0.id == draggedID })
        else { return nil }
        let parent = target.folderID
        let folder = JournalFolder(
            parentID: parent,
            // 폴더 블록 맨 끝 — 대상 저널이 있던 엔트리 영역과 시각적으로 가깝게.
            sortOrder: (childFolders(of: parent).last?.sortOrder ?? -1) + 1
        )
        folders.insert(folder, at: 0)
        expandedFolderIDs.insert(folder.id)
        // 대상을 먼저, 드래그한 저널을 그 뒤에 — 떨어뜨린 방향 그대로 읽히게.
        moveEntryWithoutSave(targetID, toFolder: folder.id, position: 0)
        moveEntryWithoutSave(draggedID, toFolder: folder.id, position: 1)
        saveNow()
        return folder.id
    }

    /// 이름이 아직 자동 생성 기본값("새 폴더")일 때만 바꾼다 — AI 명명이 끝나기 전에
    /// 사용자가 직접 이름을 붙였다면 그쪽을 존중한다.
    public func renameFolderIfPlaceholder(_ id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }),
              folders[index].name == JournalFolder.placeholderName
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders[index].name = trimmed
        saveNow()
    }

    /// 펼침 전용 — 드래그 hover 스프링 로딩용. toggle이 아니라서 hover 중
    /// 재호출돼도 도로 접히지 않는다.
    public func expand(_ folderID: UUID) {
        guard !expandedFolderIDs.contains(folderID),
              folders.contains(where: { $0.id == folderID })
        else { return }
        expandedFolderIDs.insert(folderID)
        saveNow()
    }

    /// AI 폴더 명명 입력 — 멤버 저널의 제목 + 본문 앞부분을 이어 붙인다.
    public func folderNamingContext(for folderID: UUID, maxCharacters: Int) -> String {
        let members = childEntries(of: folderID)
        guard !members.isEmpty else { return "" }
        let joined = members.enumerated().map { index, entry in
            "[문서 \(index + 1)] 제목: \(entry.title)\n\(entry.body.prefix(300))"
        }
        .joined(separator: "\n\n")
        return String(joined.prefix(maxCharacters))
    }

    /// folderID 변경 + 지정 위치 삽입 — createFolder(merging:) 내부 전용
    /// (saveNow는 호출부가 한 번만).
    private func moveEntryWithoutSave(_ id: UUID, toFolder folderID: UUID?, position: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var siblings = childEntries(of: folderID).filter { $0.id != id }
        var moved = entries[index]
        moved.folderID = folderID
        siblings.insert(moved, at: min(position, siblings.count))
        renumberEntries(siblings)
        entries[index].folderID = folderID
    }

    /// 형제 그룹을 표시 순서대로 0…n 재번호 — sortOrder를 항상 촘촘하게 유지한다.
    private func renumberEntries(_ ordered: [JournalEntry]) {
        for (position, sibling) in ordered.enumerated() {
            if let i = entries.firstIndex(where: { $0.id == sibling.id }) {
                entries[i].sortOrder = Double(position)
            }
        }
    }

    private func renumberFolders(_ ordered: [JournalFolder]) {
        for (position, sibling) in ordered.enumerated() {
            if let i = folders.firstIndex(where: { $0.id == sibling.id }) {
                folders[i].sortOrder = Double(position)
            }
        }
    }

    /// 메뉴에서 "이름 바꾸기"를 눌렀을 때 사이드바가 현재 저널의 인라인 편집을
    /// 시작하도록 하는 요청 카운터.
    @Published public private(set) var renameRequests = 0

    public func requestRename() {
        renameRequests += 1
    }

    // MARK: - 폴더 변경

    @discardableResult
    public func newFolder(in parentID: UUID? = nil) -> UUID {
        let folder = JournalFolder(
            parentID: parentID,
            // 새 폴더는 형제 폴더 맨 위.
            sortOrder: (childFolders(of: parentID).first?.sortOrder ?? 0) - 1
        )
        folders.insert(folder, at: 0)
        expandedFolderIDs.insert(folder.id)
        if let parentID { expandedFolderIDs.insert(parentID) }
        saveNow()
        return folder.id
    }

    public func renameFolder(_ id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folders[index].name = trimmed.isEmpty ? "제목 없음" : trimmed
        saveNow()
    }

    /// 폴더와 그 안의 하위 폴더·저널을 전부 삭제한다.
    public func deleteFolder(_ id: UUID) {
        let doomed = descendantFolderIDs(of: id)
        folders.removeAll { doomed.contains($0.id) }
        entries.removeAll { entry in entry.folderID.map(doomed.contains) ?? false }
        expandedFolderIDs.subtract(doomed)
        if entries.isEmpty { entries = [JournalEntry()] }
        if !entries.contains(where: { $0.id == activeID }) { activeID = entries[0].id }
        saveNow()
        pruneOrphanImages()
    }

    public func toggleExpanded(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
        saveNow()
    }

    public func rename(_ id: UUID, to title: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].title = trimmed.isEmpty ? "제목 없음" : trimmed
        // 사용자가 직접 붙인 이름 — 이후 본문 편집으로 덮어쓰지 않는다.
        entries[index].titleIsCustom = true
        saveNow()
    }

    // MARK: - 작품 메타·인물 카드 (스토리 바이블 v0, PLAN §7)

    /// 예측 조립에 쓰는 활성 문서 스냅샷 — CompletionController가 예측 직전
    /// pull한다 (값 복사로 actor 격리 경계를 넘긴다, CompletionParameters 패턴).
    public var activeDocumentContext: DocumentContext? {
        guard let entry = activeEntry else { return nil }
        return DocumentContext(
            // 플레이스홀더 제목은 신호가 아니라 소음 — 헤더에서 뺀다.
            title: JournalEntry.placeholderTitles.contains(entry.title) ? "" : entry.title,
            kind: entry.resolvedKind,
            genre: entry.genre,
            characters: entry.characters ?? []
        )
    }

    /// 작품 장르 갱신 — 바이블 팝오버의 타이핑 필드라 디바운스 저장.
    public func setGenre(_ genre: String, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard entries[index].genre != value else { return }
        entries[index].genre = value
        scheduleSave()
    }

    /// 인물 카드 추가/수정 — 팝오버 텍스트 필드가 매 키 입력마다 부르므로 디바운스 저장.
    public func upsertCharacter(_ card: CharacterCard, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var cards = entries[index].characters ?? []
        if let i = cards.firstIndex(where: { $0.id == card.id }) {
            guard cards[i] != card else { return }
            cards[i] = card
        } else {
            cards.append(card)
        }
        entries[index].characters = cards
        scheduleSave()
    }

    /// 인물 감지 후보 "무시" — 거부 목록에 넣어 같은 후보를 다시 묻지 않는다
    /// (M6, PLAN §7). 사용자 결정 = 구조 변경이라 즉시 저장.
    public func rejectCharacterName(_ name: String, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var rejected = entries[index].rejectedCharacterNames ?? []
        guard !rejected.contains(name) else { return }
        rejected.append(name)
        entries[index].rejectedCharacterNames = rejected
        saveNow()
    }

    // MARK: - Narrative 사용자 수정 (PLAN §6.5, CLAUDE.md §1-5)

    /// 오버라이드 변경 알림 — ContentView가 인덱서의 오버레이 재적용
    /// (`rehydrate`)에 배선한다. LLM 없이 스냅샷만 다시 조립하는 신호다.
    public var narrativeOverridesDidChange: ((UUID) -> Void)?

    /// AI 분석 결과 수정 저장 — 같은 (kind, key)는 최신 값으로 대체된다.
    /// 사용자 결정 = 구조 변경이라 즉시 저장 (rejectCharacterName과 같은 규칙).
    public func setNarrativeOverride(_ override: NarrativeOverride, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var overrides = entries[index].narrativeOverrides ?? []
        overrides.removeAll { $0.kind == override.kind && $0.key == override.key }
        overrides.append(override)
        entries[index].narrativeOverrides = overrides
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    /// 오버라이드 제거 — "AI 분석으로 되돌리기".
    public func removeNarrativeOverride(
        kind: NarrativeOverride.Kind, key: String, in id: UUID
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              var overrides = entries[index].narrativeOverrides,
              overrides.contains(where: { $0.kind == kind && $0.key == key })
        else { return }
        overrides.removeAll { $0.kind == kind && $0.key == key }
        entries[index].narrativeOverrides = overrides.isEmpty ? nil : overrides
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    // MARK: - 자동 기록된 대화 (PLAN §6.6)

    /// 높은 신뢰의 대화 자동 기록 — 즉시 저장하고 스냅샷을 재조립한다. 같은
    /// 대화를 이어 쓰면 겹치는 짧은 기록을 새 항목으로 쌓지 않고 하나로 확장한다.
    public func recordConversation(_ record: RecordedConversation, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let previous = entries[index].recordedConversations ?? []
        let records = ConversationDetector.merging(record, into: previous)
        guard records != previous else { return }
        entries[index].recordedConversations = records
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    /// 기록 삭제 — 사용자만 지울 수 있다 (재분석은 절대 지우지 않는다).
    public func removeRecordedConversation(id recordID: UUID, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              var records = entries[index].recordedConversations,
              records.contains(where: { $0.id == recordID })
        else { return }
        records.removeAll { $0.id == recordID }
        entries[index].recordedConversations = records.isEmpty ? nil : records
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    // MARK: - 핵심 장면 (PLAN §14 M11)

    /// 작가의 추가·수정은 즉시 저장한다. 범위형 장면은 재앵커 근거도 함께 보존한다.
    public func upsertKeyScene(_ scene: KeyScene, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var scene = scene
        scene.importance = min(5, max(1, scene.importance))
        if scene.sourceRange != nil, scene.anchorSnippet?.isEmpty != false {
            scene.anchorSnippet = KeySceneReconciler.snippet(
                in: entries[index].body, range: scene.sourceRange
            )
        }
        scene.anchorSnippet = scene.anchorSnippet.map { String($0.prefix(40)) }
        scene.updatedAt = .now
        var scenes = entries[index].keyScenes ?? []
        if let offset = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[offset] = scene
        } else {
            scenes.append(scene)
        }
        entries[index].keyScenes = scenes
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    public func removeKeyScene(id sceneID: UUID, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              var scenes = entries[index].keyScenes,
              scenes.contains(where: { $0.id == sceneID })
        else { return }
        scenes.removeAll { $0.id == sceneID }
        entries[index].keyScenes = scenes.isEmpty ? nil : scenes
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    public func confirmKeyScene(id sceneID: UUID, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              var scenes = entries[index].keyScenes,
              let offset = scenes.firstIndex(where: { $0.id == sceneID })
        else { return }
        scenes[offset].status = .confirmed
        scenes[offset].authorConfirmed = true
        scenes[offset].updatedAt = .now
        entries[index].keyScenes = scenes
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    public func rejectKeySceneCandidate(inputHash: String, in id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var hashes = entries[index].rejectedKeySceneCandidateHashes ?? []
        guard !hashes.contains(inputHash) else { return }
        hashes.append(inputHash)
        entries[index].rejectedKeySceneCandidateHashes = hashes
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    /// 두 장면을 첫 장면의 안정 UUID로 합친다. 작가가 쓴 필드는 우선 보존한다.
    public func mergeKeyScenes(keeping keptID: UUID, removing removedID: UUID, in id: UUID) {
        guard keptID != removedID,
              let index = entries.firstIndex(where: { $0.id == id }),
              var scenes = entries[index].keyScenes,
              let kept = scenes.firstIndex(where: { $0.id == keptID }),
              let removed = scenes.firstIndex(where: { $0.id == removedID })
        else { return }
        let other = scenes[removed]
        if scenes[kept].summary.isEmpty { scenes[kept].summary = other.summary }
        if scenes[kept].sourceRange == nil { scenes[kept].sourceRange = other.sourceRange }
        scenes[kept].characters = Array(Set(scenes[kept].characters + other.characters))
        scenes[kept].linkedEventKeys = Array(
            Set(scenes[kept].linkedEventKeys + other.linkedEventKeys)
        )
        scenes[kept].importance = max(scenes[kept].importance, other.importance)
        scenes[kept].authorConfirmed = scenes[kept].authorConfirmed || other.authorConfirmed
        scenes[kept].updatedAt = .now
        scenes.remove(at: removed)
        entries[index].keyScenes = scenes
        saveNow()
        narrativeOverridesDidChange?(id)
    }

    /// 인물 카드 삭제 — 구조 변경은 즉시 저장 (스토어의 기존 규칙).
    public func removeCharacter(_ cardID: UUID, from id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              var cards = entries[index].characters,
              let removed = cards.first(where: { $0.id == cardID })
        else { return }
        cards.removeAll { $0.id == cardID }
        entries[index].characters = cards.isEmpty ? nil : cards
        // 자동 화자는 일반 이름 후보가 아니어서 별도 거부 표식이 필요하다.
        // 삭제 한 번이면 재등록하지 않아야 기억의 소유권이 사용자에게 남는다.
        if removed.role == .narrator {
            var rejected = entries[index].rejectedCharacterNames ?? []
            if !rejected.contains(CharacterCard.narratorRejectionMarker) {
                rejected.append(CharacterCard.narratorRejectionMarker)
                entries[index].rejectedCharacterNames = rejected
            }
        }
        saveNow()
    }

    /// 활성 본문 변경 카운터 — 상태 바의 디바운스 통계가 `.task(id:)` 키로
    /// 쓴다. @Published가 아니어도 된다: entries 변이가 이미 objectWillChange를
    /// 쏘고, 뷰는 다시 그려질 때 이 값을 읽는다.
    public private(set) var bodyVersion = 0

    /// 에디터 바인딩이 매 키 입력마다 호출 — 본문 갱신 + 디바운스 autosave.
    /// 제목이 사용자 지정이 아니면 첫 줄에서 자동 파생한다 — 사이드바가 "새 저널"
    /// 무더기가 되지 않도록 (자동 저널링의 기본 기대).
    public func updateActiveBody(_ text: String) {
        guard let index = entries.firstIndex(where: { $0.id == activeID }) else { return }
        // 무변경 가드 — 길이(UTF-8, O(1))가 다르면 전체 비교(O(n))를 건너뛴다.
        // 타이핑은 길이가 항상 변하므로 키 입력 경로에서 전체 비교가 사라진다.
        let current = entries[index].body
        if current.utf8.count == text.utf8.count, current == text { return }
        entries[index].body = text
        bodyVersion &+= 1
        if entries[index].allowsAutoTitle {
            let derived = Self.derivedTitle(from: text)
            let fallback = entries[index].resolvedKind == .novel ? "새 소설" : "새 저널"
            entries[index].title = derived.isEmpty ? fallback : derived
            // 파생 제목임을 명시 — 레거시(nil) 항목이 첫 파생 후 플레이스홀더
            // 판정에서 벗어나 한 글자 제목으로 얼어붙던 버그 방지.
            entries[index].titleIsCustom = false
        }
        scheduleSave()
        // 타이핑 = 인덱서 선점 신호 (M6) — 진행 중 백그라운드 이해를 멈추고
        // 유휴 타이머를 다시 감는다.
        documentDidChange?(activeID)
    }

    // MARK: - 저장

    private var currentSnapshot: Snapshot {
        Snapshot(
            entries: entries, activeID: activeID,
            folders: folders,
            // Set 순서는 매번 달라진다 — 정렬해 저장 파일 diff를 안정화.
            expandedFolderIDs: expandedFolderIDs.sorted { $0.uuidString < $1.uuidString }
        )
    }

    /// 저장 대기/진행 중 표시 — 상태 바의 "저장 중…/저장됨" 표시용 (L6).
    @Published public private(set) var isSaving = false

    private func scheduleSave() {
        saveTask?.cancel()
        isSaving = true
        let snapshot = currentSnapshot
        saveTask = Task { [weak self, autosaveDelay, fileURL] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: fileURL)
            self?.isSaving = false
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        Self.write(currentSnapshot, to: fileURL)
        isSaving = false
    }

    /// 대기 중인 디바운스 저장을 즉시 디스크에 쓴다 — 앱 종료·백그라운드 전환 직전에
    /// 호출해, 입력 직후 ⌘Q로 마지막 문장을 잃는 일을 막는다 (원자적 쓰기라 반복 호출도 안전).
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        Self.write(currentSnapshot, to: fileURL)
        isSaving = false
    }

    private static func write(_ snapshot: Snapshot, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - 날짜 포맷터

    private static let koCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    private static func koFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }

    private static let fullDateFormatter = koFormatter("M월 d일 EEEE")
    private static let weekdayFormatter = koFormatter("EEEEE")
    private static let shortDateFormatter = koFormatter("M.d")
}
