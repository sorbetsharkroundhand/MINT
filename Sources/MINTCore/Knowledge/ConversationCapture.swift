import Foundation

// Conversation Capture (PLAN §6.6) — 작성 중 대화 블록의 실시간 감지와 자동 기록.
//
// 경로 분리 (요구사항 §19·§34):
// - **실시간**: `ConversationDetector` — 결정적·LLM 없음·O(스캔 창). 커서 근처만
//   훑으므로 30만 자 문서에서도 키 입력 경로 예산 안이다. 에디터가 디바운스 뒤
//   호출한다 (매 키 입력마다 돌지 않는다).
// - **백그라운드**: 참여자 귀속·주제·어조 보완은 BackgroundIndexer의 몫이다 —
//   기록 시점에는 원문 범위·첫 대사만 있으면 된다.
//
// 기록은 높은 신뢰의 결정적 규칙을 통과한 사용자 가시 메모리다. entries.json에
// 저장해 재실행 후에도 유지하되 원문 범위·해시로 재검증할 수 있고 사용자가 지울
// 수 있다. 스냅샷은 기존 Conversation 인덱스와 겹쳐 하나의 목록으로 낸다.

// MARK: - 기록된 대화 (사용자 데이터 — entries.json)

/// 결정적 감지기가 자동으로 수집한 대화 하나.
/// 대사 전체를 복제하지 않는다 — 원문 범위 + 재앵커용 첫/끝 대사만 (요구사항 §21).
public struct RecordedConversation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 기록 시점의 참여자 후보 (등록 카드 id) — 결정적 발화 귀속 결과.
    public var participants: [UUID]
    /// 기록 시점의 본문 위치 (UTF-16) — 원문이 수정되면 firstLine으로 재앵커.
    public var utf16Start: Int
    public var utf16End: Int
    /// 첫 대사 (따옴표 제외, ≤60자) — 재앵커 질의 + 목록 미리보기.
    public var firstLine: String
    /// 마지막 대사 — 범위 끝 재앵커.
    public var lastLine: String
    /// 기록 시점 대화 원문의 해시 — 백그라운드 보완(주제·어조)의 메모 키.
    public var contentHash: String
    public var recordedAt: Date

    public init(
        id: UUID = UUID(), participants: [UUID] = [],
        utf16Start: Int, utf16End: Int,
        firstLine: String, lastLine: String,
        contentHash: String, recordedAt: Date = .now
    ) {
        self.id = id
        self.participants = participants
        self.utf16Start = utf16Start
        self.utf16End = utf16End
        self.firstLine = firstLine
        self.lastLine = lastLine
        self.contentHash = contentHash
        self.recordedAt = recordedAt
    }
}

/// 기록된 대화의 백그라운드 보완 (파생 — 사이드카) — 주제·어조·핵심 발언.
/// 키 = RecordedConversation.id.uuidString, 메모 = contentHash (같으면 재분석 금지).
public struct ConversationMeta: Codable, Equatable, Sendable {
    public var contentHash: String
    /// ≤30자 — "과거 사건에 대한 대화".
    public var topic: String?
    /// ≤20자 — "긴장과 회피".
    public var tone: String?
    /// 핵심 발언 인용 (≤2개, 각 ≤40자).
    public var keyStatements: [String]
    public var updatedAt: Date

    public init(
        contentHash: String, topic: String? = nil, tone: String? = nil,
        keyStatements: [String] = [], updatedAt: Date = .now
    ) {
        self.contentHash = contentHash
        self.topic = topic
        self.tone = tone
        self.keyStatements = keyStatements
        self.updatedAt = updatedAt
    }
}

// MARK: - 실시간 감지기 (결정적 — LLM 금지 경로)

/// 커서 위치에서 끝나는 대화 블록의 빠른 감지 (요구사항 §18·§19).
///
/// 단순 정규식 한 방이 아니라 문단 단위 규칙으로 판단한다:
/// - 큰따옴표 발화가 있는 문단들의 연속 구간 (DialogueAttribution과 같은 관례).
/// - 발화 사이의 **짧은 행동 서술 1문단**까지는 같은 대화다.
/// - 빈 줄 2연속·헤딩·긴 서술은 대화를 끊는다.
/// - 스캔 창 상한(기본 4,000 UTF-16)을 두어 키 입력 경로 예산을 지킨다.
public enum ConversationDetector {

