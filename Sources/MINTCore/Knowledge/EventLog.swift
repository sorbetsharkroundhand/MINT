import Foundation

/// 사건 로그 (PLAN §6.3) — append-only. 설계 근거는 docs/m6-events.md.
///
/// **앵커는 Pos가 아니라 씬 콘텐츠 해시다.** PLAN §6.3 스키마의 `pos`를 그대로
/// 저장하지 않는 이유: 씬 배열 인덱스(Pos v1)는 씬이 하나 삽입되면 뒤가 전부
/// 밀려, append-only 로그가 삽입마다 전체 재기록을 요구하게 된다. 해시는 원문에
/// 매여 있어 삽입에 불변이고, Pos는 질의 시점에 아웃라인 순서에서 파생한다.
/// 덤으로 PLAN §8 "편집 무효화 규칙"의 톰스톤이 기존 GC(`save(pruningTo:)`)에
/// 그대로 얹힌다 — 블록이 바뀌면 해시가 고아가 되고 자동으로 청소된다.
public struct StoryEvent: Codable, Equatable, Sendable {
    /// 이 사건이 일어난 씬의 `DocumentOutline.Scene.contentHash`.
    public var sceneHash: String
    /// 참여 인물 — **등록된 `CharacterCard.id`만** 담는다. 미등록 이름은 링크하지
    /// 않는다 (자동 등록 금지, CLAUDE.md §3). 등록 시점에 이름 매칭으로 소급 연결.
    public var participants: [UUID]
    /// ≤80자 (PLAN §6.3).
    public var summary: String
    /// 1–5 — B 블록 예산이 모자랄 때 버리는 순서를 정한다 (PLAN §11).
    public var importance: Int
    /// 상태 효과 (PLAN §6.3 `상태 효과 [StateDelta 참조]`) — **5b에서 채운다**.
    /// 지금 필드만 두는 이유: 5b에 다시 스키마 버전을 올리면 그때 또 전 요약을
    /// 폐기·재생성해야 한다 (결정 5의 비용을 두 번 내지 않는다).
    public var deltas: [StateDelta]
    public var updatedAt: Date

    public init(
        sceneHash: String, participants: [UUID], summary: String,
        importance: Int, deltas: [StateDelta] = [], updatedAt: Date = .now
    ) {
        self.sceneHash = sceneHash
        self.participants = participants
        self.summary = summary
        self.importance = importance
        self.deltas = deltas
        self.updatedAt = updatedAt
    }
}

/// 인물 상태 변화 한 조각 (PLAN §6.2) — 상태는 덮어쓰지 않고 append하며,
/// `state_at(pos)`가 pos 이하 델타를 접어 그 시점 상태를 만든다.
/// **5b 단계에서 추출을 붙인다** — 지금은 스키마 자리만 잡는다.
public struct StateDelta: Codable, Equatable, Sendable {
    /// 닫힌 필드 집합 — 소형 모델의 자유 서술을 막는 장치 (docs/m6-events.md 5b).
    public enum Field: String, Codable, Equatable, Sendable, CaseIterable {
        case location = "위치"
        case emotion = "감정"
        case relation = "관계"
        case goal = "목표"
        case vitality = "생사"
    }

    public var characterID: UUID
    public var field: Field
    /// ≤40자.
    public var value: String
    /// 근거 앵커 — 이 델타를 만든 씬의 콘텐츠 해시.
    public var sceneHash: String

    public init(characterID: UUID, field: Field, value: String, sceneHash: String) {
        self.characterID = characterID
        self.field = field
        self.value = value
        self.sceneHash = sceneHash
    }
}

// MARK: - 추출 결과 파싱 (결정적 — CLAUDE.md §2-5)

/// LLM 사건 추출 출력의 파서·검증기.
///
/// 소형 모델의 JSON은 깨진다(중괄호 누락·트레일링 콤마) — 요약 경로가 평문 +
/// 결정적 clamp를 쓰는 것과 같은 규율로 줄 형식을 쓴다 (docs/m6-events.md 결정 4).
/// **파싱은 관대하게, 검증은 엄격하게**: 환각 인물은 등록 카드 매칭에서 탈락한다.
public enum EventParser {

    /// 사건 요약 상한 (PLAN §6.3).
    static let maxSummaryCharacters = 80
    /// 씬 하나에서 받아들이는 사건 수 상한 — 모델이 문장마다 사건을 만들면
    /// B 블록 예산이 한 씬에 잠식된다 (품질 > 적극성, CLAUDE.md §1-2).
    static let maxEventsPerScene = 3

