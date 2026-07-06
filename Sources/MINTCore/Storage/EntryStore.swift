import Foundation
import SwiftUI

/// 저널 한 편 (에디터 v3 — 다중 저널).
public struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var body: String
    /// 소속 폴더. nil이면 루트 (파일시스템 v1 — 이전 파일엔 키가 없어 nil로 로드).
    public var folderID: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "새 저널",
        createdAt: Date = .now,
        body: String = "",
        folderID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.body = body
        self.folderID = folderID
    }
}

/// 저널을 프로젝트처럼 묶는 폴더 (파일시스템 v1). parentID로 중첩된다.
public struct JournalFolder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "새 폴더",
        parentID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}

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

    /// 본문 autosave까지 기다리는 시간. 입력이 멈춘 뒤에만 쓴다.
    private let autosaveDelay: Duration
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var entries: [JournalEntry]
        var activeID: UUID?
        // 파일시스템 v1 이전 파일엔 없는 키 — 옵셔널로 하위 호환.
        var folders: [JournalFolder]? = nil
        var expandedFolderIDs: [UUID]? = nil
    }

    public init(autosaveDelay: Duration = .milliseconds(800)) {
        self.autosaveDelay = autosaveDelay
        let dir = Self.storageDirectory()
        self.fileURL = dir.appendingPathComponent("entries.json", isDirectory: false)

        let loaded = Self.loadSnapshot(from: fileURL) ?? Self.migratedOrEmptySnapshot(in: dir)
        var entries = loaded.entries
        if entries.isEmpty { entries = [JournalEntry()] }
        self.entries = entries
        let folders = loaded.folders ?? []
        self.folders = folders
        self.expandedFolderIDs = Set(loaded.expandedFolderIDs ?? [])
            .intersection(folders.map(\.id))
        self.activeID = loaded.activeID.flatMap { id in
            entries.contains(where: { $0.id == id }) ? id : nil
        } ?? entries[0].id
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
            title: Self.derivedTitle(from: body), createdAt: modified, body: body)
        return Snapshot(entries: [entry], activeID: entry.id)
    }

    /// 첫 비어 있지 않은 줄에서 마크다운 마커를 벗겨 제목으로 쓴다.
    private static func derivedTitle(from body: String) -> String {
        for line in body.split(separator: "\n") {
            let stripped = line
                .replacingOccurrences(
                    of: #"^(#{1,3}\s+|>\s?|- \[[ x]\]\s?|[-*]\s+|\d+\.\s+)"#,
                    with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return String(stripped.prefix(30)) }
        }
        return "저널"
    }

    // MARK: - 조회

    public var activeEntry: JournalEntry? {
        entries.first(where: { $0.id == activeID })
    }

    /// 한 폴더의 하위 폴더들 (nil = 루트).
    public func childFolders(of parentID: UUID?) -> [JournalFolder] {
        folders.filter { $0.parentID == parentID }
    }

    /// 한 폴더에 담긴 저널들 (nil = 루트).
    public func childEntries(of folderID: UUID?) -> [JournalEntry] {
        entries.filter { $0.folderID == folderID }
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
    }

    @discardableResult
    public func newEntry(in folderID: UUID? = nil) -> UUID {
        let entry = JournalEntry(folderID: folderID)
        entries.insert(entry, at: 0)
        activeID = entry.id
        // 새 저널이 접힌 폴더 안에 숨지 않게 부모를 펼친다.
        if let folderID { expandedFolderIDs.insert(folderID) }
        saveNow()
        return entry.id
    }

    public func delete(_ id: UUID) {
        entries.removeAll(where: { $0.id == id })
        if entries.isEmpty { entries = [JournalEntry()] }
        if !entries.contains(where: { $0.id == activeID }) { activeID = entries[0].id }
        saveNow()
    }

    // MARK: - 폴더 변경

    @discardableResult
    public func newFolder(in parentID: UUID? = nil) -> UUID {
        let folder = JournalFolder(parentID: parentID)
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
        saveNow()
    }

    /// 에디터 바인딩이 매 키 입력마다 호출 — 본문 갱신 + 디바운스 autosave.
    public func updateActiveBody(_ text: String) {
        guard let index = entries.firstIndex(where: { $0.id == activeID }),
            entries[index].body != text
        else { return }
        entries[index].body = text
        scheduleSave()
    }

    // MARK: - 저장

    private var currentSnapshot: Snapshot {
        Snapshot(
            entries: entries, activeID: activeID,
            folders: folders,
            // Set 순서는 매번 달라진다 — 정렬해 저장 파일 diff를 안정화.
            expandedFolderIDs: expandedFolderIDs.sorted { $0.uuidString < $1.uuidString })
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = currentSnapshot
        saveTask = Task { [autosaveDelay, fileURL] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: fileURL)
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        Self.write(currentSnapshot, to: fileURL)
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
