import Foundation

/// 발화의 존대 수준 (PLAN §6.4) — 한국어 대화 예측의 핵심 축.
public enum Politeness: String, Equatable, Sendable {
    case honorific = "존댓말"
    case plain = "반말"
}

/// 귀속된 발화 하나 (PLAN §7 대화 귀속).
///
/// 사이드카에 저장하지 않는다 — 추출이 결정적(LLM 없음)이라 패스마다 원문에서
/// 재계산하는 비용이 저장·무효화 관리 비용보다 싸다 (CLAUDE.md §2-5).
/// 스냅샷에만 실려 예측 조립이 질의한다.
public struct Utterance: Equatable, Sendable {
    /// 화자 — 등록된 `CharacterCard.id`만 (자동 등록 금지, CLAUDE.md §3).
    public var speakerID: UUID
    /// 대사 원문 (따옴표 제외) — 말투 예문·존대 판정의 재료.
    public var text: String
    /// 발화 시작 위치 (UTF-16) — 시점 차단 질의의 축 (CLAUDE.md §2-4).
    public var utf16Start: Int
    /// 같은 런의 상대 화자 — **2인 대화 런에서만** 채워진다. 존대 매트릭스의
    /// 방향(A→B)이 여기서 나온다. 3인 이상은 v1에서 방향을 추정하지 않는다.
    public var listenerID: UUID?
    /// 존대 판정 — 종결어미가 닫힌 규칙에 없으면 nil (품질 > 적극성).
    public var politeness: Politeness?
}

/// 원문의 큰따옴표 안 내용을 하나도 버리지 않는 전체 대사 레코드.
/// 등록 인물로 확정되지 않아도 `speakerLabel=미상`으로 남겨, 수집 누락과
/// 귀속 실패를 구분한다. 말투·일관성 계산은 기존 `Utterance`만 사용한다.
public struct DialogueLine: Identifiable, Equatable, Sendable {
    public enum Attribution: String, Equatable, Sendable {
        case deterministic = "규칙 귀속"
        case contextualRole = "문맥 역할"
        case unresolved = "미상"
        case user = "사용자 지정"
    }

    public var id: String { stableKey }
    public var stableKey: String
    public var speakerID: UUID?
    public var speakerLabel: String
    public var text: String
    public var utf16Start: Int
    public var listenerID: UUID?
    public var politeness: Politeness?
    public var attribution: Attribution

    public init(
        stableKey: String, speakerID: UUID?, speakerLabel: String,
        text: String, utf16Start: Int, listenerID: UUID? = nil,
        politeness: Politeness? = nil, attribution: Attribution
    ) {
        self.stableKey = stableKey
        self.speakerID = speakerID
        self.speakerLabel = speakerLabel
        self.text = text
        self.utf16Start = utf16Start
        self.listenerID = listenerID
        self.politeness = politeness
        self.attribution = attribution
    }
}

/// 대화 귀속 (PLAN §7·§6.4, m6-prep 6단계) — **결정적 우선** (CLAUDE.md §2-5).
///
/// 규칙 두 단: ① 인접 서술 — 발화가 있는 문단의 서술부에 등록 인물 이름이
/// (발화 동사와 함께, 또는 유일하게) 나오면 그 인물. ② 교대 규칙 — 화자 둘이
/// 확정된 대화 런에서 미귀속 발화는 교대로 채운다.
/// 둘 다 실패하면 **귀속하지 않는다** — 모호할 때의 LLM 판정(PLAN §7)은
/// v2 (docs/m6-dialogue.md 보류 근거).
public enum DialogueAttribution {
    /// 말투 예문으로 쓰는 대사 상한 — 카드·대화 블록 예산 보호 (PLAN §11).
    public static let maxExampleCharacters = 40

    /// 인접 서술에서 화자를 지목하는 발화 동사 어간 — 활용형을 접두로 매칭한다
    /// ("말했다"·"말하며"·"말했지만" 전부 "말하"/"말했"에 걸린다).
    static let speechVerbStems = [
        "말했", "말하", "물었", "묻는", "대답했", "대답하", "답했", "답하",
        "외쳤", "외치", "소리쳤", "소리치", "중얼거렸", "중얼거리",
        "속삭였", "속삭이", "덧붙였", "덧붙이", "되물었", "되묻",
        "받았", "받는", "물으", "물을", "입을 열었", "말을 이었", "말을 꺼냈"
    ]