    /// 인물 이름·별칭 → 카드 id. 조립기와 같은 별칭 규격(쉼표 구분)을 쓴다.
    public static func nameIndex(_ cards: [CharacterCard]) -> [String: UUID] {
        var index: [String: UUID] = [:]
        for card in cards {
            let name = card.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            index[name] = card.id
            for alias in card.aliases.split(separator: ",") {
                let key = alias.trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { index[key] = card.id }
            }
        }
        return index
    }

    /// 모델 출력 → 검증된 사건 배열.
    ///
    /// 기대 형식 (한 줄에 사건 하나):
    /// ```
    /// 서연이 병원에서 퇴원했다 | 참여: 서연, 민준 | 중요도: 3
    /// ```
    /// 형식을 벗어난 줄은 조용히 버린다 — 한 줄도 못 건지면 빈 배열이고,
    /// 호출부는 "사건 없음"으로 기록한다 (다음 패스가 재시도하지 않도록).
    public static func parse(
        _ output: String, sceneHash: String, nameIndex: [String: UUID]
    ) -> [StoryEvent] {
        var events: [StoryEvent] = []
        for rawLine in output.split(separator: "\n") {
            guard events.count < maxEventsPerScene else { break }
            let line = stripListMarker(rawLine.trimmingCharacters(in: .whitespaces))
            // **구분자 없는 줄은 버린다.** 모델의 머리말("다음은 사건입니다:")이
            // 사건으로 저장되면 B 블록에 지식인 척 주입된다 — 형식을 지킨 줄에는
            // 항상 `|`가 있으므로, 이 한 줄이 머리말을 구조적으로 막는다.
            // 형식을 벗어난 진짜 사건을 놓치는 비용은 받는다 (CLAUDE.md §1-2
            // 품질 > 적극성 — 확신이 없으면 침묵이 정답).
            guard line.contains("|") else { continue }
            let fields = line.split(separator: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let head = fields.first, !head.isEmpty else { continue }

            let summary = String(head.prefix(maxSummaryCharacters))
            // 요약이라기엔 너무 짧은 토막은 사건이 아니다.
            guard summary.count >= 4 else { continue }

            var participants: [UUID] = []
            var importance = 3  // 표기가 없거나 깨졌으면 중간값
            for field in fields.dropFirst() {
                if let value = value(of: field, keys: ["참여", "인물"]) {
                    participants = resolve(value, nameIndex: nameIndex)
                } else if let value = value(of: field, keys: ["중요도", "중요"]) {
                    importance = min(5, max(1, Int(value.filter(\.isNumber)) ?? 3))
                }
            }
            events.append(
                StoryEvent(
                    sceneHash: sceneHash, participants: participants,
                    summary: summary, importance: importance))
        }
        return events
    }

    /// 모델이 붙이는 목록 기호만 벗긴다 — `- `·`* `·`• `·`1. `·`2) `.
    ///
    /// ⚠️ 선두 문자를 뭉뚱그려 버리면(`drop(while: "-*•0123456789. ")`) 숫자로
    /// 시작하는 **본문을 먹는다** — 실제 원고에서 "33번지 18가구…"가 "번지
    /// 18가구…"로 저장된 것을 확인했다 (이상 「날개」). 숫자 불릿은 뒤에
    /// `. `·`) `가 따라올 때만 불릿이다.
    static func stripListMarker(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "-*•".contains(first) {
            return String(line.dropFirst().drop(while: { $0 == " " }))
        }
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return line }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return line }
        let after = rest.dropFirst()
        // "1." 뒤에 공백이 있어야 불릿 — "3.5초 만에"·"1930년"은 본문이다.
        guard after.first == " " else { return line }
        return String(after.drop(while: { $0 == " " }))
    }

    /// `키: 값` 조각에서 값만 — 키가 목록에 없으면 nil.
    private static func value(of field: String, keys: [String]) -> String? {
        guard let separator = field.firstIndex(of: ":") else { return nil }
        let key = field[..<separator].trimmingCharacters(in: .whitespaces)
        guard keys.contains(key) else { return nil }
        return field[field.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
    }

    /// 이름 목록 → 카드 id. **등록 카드에 없는 이름은 버린다** — 모델이 지어낸
    /// 인물이 사건에 들어오는 것을 막는 유일한 관문 (docs/m6-events.md 결정 2).
    private static func resolve(_ names: String, nameIndex: [String: UUID]) -> [UUID] {
        var ids: [UUID] = []
        for raw in names.split(separator: ",") {
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            // 모델이 조사를 붙여 오는 경우("서연이")까지 받아준다 — 등록 이름이
            // 접두인 가장 긴 매칭. 감지기(CharacterLexicon)와 같은 교착어 대응.
            if let id = nameIndex[name] {
                ids.append(id)
            } else if let match = nameIndex.first(where: { name.hasPrefix($0.key) }) {
                ids.append(match.value)
            }
        }
        return Array(Set(ids))  // 같은 인물 중복 표기 제거
    }
}