    /// 감지된 대화 블록 — 아직 기록 전의 제안 재료.
    public struct Block: Equatable, Sendable {
        /// 본문 전체 기준 UTF-16 범위 (첫 발화 문단 시작 … 마지막 발화 문단 끝).
        public var utf16Range: Range<Int>
        /// 발화 수 (따옴표 쌍 수).
        public var utteranceCount: Int
        /// 첫/마지막 대사 (따옴표 제외).
        public var firstLine: String
        public var lastLine: String
        /// 블록 원문 해시 — 같은 블록에 같은 제안을 두 번 띄우지 않는 키.
        public var contentHash: String
    }

    /// 제안을 띄우는 최소 발화 수 — 한 마디로는 "대화"가 아니다 (품질 > 적극성).
    public static let minUtterances = 2
    /// 커서에서 위로 스캔하는 최대 창 (UTF-16).
    public static let maxScanUTF16 = 4_000
    /// 발화 사이에 허용하는 서술 문단 길이 상한 — 이보다 길면 장면이 전환됐다.
    static let maxInterleavedNarration = 200

    /// 커서(문서 끝 근처) 위치에서 끝나는 대화 블록을 찾는다. 없으면 nil.
    ///
    /// `text`는 본문 전체(NSString 좌표) — 스캔은 커서 위 `maxScanUTF16`까지만.
    public static func blockEnding(
        at caret: Int, in text: NSString
    ) -> Block? {
        let caret = min(max(0, caret), text.length)
        let windowStart = max(0, caret - maxScanUTF16)

        // 문단(개행 구분) 단위로 뒤에서 앞으로 훑는다.
        struct ParagraphInfo {
            var range: NSRange
            var quotes: [String]
            var isBlank: Bool
            var isHeading: Bool
            var length: Int
        }
        var paragraphs: [ParagraphInfo] = []
        var location = caret
        while location > windowStart {
            let lineRange = text.lineRange(for: NSRange(location: location - 1, length: 0))
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let quotes = DialogueAttribution.quotedSpans(in: Substring(line)).map(\.text)
            paragraphs.append(
                ParagraphInfo(
                    range: lineRange,
                    quotes: quotes,
                    isBlank: trimmed.isEmpty,
                    isHeading: trimmed.hasPrefix("#"),
                    length: (trimmed as NSString).length))
            location = lineRange.location
            // 발화 없는 문단이 이미 여럿 쌓였고 발화도 못 찾았다면 조기 종료.
            if paragraphs.count > 60 { break }
        }
        // paragraphs는 아래→위 순서다. 커서 쪽 꼬리의 빈 문단은 건너뛴다
        // (마지막 대사 뒤에서 Enter를 눌러 빈 줄에 커서가 있는 상태가 보통이다).
        var index = 0
        var blankRun = 0
        while index < paragraphs.count, paragraphs[index].isBlank {
            blankRun += 1
            if blankRun >= 2 { return nil }  // 빈 줄 2연속 아래는 대화가 끝난 지 오래다
            index += 1
        }
        guard index < paragraphs.count else { return nil }

        // 대화 런 수집 — 발화 문단 + 사이의 짧은 서술 1문단 허용.
        var runParagraphs: [ParagraphInfo] = []
        var narrationGap = 0
        var pendingNarration: [ParagraphInfo] = []
        while index < paragraphs.count {
            let paragraph = paragraphs[index]
            if paragraph.isHeading { break }
            if paragraph.isBlank {
                // 빈 줄 하나는 문단 간격 — 둘 연속이면 런 종료.
                if index + 1 < paragraphs.count, paragraphs[index + 1].isBlank { break }
                index += 1
                continue
            }
            if paragraph.quotes.isEmpty {
                narrationGap += 1
                if narrationGap > 1 || paragraph.length > maxInterleavedNarration { break }
                pendingNarration.append(paragraph)
            } else {
                // 발화 문단 — 보류 중이던 서술을 런에 편입.
                runParagraphs.append(contentsOf: pendingNarration)
                pendingNarration = []
                narrationGap = 0
                runParagraphs.append(paragraph)
            }
            index += 1
        }
        // 런 머리의 서술(pendingNarration에 남은 것)은 대화 밖이다 — 버린다.

        let utterances = runParagraphs.flatMap(\.quotes)
        guard utterances.count >= minUtterances else { return nil }
        guard let last = runParagraphs.first?.range,  // 아래→위라 first가 마지막 문단
            let first = runParagraphs.last?.range
        else { return nil }
        let start = first.location
        var end = last.location + last.length
        // 문단 range는 개행 포함 — 끝 개행은 블록 밖으로.
        while end > start,
            text.character(at: end - 1) == 0x0A
        {
            end -= 1
        }
        guard end > start else { return nil }
        let content = text.substring(with: NSRange(location: start, length: end - start))
        // quotes는 문단별 원문 순서인데 runParagraphs가 아래→위라 뒤집는다.
        let ordered = runParagraphs.reversed().flatMap(\.quotes)
        return Block(
            utf16Range: start..<end,
            utteranceCount: utterances.count,
            firstLine: String((ordered.first ?? "").prefix(60)),
            lastLine: String((ordered.last ?? "").prefix(60)),
            contentHash: DocumentOutline.stableHash(content))
    }