    /// 본문 전체 → 큰따옴표 안의 모든 대사. 귀속 실패도 `미상`으로 보존한다.
    public static func dialogues(
        in body: String, cards: [CharacterCard]
    ) -> [DialogueLine] {
        let attributed = attributedUtterances(in: body, cards: cards)
        let byPosition = Dictionary(
            attributed.map { ($0.utf16Start, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let names = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) })
        let spans = allQuotedSpans(in: body)
        let discourseSpeakers = discourseSpeakerIDs(
            spans: spans, body: body, cards: cards
        )
        let usesTwoPartyDiscourse = cards.contains { $0.role == .narrator }
            && cards.count(where: { $0.role != .narrator }) == 1
        var ordinalByTextHash: [String: Int] = [:]
        return spans.enumerated().map { index, span in
            let textHash = DocumentOutline.stableHash(span.text)
            let ordinal = ordinalByTextHash[textHash, default: 0]
            ordinalByTextHash[textHash] = ordinal + 1
            let stableKey = "dialogue|\(textHash)|\(ordinal)"
            if let label = contextualRoleLabel(
                for: span, in: body
            ) {
                return DialogueLine(
                    stableKey: stableKey, speakerID: nil, speakerLabel: label,
                    text: span.text, utf16Start: span.utf16Start,
                    politeness: politeness(of: span.text),
                    attribution: .contextualRole
                )
            }
            if let speakerID = discourseSpeakers[index] {
                let listenerID = discourseListenerID(
                    for: index, speakers: discourseSpeakers
                )
                return DialogueLine(
                    stableKey: stableKey, speakerID: speakerID,
                    speakerLabel: names[speakerID] ?? "미상",
                    text: span.text, utf16Start: span.utf16Start,
                    listenerID: listenerID,
                    politeness: politeness(of: span.text),
                    attribution: .deterministic
                )
            }
            if !usesTwoPartyDiscourse, let utterance = byPosition[span.utf16Start] {
                return DialogueLine(
                    stableKey: stableKey, speakerID: utterance.speakerID,
                    speakerLabel: names[utterance.speakerID] ?? "미상",
                    text: span.text, utf16Start: span.utf16Start,
                    listenerID: utterance.listenerID,
                    politeness: utterance.politeness,
                    attribution: .deterministic
                )
            }
            return DialogueLine(
                stableKey: stableKey, speakerID: nil, speakerLabel: "미상",
                text: span.text, utf16Start: span.utf16Start,
                politeness: politeness(of: span.text), attribution: .unresolved
            )
        }
    }

