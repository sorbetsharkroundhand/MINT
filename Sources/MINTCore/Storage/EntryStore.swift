import Foundation
import SwiftUI

/// 저널 한 편 (에디터 v3 — 다중 저널).
public struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var body: String

    public init(
        id: UUID = UUID(),
        title: String = "새 저널",
        createdAt: Date = .now,
        body: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.body = body
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
    @Published public private(set) var activeID: UUID

    /// 본문 autosave까지 기다리는 시간. 입력이 멈춘 뒤에만 쓴다.
    private let autosaveDelay: Duration
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var entries: [JournalEntry]
        var activeID: UUID?
    }

    public init(autosaveDelay: Duration = .milliseconds(800)) {
        self.autosaveDelay = autosaveDelay
        let dir = Self.storageDirectory()
        self.fileURL = dir.appendingPathComponent("entries.json", isDirectory: false)

        let loaded = Self.loadSnapshot(from: fileURL) ?? Self.migratedOrEmptySnapshot(in: dir)
        var entries = loaded.entries
        if entries.isEmpty { entries = [JournalEntry()] }
        self.entries = entries
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
        saveNow()
    }

    @discardableResult
    public func newEntry() -> UUID {
        let entry = JournalEntry()
        entries.insert(entry, at: 0)
        activeID = entry.id
        saveNow()
        return entry.id
    }

    public func delete(_ id: UUID) {
        entries.removeAll(where: { $0.id == id })
        if entries.isEmpty { entries = [JournalEntry()] }
        if !entries.contains(where: { $0.id == activeID }) { activeID = entries[0].id }
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

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = Snapshot(entries: entries, activeID: activeID)
        saveTask = Task { [autosaveDelay, fileURL] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: fileURL)
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        Self.write(Snapshot(entries: entries, activeID: activeID), to: fileURL)
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