    /// 기록의 재앵커 (PLAN §6.6) — 현재 범위와 해시가 여전히 맞으면 그대로
    /// 유지하고, 원문이 수정돼 밀렸을 때만 기존 위치에서 가장 가까운 첫/끝 대사로
    /// 범위를 되찾는다. 못 찾으면 nil — 엉뚱한 반복 대사에 잇는 것보다 낫다.
    public static func reanchor(
        _ record: RecordedConversation, in body: NSString
    ) -> RecordedConversation? {
        guard !record.firstLine.isEmpty else { return nil }
        if record.utf16Start >= 0, record.utf16End > record.utf16Start,
            record.utf16End <= body.length
        {
            let current = body.substring(
                with: NSRange(
                    location: record.utf16Start,
                    length: record.utf16End - record.utf16Start))
            if DocumentOutline.stableHash(current) == record.contentHash { return record }
        }

        var candidates: [NSRange] = []
        var searchStart = 0
        while searchStart < body.length {
            let found = body.range(
                of: record.firstLine, options: [],
                range: NSRange(location: searchStart, length: body.length - searchStart))
            guard found.location != NSNotFound else { break }
            candidates.append(found)
            searchStart = found.location + max(1, found.length)
        }
        guard let first = candidates.min(by: {
            abs($0.location - record.utf16Start) < abs($1.location - record.utf16Start)
        }) else { return nil }
        var updated = record
        // 문단 시작으로 확장 — 기록 범위는 발화 문단 단위였다.
        let firstParagraph = body.lineRange(for: first)
        updated.utf16Start = firstParagraph.location
        let tailStart = first.location + first.length
        guard !record.lastLine.isEmpty, tailStart < body.length else { return nil }
        var lastCandidates: [NSRange] = []
        searchStart = tailStart
        while searchStart < body.length {
            let found = body.range(
                of: record.lastLine, options: [],
                range: NSRange(location: searchStart, length: body.length - searchStart))
            guard found.location != NSNotFound else { break }
            lastCandidates.append(found)
            searchStart = found.location + max(1, found.length)
        }
        let expectedEnd = updated.utf16Start + (record.utf16End - record.utf16Start)
        guard let last = lastCandidates.min(by: {
            abs(($0.location + $0.length) - expectedEnd)
                < abs(($1.location + $1.length) - expectedEnd)
        }) else { return nil }
        let lastParagraph = body.lineRange(for: last)
        var end = lastParagraph.location + lastParagraph.length
        while end > updated.utf16Start, body.character(at: end - 1) == 0x0A { end -= 1 }
        updated.utf16End = end
        return updated
    }

    /// 블록 → 기록 레코드. 참여자는 현재 스냅샷의 발화 귀속에서 겹치는 화자들로
    /// 채운다. 아직 스냅샷이 따라오지 못했으면 다음 확장 감지에서 병합 보완된다.
    public static func record(
        from block: Block, utterances: [Utterance]
    ) -> RecordedConversation {
        let speakers = utterances
            .filter { block.utf16Range.contains($0.utf16Start) }
            .flatMap { [$0.speakerID] + ($0.listenerID.map { [$0] } ?? []) }
        return RecordedConversation(
            participants: Array(Set(speakers)),
            utf16Start: block.utf16Range.lowerBound,
            utf16End: block.utf16Range.upperBound,
            firstLine: block.firstLine,
            lastLine: block.lastLine,
            contentHash: block.contentHash)
    }

    /// 새 감지 결과를 기존 자동 기록에 합친다. 같은 해시는 무시하고, 이어 쓰기로
    /// 범위가 겹치면 ID·최초 기록 시각을 보존한 채 한 대화로 확장한다.
    static func merging(
        _ record: RecordedConversation, into existing: [RecordedConversation]
    ) -> [RecordedConversation] {
        guard !existing.contains(where: { $0.contentHash == record.contentHash }) else {
            return existing
        }
        var records = existing
        if let overlap = records.firstIndex(where: {
            $0.utf16Start < record.utf16End && record.utf16Start < $0.utf16End
        }) {
            var expanded = record
            expanded.id = records[overlap].id
            expanded.recordedAt = records[overlap].recordedAt
            expanded.participants = Array(Set(records[overlap].participants + record.participants))
            records[overlap] = expanded
        } else {
            records.append(record)
        }
        return records
    }
}