    /// 이름 미상 1인칭 화자와 한 명의 상대가 중심인 대화에서는 문단 사이의
    /// `하고 … 대답했다`·응답·연속 발화 표지를 함께 읽는다. 문단별 귀속만으로는
    /// 「동백꽃」처럼 서술이 앞뒤 문단에 갈라진 작품에서 화자와 청자를 거꾸로
    /// 잡는다. 둘보다 많은 등록 인물이 있으면 이 보강을 쓰지 않아 오추정을 막는다.
    private static func discourseSpeakerIDs(
        spans: [AbsoluteQuotedSpan], body: String, cards: [CharacterCard]
    ) -> [UUID?] {
        guard let narrator = cards.first(where: { $0.role == .narrator }),
              cards.filter({ $0.role != .narrator }).count == 1,
              let counterpart = cards.first(where: { $0.role != .narrator })
        else { return Array(repeating: nil, count: spans.count) }

        let source = body as NSString
        let nameIndex = EventParser.nameIndex(cards)
        let names = nameIndex.keys.sorted { $0.count > $1.count }
        let pair = Set([narrator.id, counterpart.id])
        var result = Array<UUID?>(repeating: nil, count: spans.count)

        func gap(_ lower: Int, _ upper: Int) -> String {
            let start = min(max(0, lower), source.length)
            let end = min(max(start, upper), source.length)
            return source.substring(
                with: NSRange(location: start, length: end - start)
            )
        }
        func before(_ index: Int) -> String {
            let lower = index == 0 ? max(0, spans[index].utf16Start - 900)
                : spans[index - 1].utf16End
            return gap(lower, spans[index].utf16Start)
        }
        func after(_ index: Int) -> String {
            let upper = index + 1 < spans.count
                ? spans[index + 1].utf16Start : min(source.length, spans[index].utf16End + 900)
            return gap(spans[index].utf16End, upper)
        }
        func subject(in text: String) -> UUID? {
            attributeFromNarration(
                text, names: names, nameIndex: nameIndex,
                narratorID: narrator.id
            )
        }
        func beginsAsPostQuote(_ text: String) -> Bool {
            let normalized = text.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "\"”」』")
                )
            )
            return normalized.hasPrefix("하고") || normalized.hasPrefix("이렇게")
        }
        func hasSpeechClosure(_ text: String) -> Bool {
            speechVerbRange(in: text) != nil || text.contains("소리를")
                || text.contains("호령") || text.contains("수작을")
                || text.contains("대꾸")
        }
        func hasGenericCounterpartSubject(_ text: String) -> Bool {
            ["계집애가", "계집애는", "계집애하고", "계집애년이"]
                .contains { text.contains($0) }
        }
        func stronglyAttributesQuote(_ text: String) -> Bool {
            let firstSentence = text.split(separator: ".", maxSplits: 1,
                omittingEmptySubsequences: false).first.map(String.init) ?? text
            if beginsAsPostQuote(text), subject(in: firstSentence) != nil { return true }
            let speechMarkers = ["소리를", "호령"]
            for marker in speechMarkers {
                if let markerRange = text.range(of: marker),
                   let speaker = subject(in: String(text[..<markerRange.upperBound])),
                   pair.contains(speaker) {
                    return true
                }
            }
            return false
        }
        func isContinuation(_ text: String) -> Bool {
            ["또는,", "그리고 또 하는 소리가", "그만도 좋으련만"]
                .contains { text.contains($0) }
        }
        func isReply(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["그래", "그럼", "뭐 ", "뭐,", "아니", "응", "왜 ", "난 "]
                .contains { trimmed.hasPrefix($0) }
        }
        func isTurnBoundary(_ text: String) -> Bool {
            ["하니까", "했더니", "대답하", "대답했", "호령을 하", "일어나다가"]
                .contains { text.contains($0) }
        }
        func isInsult(_ text: String) -> Bool {
            ["바보", "병신", "고자", "이년", "녀석", "계집애년"]
                .contains { text.contains($0) }
        }
        func opposite(_ speaker: UUID) -> UUID? {
            pair.first(where: { $0 != speaker })
        }

        // 먼저 원문에 주어가 실제로 있는 강한 표지만 고정한다. 앞 서술이 명시적
        // 리드인이면 뒤의 청자 반응보다 우선한다 (`점순이가 다가와서, “…”`).
        for index in spans.indices {
            let lead = before(index)
            let trail = after(index)
            let trimmedLead = lead.trimmingCharacters(in: .whitespacesAndNewlines)
            let trailAttributesQuote = beginsAsPostQuote(trail) || hasSpeechClosure(trail)

            if isContinuation(lead), index > 0, let previous = result[index - 1] {
                result[index] = previous
                continue
            }
            if hasGenericCounterpartSubject(lead),
               (trimmedLead.hasSuffix(",") || lead.contains("턱밑으로 불쑥 내미는")) {
                result[index] = counterpart.id
                continue
            }
            if stronglyAttributesQuote(trail) {
                let firstSentence = trail.split(
                    separator: ".", maxSplits: 1, omittingEmptySubsequences: false
                ).first.map(String.init) ?? trail
                if let trailSubject = subject(in: firstSentence) {
                    result[index] = trailSubject
                    continue
                }
            }
            if spans[index].text.contains("너"),
               (lead.contains("나는") || lead.contains("내가") || lead.contains("나의")),
               !trimmedLead.hasSuffix(",") {
                // 1인칭 서술 뒤 `너 …`는 화자 자신이 아니라 그에게 말하는 상대다.
                result[index] = counterpart.id
                continue
            }
            if let leadSubject = subject(in: lead) {
                let namedCounterpart = leadSubject == counterpart.id
                let narratorLead = leadSubject == narrator.id
                    && (trimmedLead.hasSuffix(",") || lead.contains("연방,"))
                    && !isTurnBoundary(lead)
                if namedCounterpart || narratorLead || trailAttributesQuote {
                    result[index] = leadSubject
                    continue
                }
            }
            if trailAttributesQuote, let trailSubject = subject(in: trail) {
                result[index] = trailSubject
            }
        }

        // 남은 칸은 앞뒤 발화 관계가 명시적인 경우에만 채운다. `또는`은 같은
        // 화자의 연속 발화, 응답·대답·중단은 상대 차례다. 욕설을 줄마다 나눈
        // 경우는 질문/응답이 아니라 한 화자의 연속 발화로 본다.
        for index in spans.indices where result[index] == nil {
            guard index > 0, let previous = result[index - 1] else { continue }
            let bridge = before(index)
            if isReply(spans[index].text) {
                result[index] = opposite(previous)
            } else if bridge.count < 80, isInsult(spans[index - 1].text),
               isInsult(spans[index].text) {
                result[index] = previous
            } else if isContinuation(bridge) {
                result[index] = previous
            } else if bridge.trimmingCharacters(in: .whitespacesAndNewlines)
                .filter({ !"\"”」』“.".contains($0) }).isEmpty {
                result[index] = isInsult(spans[index - 1].text)
                    && isInsult(spans[index].text) ? previous : opposite(previous)
            } else if isTurnBoundary(bridge) {
                result[index] = opposite(previous)
            } else if bridge.count < 650 {
                // 두 사람만 있는 짧은 대화 구간의 새 따옴표는 기본적으로 상대
                // 차례다. 위의 연속 발화 표지가 있을 때만 같은 화자로 유지한다.
                result[index] = opposite(previous)
            }
        }
        // 첫 순회에서 선행 화자가 아직 비어 전이를 못 한 칸을 한 번 더 접는다.
        for index in spans.indices where result[index] == nil {
            guard index > 0, let previous = result[index - 1] else { continue }
            let bridge = before(index)
            if isContinuation(bridge) {
                result[index] = previous
            } else if isTurnBoundary(bridge) || isReply(spans[index].text) {
                result[index] = opposite(previous)
            } else if bridge.count < 650 {
                result[index] = opposite(previous)
            }
        }
        return result
    }

    private static func discourseListenerID(
        for index: Int, speakers: [UUID?]
    ) -> UUID? {
        let current = speakers[index]
        if index > 0, let previous = speakers[index - 1], previous != current {
            return previous
        }
        if index + 1 < speakers.count,
           let following = speakers[index + 1], following != current {
            return following
        }
        return nil
    }

    /// 기존 말투·대화·일관성 로직에는 등록 인물로 귀속된 발화만 전달한다.
    public static func utterances(
        in body: String, cards: [CharacterCard]
    ) -> [Utterance] {
        attributedUtterances(in: body, cards: cards)
    }

    public static func utterances(from dialogues: [DialogueLine]) -> [Utterance] {
        dialogues.compactMap { dialogue in
            guard let speakerID = dialogue.speakerID else { return nil }
            return Utterance(
                speakerID: speakerID, text: dialogue.text,
                utf16Start: dialogue.utf16Start,
                listenerID: dialogue.listenerID,
                politeness: dialogue.politeness
            )
        }
    }

    /// 본문 전체 → 담화 순서의 귀속된 발화들. 등록 카드가 없으면 빈 배열.
    ///
    /// O(n) 한 번 훑기 + 문단 단위 처리 — 30만 자에서도 밀리초 단위라
    /// 패스마다 재계산한다 (`CharacterDetector.detect`와 같은 예산).
    private static func attributedUtterances(
        in body: String, cards: [CharacterCard]
    ) -> [Utterance] {
        let nameIndex = EventParser.nameIndex(cards)
        guard !nameIndex.isEmpty else { return [] }
        let narratorID = cards.first(where: { $0.role == .narrator })?.id
        // 긴 이름 우선 매칭 — "서연희"가 등록돼 있으면 "서연"보다 먼저 잡는다.
        let names = nameIndex.keys.sorted { $0.count > $1.count }

        // ① 문단별 발화·서술 분해 + 인접 서술 귀속.
        var paragraphs: [Paragraph] = []
        var utf16Pos = 0
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { utf16Pos += line.utf16.count + 1 } // +1 = 개행
            let quotes = quotedSpans(in: line)
            guard !quotes.isEmpty else {
                paragraphs.append(
                    Paragraph(
                        quotes: [], speaker: nil, narration: String(line),
                        isBlank: line.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                )
                continue
            }
            let narration = narrationText(of: line)
            let speaker = attributeFromNarration(
                narration, names: names, nameIndex: nameIndex,
                narratorID: narratorID
            )
            paragraphs.append(
                Paragraph(
                    quotes: quotes.map { span in
                        (text: span.text, start: utf16Pos + span.utf16Offset)
                    },
                    speaker: speaker, narration: narration, isBlank: false
                )
            )
        }

        // 고전·출판 원고는 `"대사"`와 `하고 점순이가 말했다`를 서로 다른
        // 문단에 놓는 경우가 흔하다. 같은 줄만 보는 기존 규칙은 「동백꽃」의
        // 점순 대사를 하나도 귀속하지 못했다. 바로 이웃의 비대사 문단까지만
        // 결합해 먼 문단의 이름을 끌어오는 오귀속은 막는다.
        attributeFromNeighborNarration(
            &paragraphs, names: names, nameIndex: nameIndex,
            narratorID: narratorID
        )

        // ② 대화 런으로 묶어 교대 규칙 적용 + 청자 방향 부여.
        var result: [Utterance] = []
        for run in dialogueRuns(paragraphs) {
            let attributed = fillByAlternation(run)
            let speakers = Set(attributed.compactMap(\.speaker))
            for paragraph in attributed {
                guard let speaker = paragraph.speaker else { continue }
                // 2인 런에서만 상대를 청자로 확정 — 3인 이상의 방향 추정은
                // 틀린 매트릭스를 만든다 (품질 > 적극성).
                let listener =
                    speakers.count == 2 ? speakers.first(where: { $0 != speaker }) : nil
                for quote in paragraph.quotes {
                    result.append(
                        Utterance(
                            speakerID: speaker,
                            text: quote.text,
                            utf16Start: quote.start,
                            listenerID: listener,
                            politeness: politeness(of: quote.text)
                        )
                    )
                }
            }
        }
        return result.sorted { $0.utf16Start < $1.utf16Start }
    }

    // MARK: - 존대 판정 (결정적 — 닫힌 종결어미 규칙)

    /// 발화 → 존대/반말. 문장별로 판정해 다수결, 갈리거나 못 읽으면 nil.
    ///
    /// 규칙이 **닫힌 집합**인 이유: 종결어미는 유한하고, 규칙 밖을 추정으로
    /// 채우면 틀린 존대 신호가 프롬프트에 실린다 — 침묵이 낫다 (CLAUDE.md §1-2).
    public static func politeness(of utterance: String) -> Politeness? {
        var honorific = 0
        var plain = 0
        for sentence in utterance.split(whereSeparator: { ".!?…。！？".contains($0) }) {
            switch sentencePoliteness(sentence) {
            case .honorific: honorific += 1
            case .plain: plain += 1
            case nil: break
            }
        }
        if honorific > 0, plain == 0 { return .honorific }
        if plain > 0, honorific == 0 { return .plain }
        return nil // 혼재·판정 불가 — 발화 단위에선 침묵
    }

    /// 존대 종결 — "요"로 끝나거나 격식체(-니다/-니까/-십시오 등).
    private static let honorificSuffixes = [
        "요", "니다", "니까", "십시오", "십시다", "시죠", "소서"
    ]
    /// 반말 종결 — 해체·해라체의 흔한 꼬리. 모호한 음절은 넣지 않는다:
    /// "마" 단독은 "설마"·"엄마"를 먹는다 → 금지 명령은 "지 마"/"지마"로만.
    private static let plainSuffixes = [
        "야", "어", "아", "지", "자", "니", "냐", "래", "라", "지 마", "지마",
        "걸", "게", "군", "네", "든", "잖아", "거든", "다고", "다니까", "달라고"
    ]
    /// 반말로 오판하기 쉬운 평서형 — "~했다"·"~이다"는 서술이지 반말 대사체가
    /// 아닐 수 있으나, 대사 안에서는 해라체(반말)로 본다. 단 "니다"가 먼저다.
    private static let plainDeclarative = ["다"]

    private static func sentencePoliteness(_ sentence: Substring) -> Politeness? {
        // 꼬리 정리 — 공백·물결·반복 부호는 판정에서 뺀다 ("알겠어요~~" → "알겠어요").
        let trimmed = sentence.trimmingCharacters(
            in: CharacterSet(charactersIn: " \t~ㅋㅎㅠㅜ,")
        )
        guard !trimmed.isEmpty else { return nil }
        for suffix in honorificSuffixes where trimmed.hasSuffix(suffix) {
            return .honorific
        }
        for suffix in plainSuffixes where trimmed.hasSuffix(suffix) {
            return .plain
        }
        for suffix in plainDeclarative where trimmed.hasSuffix(suffix) {
            return .plain
        }
        return nil
    }

    // MARK: - 내부: 문단 분해

    private struct Paragraph {
        var quotes: [(text: String, start: Int)]
        var speaker: UUID?
        var narration: String
        var isBlank: Bool
        var hasQuotes: Bool {
            !quotes.isEmpty
        }
    }

    /// 여닫는 따옴표 쌍 — 큰따옴표 계열만 대사로 본다 (작은따옴표는 속마음·강조).
    private static let quotePairs: [(open: Character, close: Character)] = [
        ("“", "”"), ("\"", "\""), ("「", "」"), ("『", "』")
    ]

    private struct AbsoluteQuotedSpan {
        var text: String
        var utf16Start: Int
        var utf16End: Int
    }

    /// 줄바꿈을 포함한 따옴표도 하나의 대사로 보존하는 본문 전체 스캐너.
    /// 기존 문단 귀속기가 못 읽는 형식이어도 수집 목록에서는 절대 사라지지 않는다.
    private static func allQuotedSpans(in body: String) -> [AbsoluteQuotedSpan] {
        var spans: [AbsoluteQuotedSpan] = []
        var index = body.startIndex
        var utf16Offset = 0
        while index < body.endIndex {
            let character = body[index]
            if let pair = quotePairs.first(where: { $0.open == character }) {
                let contentStart = body.index(after: index)
                if let close = body[contentStart...].firstIndex(of: pair.close) {
                    let raw = String(body[contentStart ..< close])
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    let openLength = String(character).utf16.count
                    let consumed = body[index ..< body.index(after: close)].utf16.count
                    if !text.isEmpty {
                        spans.append(AbsoluteQuotedSpan(
                            text: text, utf16Start: utf16Offset + openLength,
                            utf16End: utf16Offset + consumed - String(pair.close).utf16.count
                        ))
                    }
                    utf16Offset += consumed
                    index = body.index(after: close)
                    continue
                }
            }
            utf16Offset += String(character).utf16.count
            index = body.index(after: index)
        }
        return spans
    }

    /// 등록 카드가 없지만 원문이 역할을 직접 밝힌 좁은 경우. 임의 이름을 만들지
    /// 않고 `미등록` 표식을 남겨 스토리 바이블 등록 여부와 화자 귀속을 구분한다.
    private static func contextualRoleLabel(
        for span: AbsoluteQuotedSpan, in body: String
    ) -> String? {
        let source = body as NSString
        let lower = max(0, span.utf16Start - 220)
        let upper = min(source.length, span.utf16End + 220)
        let context = source.substring(
            with: NSRange(location: lower, length: upper - lower)
        )
        if span.text.contains("점순아"), context.contains("어머니가") {
            return "점순 어머니(미등록)"
        }
        if span.text.contains("시집"), context.contains("동리 어른이"),
           context.contains("하고 웃으면") {
            return "동리 어른(미등록)"
        }
        return nil
    }

    /// 한 문단에서 따옴표 안 대사들을 뽑는다 (UTF-16 상대 오프셋 포함).
    static func quotedSpans(in line: Substring) -> [(text: String, utf16Offset: Int)] {
        var spans: [(String, Int)] = []
        var index = line.startIndex
        var utf16Offset = 0
        while index < line.endIndex {
            let char = line[index]
            if let pair = quotePairs.first(where: { $0.open == char }) {
                let contentStart = line.index(after: index)
                if let closeIndex = line[contentStart...].firstIndex(of: pair.close) {
                    let text = String(line[contentStart ..< closeIndex])
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        spans.append((text, utf16Offset + String(char).utf16.count))
                    }
                    utf16Offset += line[index ..< line.index(after: closeIndex)].utf16.count
                    index = line.index(after: closeIndex)
                    continue
                }
            }
            utf16Offset += String(char).utf16.count
            index = line.index(after: index)
        }
        return spans
    }

    /// 문단에서 대사를 걷어낸 서술부.
    private static func narrationText(of line: Substring) -> String {
        var text = String(line)
        for span in quotedSpans(in: line) {
            text = text.replacingOccurrences(of: span.text, with: "")
        }
        return text
    }

    /// 인접 서술 귀속 — 발화 동사 옆 이름이 최우선, 없으면 서술부의 유일한 이름.
    private static func attributeFromNarration(
        _ narration: String, names: [String], nameIndex: [String: UUID],
        narratorID: UUID?
    ) -> UUID? {
        // `나는 … 말했다`, `내가 … 하니까,`처럼 1인칭 주어가 명시되면 자동
        // 등록된 화자 카드에 연결한다. 다만 뒤 절에 `점순이가 …`처럼 더 가까운
        // 등록 인물 주어가 있으면 그쪽이 말한 것이므로 마지막 주어가 이긴다.
        if let narratorID,
           let firstPosition = lastFirstPersonSubjectPosition(in: narration) {
            let namedSubjects = names.compactMap { name -> (UUID, Int)? in
                guard narrationMentionsSubject(narration, name: name),
                      let id = nameIndex[name],
                      let range = narration.range(of: name, options: .backwards)
                else { return nil }
                return (id, narration.distance(from: narration.startIndex, to: range.lowerBound))
            }
            if namedSubjects.allSatisfy({ $0.1 < firstPosition }) {
                return narratorID
            }
        }
        let mentioned = names.filter { narration.contains($0) }
        // 별칭이 본명의 부분 문자열인 경우("서연"/"연이") 같은 인물이면 하나로 본다.
        let ids = Set(mentioned.compactMap { nameIndex[$0] })
        guard !ids.isEmpty else { return nil }
        if ids.count == 1 { return ids.first }
        // 이름이 여럿이면 발화 동사에 가장 가까운 이름 — "서연이 민준을 보며
        // 말했다"에서 화자는 서연이다 (v1: 동사 앞에서 가장 가까운 이름).
        guard let verbRange = speechVerbRange(in: narration) else { return nil }
        var best: (id: UUID, distance: Int)?
        for name in mentioned {
            guard let id = nameIndex[name] else { continue }
            var searchStart = narration.startIndex
            while let range = narration.range(of: name, range: searchStart ..< narration.endIndex) {
                if range.upperBound <= verbRange.lowerBound {
                    let distance = narration.distance(
                        from: range.upperBound, to: verbRange.lowerBound
                    )
                    if best == nil || distance < best!.distance {
                        best = (id, distance)
                    }
                }
                searchStart = range.upperBound
            }
        }
        return best?.id
    }

    private static func speechVerbRange(in narration: String) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        for stem in speechVerbStems {
            if let range = narration.range(of: stem) {
                if earliest == nil || range.lowerBound < earliest!.lowerBound {
                    earliest = range
                }
            }
        }
        return earliest
    }

    /// 대사 문단 바로 앞·뒤의 서술을 귀속 근거로 쓴다. 빈 줄은 출판 레이아웃일
    /// 뿐 의미 경계가 아니므로 건너뛰되, 다른 대사 문단을 넘어가지는 않는다.
    private static func attributeFromNeighborNarration(
        _ paragraphs: inout [Paragraph], names: [String],
        nameIndex: [String: UUID], narratorID: UUID?
    ) {
        func neighbor(of index: Int, step: Int) -> String? {
            var cursor = index + step
            while paragraphs.indices.contains(cursor) {
                let paragraph = paragraphs[cursor]
                if paragraph.hasQuotes { return nil }
                if !paragraph.isBlank { return paragraph.narration }
                cursor += step
            }
            return nil
        }

        for index in paragraphs.indices
            where paragraphs[index].hasQuotes && paragraphs[index].speaker == nil {
            let previous = neighbor(of: index, step: -1)
            let following = neighbor(of: index, step: 1)

            if let following,
               speechVerbRange(in: following) != nil,
               let speaker = attributeFromNarration(
                   following, names: names, nameIndex: nameIndex,
                   narratorID: narratorID
               ) {
                paragraphs[index].speaker = speaker
                continue
            }

            if let previous {
                let trimmed = previous.trimmingCharacters(in: .whitespaces)
                let isLeadIn = trimmed.hasSuffix(",") || trimmed.hasSuffix(":")
                let hasSpeechVerb = speechVerbRange(in: previous) != nil
                // 쉼표 리드인은 `점순이가 … 놓고는,`처럼 등록 인물이 문법적
                // 주어일 때만 쓴다. `나는 … 점순이 집에 …,`의 목적·소유 언급을
                // 화자로 오인한 「동백꽃」 실제 회귀를 막는다.
                let leadInHasNamedSubject = isLeadIn && names.contains {
                    narrationMentionsSubject(previous, name: $0)
                }
                let leadInHasNarratorSubject = isLeadIn
                    && narratorID != nil
                    && lastFirstPersonSubjectPosition(in: previous) != nil
                if (hasSpeechVerb || leadInHasNamedSubject || leadInHasNarratorSubject),
                   let speaker = attributeFromNarration(
                       previous, names: names, nameIndex: nameIndex,
                       narratorID: narratorID
                   ) {
                    paragraphs[index].speaker = speaker
                    continue
                }
            }

            // 이름은 앞 리드인, 발화 동사는 뒤의 `하고 물었다`에 갈라진 형식.
            if let previous, let following,
               speechVerbRange(in: following) != nil,
               let speaker = attributeFromNarration(
                   previous, names: names, nameIndex: nameIndex,
                   narratorID: narratorID
               ) {
                paragraphs[index].speaker = speaker
            }
        }
    }

    private static func narrationMentionsSubject(_ narration: String, name: String) -> Bool {
        var start = narration.startIndex
        while let range = narration.range(of: name, range: start ..< narration.endIndex) {
            let tail = narration[range.upperBound...]
            if tail.hasPrefix("이가") || tail.hasPrefix("가 ") || tail.hasPrefix("가,")
                || tail.hasPrefix("은 ") || tail.hasPrefix("는 ")
                || tail.hasPrefix("께서") {
                return true
            }
            start = range.upperBound
        }
        return false
    }

    private static func lastFirstPersonSubjectPosition(in narration: String) -> Int? {
        let subjects = ["나는", "내가", "나도", "난 ", "저는", "제가", "저도", "전 "]
        return subjects.compactMap { subject -> Int? in
            guard let range = narration.range(of: subject, options: .backwards) else {
                return nil
            }
            return narration.distance(from: narration.startIndex, to: range.lowerBound)
        }.max()
    }

    // MARK: - 내부: 대화 런·교대 규칙

    /// 발화 문단들의 연속 구간(런) — 사이의 서술 문단은 1개까지 허용한다
    /// ("대사, 서술 한 줄, 대사"는 같은 대화다). 빈 줄 2연속·헤딩은 런을 끊는다.
    private static func dialogueRuns(_ paragraphs: [Paragraph]) -> [[Paragraph]] {
        var runs: [[Paragraph]] = []
        var current: [Paragraph] = []
        var gap = 0
        for paragraph in paragraphs {
            if paragraph.hasQuotes {
                current.append(paragraph)
                gap = 0
            } else if paragraph.isBlank {
                // 문단 사이 빈 줄은 대화 런을 끊지 않는다. 비대사 내용 문단의
                // 개수만 센다 — `대사→빈 줄→귀속 서술→빈 줄→대사`가 한 런이다.
                continue
            } else if !current.isEmpty {
                gap += 1
                if gap > 1 {
                    runs.append(current)
                    current = []
                    gap = 0
                }
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// 교대 규칙 — 화자 둘이 확정된 런에서, 미귀속 문단을 이웃의 반대 화자로
    /// 채운다. 확정 화자가 0·1·3+명이면 채우지 않는다 (모호 — 침묵이 정답).
    private static func fillByAlternation(_ run: [Paragraph]) -> [Paragraph] {
        let known = run.compactMap(\.speaker)
        let speakers = Array(Set(known))
        guard speakers.count == 2 else { return run }

        var filled = run
        // 앞→뒤: 직전 확정 화자의 반대로 채운다. 연속 미귀속도 교대로 이어진다.
        var previous: UUID?
        for index in filled.indices {
            if let speaker = filled[index].speaker {
                previous = speaker
            } else if let last = previous {
                let next = speakers.first(where: { $0 != last })
                filled[index].speaker = next
                previous = next
            }
        }
        // 런 머리의 미귀속(직전 화자가 없던 구간)은 뒤에서 앞으로 한 번 더.
        var following: UUID?
        for index in filled.indices.reversed() {
            if let speaker = filled[index].speaker {
                following = speaker
            } else if let next = following {
                let previous = speakers.first(where: { $0 != next })
                filled[index].speaker = previous
                following = previous
            }
        }
        return filled
    }
}
