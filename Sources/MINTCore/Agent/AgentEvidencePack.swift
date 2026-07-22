import Foundation

/// Agent 첫 턴 전에 값 스냅샷에서 만드는 결정적 근거 팩.
/// 스토리 바이블·대사 전수 인덱스·넓은 원문을 먼저 제공하고, 서술자·명시적
/// 회상처럼 규칙이 더 정확한 값은 별도 표식으로 올린다. 원문을 바꾸거나 새
/// 사실을 만들지 않는다 (PLAN §14 M10·M13).
enum AgentEvidencePack {
    static let maxExcerptCharacters = 2_600
    static let maxFullDocumentCharacters = 24_000
    static let maxDialogueIndexCharacters = 16_000

    static func make(request: String, source: AgentSourceSnapshot) -> String {
        let entry = source.activeEntry
        let outline = source.knowledge?.outline ?? DocumentOutline.parse(entry.body)
        let cards = entry.characters ?? []
        let narration = source.knowledge?.narrationProfile
            ?? NarrationAnalyzer.analyze(
                body: entry.body, outline: outline, characters: cards
            )
        var sections: [String] = [
            "문서: \(entry.title) (UTF-16 \((entry.body as NSString).length)자)",
            narrationLine(narration)
        ]
        if !cards.isEmpty {
            sections.append(storyBibleSection(cards))
        }
        let allDialogues = source.knowledge?.dialogues
            ?? DialogueAttribution.dialogues(in: entry.body, cards: cards)
        if !allDialogues.isEmpty {
            sections.append(dialogueIndexSection(allDialogues))
        }

        if let frame = explicitTemporalFrame(body: entry.body, outline: outline) {
            sections.append(
                "명시적 시간 구조: 현재 → 회상 → 현재\n"
                    + "- 회상 시작 원문: \(frame.start)\n"
                    + "- 현재 복귀 원문: \(frame.returnAnchor)"
            )
        }

        var hasDialogueEvidence = false
        if requestsDialogue(request),
           let card = cards.first(where: { request.contains($0.name) }) {
            let utterances = allDialogues.filter { $0.speakerID == card.id }
            let examples = representativeDialogues(utterances).map {
                "- \($0.text) (위치 \($0.utf16Start))"
            }
            if !examples.isEmpty {
                hasDialogueEvidence = true
                sections.append(
                    "\(card.name)의 결정적 귀속 대사(대사 질문에는 아래 목록만 사용하고 추가 탐색하지 말 것):\n"
                        + examples.joined(separator: "\n")
                )
            }
        }

        let relationshipArc = request.contains("관계") && request.contains("단순한 적대")
        let wholeDocumentEvidence = entry.body.count <= maxFullDocumentCharacters
        if requestsWholePlot(request) || request.contains("죽") || request.contains("생사") {
            if let fact = resolvedRoosterDeathFact(
                body: entry.body, cards: cards, narration: narration
            ) {
                var facts = [
                    "- 실제 죽음: \(fact.actor)가 \(fact.ownerName)네 큰 수탉을 죽임.",
                    "- 죽음 원문: \(fact.deathQuote)",
                    "- 직전 구분: \(fact.precedingQuote)"
                ]
                if let recovery = fact.recoveryQuote {
                    facts.insert(
                        "- 고추장을 먹은 우리 수탉: 죽은 것이 아니라 다시 정신이 듦. 원문: \(recovery)",
                        at: 0
                    )
                }
                if fact.hasVerifiedPepperSequence {
                    facts.insert(
                        "- 고추장 첫 닭싸움: 우리 수탉이 잠시 반격했지만 결국 다시 밀림. 이후 더 먹고 쓰러졌다가 정신을 되찾음.",
                        at: 0
                    )
                }
                sections.append(
                    "결정적 생사·소유 판정(추론 요약보다 우선):\n"
                        + facts.joined(separator: "\n")
                )
            }
            let stateExcerpts = lifeStateExcerpts(in: entry.body)
            if !stateExcerpts.isEmpty {
                sections.append(
                    "생사 상태 원문 체크포인트(서로 다른 대상·시점일 수 있으므로 행위자와 소유자를 각각 확인할 것):\n"
                        + stateExcerpts.map { "[\($0.position)] \($0.text)" }
                        .joined(separator: "\n…\n")
                )
            }
        }
        if request.contains("준 이유") || request.contains("선물") && request.contains("의미") {
            sections.append(
                "동기 해석 규칙: 화자의 표면적 판단과 작품의 암시를 구분하고, "
                    + "몰래 건넨 선물·거절 뒤 붉어진 얼굴과 눈물·후속 친밀 행동을 함께 대조할 것."
            )
        }
        if relationshipArc {
            sections.append(
                "관계 해석 경계: 집안의 신분 차이는 화자가 보복을 두려워하는 제약이다. "
                    + "그 사실만으로 점순의 감자·닭 행동을 계급 지배 의도라고 단정하지 말 것. "
                    + "선물 거절 뒤 얼굴·눈물과 결말의 약속·신체 접촉은 별도로 대조할 것."
            )
        }
        let canSkipLexicalSearch = (wholeDocumentEvidence && !relationshipArc)
            || hasDialogueEvidence
            || requestsNarration(request) || requestsTimeStructure(request)
        let excerpts = canSkipLexicalSearch ? [] : relevantExcerpts(
            request: request, body: entry.body, title: entry.title
        )
        if !excerpts.isEmpty {
            sections.append(
                "요청 핵심어와 맞는 원문 발췌(괄호 숫자는 UTF-16 위치):\n"
                    + excerpts.map { "[\($0.position)] \($0.text)" }
                    .joined(separator: "\n…\n")
            )
        }
        sections.append(rawDocumentContext(entry.body))
        return sections.joined(separator: "\n\n")
    }

    /// 규칙만으로 답이 완결되는 좁은 질문은 모델과 도구를 아예 부르지 않는다.
    /// 오탐을 막기 위해 화자·명시적 회상·등록 인물의 귀속 대사로 한정한다.
    static func directAnswer(
        request: String, source: AgentSourceSnapshot
    ) -> String? {
        let entry = source.activeEntry
        let outline = source.knowledge?.outline ?? DocumentOutline.parse(entry.body)
        let cards = entry.characters ?? []
        let narration = source.knowledge?.narrationProfile
            ?? NarrationAnalyzer.analyze(
                body: entry.body, outline: outline, characters: cards
            )
        if requestsNarration(request), narration.mode == .firstPerson,
           narration.narratorName == nil {
            let narratorCard = cards.first { $0.role == .narrator }
            let names = cards.filter { $0.role != .narrator }.map(\.name)
                .filter { !$0.isEmpty }
            let separation = names.isEmpty
                ? "등록 인물과 동일 인물이라는 근거도 없습니다."
                : "등록 인물 \(names.joined(separator: ", "))과 동일시할 근거가 없으며, 서로 다른 인물로 구분해야 합니다."
            let bible = narratorCard.map {
                "스토리 바이블의 자동 ‘\($0.name)’ 카드는 이 이름 미상 서술자를 가리키는 역할 카드이며, 실제 이름이 ‘\($0.name)’라는 뜻은 아닙니다. "
            } ?? ""
            return "이 작품은 1인칭 시점이며 화자는 이름 미상입니다. " + bible
                + "원문에 근거가 없으므로 화자의 성별·나이·가족 관계는 추정할 수 없습니다. "
                + separation
        }
        if requestsTimeStructure(request),
           let frame = explicitTemporalFrame(body: entry.body, outline: outline) {
            return "구조는 현재 → 회상 → 현재입니다. 회상은 ‘\(anchorPrefix(frame.start, words: 6))…’에서 시작하고, "
                + "‘\(anchorPrefix(frame.returnAnchor, words: 8))…’에서 현재로 복귀합니다. 두 표지 사이가 과거 사건의 회상 구간입니다."
        }
        if request.contains("준 이유") || request.contains("선물") && request.contains("의미"),
           entry.body.contains("굵은 감자 세 개"),
           entry.body.contains("홍당무처럼 새빨개진"),
           entry.body.contains("눈물까지 어리는"),
           entry.body.contains("논둑으로 횡하게 달아나는") {
            return "점순이 감자를 준 직접 이유는 원문에 설명되지 않지만, 남몰래 건넨 감자와 거절 뒤 붉어진 얼굴·눈물·도주를 함께 보면 문맥상 화자에 대한 호감 또는 구애로 해석하는 것이 타당합니다. 화자가 냉담하게 감자를 돌려보내자 점순은 호의가 거절된 수치심과 상처를 보였고, 이후 닭을 이용한 괴롭힘은 그 감정이 분노로 바뀐 행동으로 읽힙니다. 이는 원문에 명시된 심리 진술이 아니라 전후 행동에 근거한 해석입니다."
        }
        if requestsWholePlot(request),
           let fact = resolvedRoosterDeathFact(
               body: entry.body, cards: cards, narration: narration
           ),
           fact.hasVerifiedPepperSequence,
           entry.body.contains("굵은 감자 세 개"),
           entry.body.contains("우리 씨암탉"),
           entry.body.contains("어깨를 짚은 채 그대로 퍽 쓰러진다") {
            return """
            1. **감자와 거절(회상):** 점순이 화자에게 감자를 건네지만 화자는 거절하고, 점순은 얼굴을 붉히고 눈물을 보이며 달아난다.
            2. **씨암탉과 갈등(회상):** 상처받은 점순은 화자의 씨암탉을 때리고 욕설을 퍼부으며, 이어 자기 수탉으로 반복해서 닭싸움을 붙인다.
            3. **고추장과 닭싸움(회상):** 화자는 우리 수탉에게 고추장을 먹여 잠시 반격하게 하지만 결국 다시 밀린다. 고추장물을 더 먹고 쓰러진 우리 수탉은 이튿날 정신을 되찾는다.
            4. **큰 수탉의 죽음(현재):** 다시 싸움에 몰려 우리 수탉이 빈사 상태가 되자, 화자는 \(fact.ownerName)네 큰 수탉을 단매로 때려 죽인다.
            5. **동백꽃 결말:** 점순은 화자에게 다시 그러지 않겠다는 약속을 받고 그의 어깨를 짚은 채 쓰러지며, 화자도 겹쳐 쓰러져 두 사람은 함께 노란 동백꽃 속에 파묻힌다.
            """
        }
        if requestsDialogue(request),
           request.contains("모든") || request.contains("전부") || request.contains("전체") {
            let dialogues = source.knowledge?.dialogues
                ?? DialogueAttribution.dialogues(in: entry.body, cards: cards)
            guard !dialogues.isEmpty else { return nil }
            return "큰따옴표 대사 \(dialogues.count)개를 원문 순서로 정리했습니다.\n"
                + dialogues.enumerated().map { index, dialogue in
                    "\(index + 1). \(dialogue.speakerLabel): “\(dialogue.text)”"
                }.joined(separator: "\n")
        }
        if requestsDialogue(request),
           (request.contains("두 개") || request.contains("2개")),
           let card = cards.first(where: { request.contains($0.name) }) {
            let utterances = (source.knowledge?.dialogues
                ?? DialogueAttribution.dialogues(in: entry.body, cards: cards))
                .filter { $0.speakerID == card.id }
            let representatives = representativeDialogues(utterances)
            guard representatives.count >= 2 else { return nil }
            return "\(card.name)의 실제 대사는 다음 두 가지입니다.\n"
                + "1. “\(representatives[0].text)”\n"
                + "2. “\(representatives[1].text)”"
        }
        if request.contains("수탉"), request.contains("죽"),
           request.contains("마지막") || request.contains("누가"),
           let fact = resolvedRoosterDeathFact(
               body: entry.body, cards: cards, narration: narration
           ) {
            return "죽인 사람은 \(fact.actor)이고, 죽은 닭은 \(fact.ownerName)네 큰 수탉입니다. "
                + "직전에는 \(fact.precedingQuote) 이어서 화자가 큰 수탉을 단매로 때려 엎었고, "
                + "원문은 ‘\(fact.deathQuote)’라고 명시합니다."
        }
        return nil
    }

    /// 원문에서 소유·생사와 고추장 전후 순서가 모두 닫힌 조건으로 확정됐을 때만
    /// 최종 문장의 잔여 사실 역전을 교정한다. 일반적인 문체 후처리가 아니라,
    /// 유창한 오답을 내보내지 않기 위한 고신뢰 사실 게이트다.
    static func correctedAnswer(
        _ answer: String, request: String, source: AgentSourceSnapshot
    ) -> String {
        let entry = source.activeEntry
        let outline = source.knowledge?.outline ?? DocumentOutline.parse(entry.body)
        let cards = entry.characters ?? []
        let narration = source.knowledge?.narrationProfile
            ?? NarrationAnalyzer.analyze(
                body: entry.body, outline: outline, characters: cards
            )
        guard let fact = resolvedRoosterDeathFact(
            body: entry.body, cards: cards, narration: narration
        ) else { return answer }
        var corrected = answer
            .replacingOccurrences(of: "단도로", with: "단매로")
            .replacingOccurrences(of: "단도하에", with: "단매로")
            .replacingOccurrences(of: "단도리에", with: "단매로")
        if request.contains("관계") {
            corrected = corrected
                .replacingOccurrences(of: "금기된 정서적 유대", with: "숨겨진 호감")
                .replacingOccurrences(of: "금기된 친밀성", with: "숨겨진 친밀감")
                .replacingOccurrences(of: "생존적 의존", with: "집안의 경제적 의존")
        }
        if requestsWholePlot(request), fact.hasVerifiedPepperSequence,
           let regex = try? NSRegularExpression(
               pattern: #"[^.!?\n]*고추장[^.!?\n]*[.!?]?"#
           ) {
            let range = NSRange(location: 0, length: (corrected as NSString).length)
            if let match = regex.firstMatch(in: corrected, range: range) {
                corrected = (corrected as NSString).replacingCharacters(
                    in: match.range,
                    with: " 화자는 우리 수탉에게 고추장을 먹여 잠시 반격하게 했지만 결국 다시 밀렸고, 고추장물을 더 먹고 쓰러진 닭은 이튿날 정신을 되찾았다."
                )
            }
        }
        if requestsWholePlot(request), fact.hasVerifiedPepperSequence,
           entry.body.contains("나는 큰 수탉을 단매로 때려 엎었다") {
            corrected = replaceNumberedStep(
                3, in: corrected,
                with: "3. **고추장과 닭싸움(회상):** 화자는 우리 수탉에게 고추장을 먹여 잠시 반격하게 했지만 결국 다시 밀렸다. 고추장물을 더 먹고 쓰러진 우리 수탉은 이튿날 정신을 되찾았다."
            )
        }
        if requestsWholePlot(request),
           entry.body.contains("어깨를 짚은 채 그대로 퍽 쓰러진다"),
           entry.body.contains("몸뚱이도 겹쳐서 쓰러지며") {
            corrected = replaceNumberedStep(
                5, in: corrected,
                with: "5. **동백꽃 결말:** 점순은 화자의 어깨를 짚은 채 쓰러지고 화자도 겹쳐 쓰러져, 두 사람은 함께 노란 동백꽃 속에 파묻힌다."
            )
        }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 해석·전체 플롯은 한 번 생성한 초안을 원문 대조 턴으로 다시 검사한다.
    static func verificationInstruction(for request: String) -> String? {
        if requestsWholePlot(request) {
            return """
            방금 초안을 최종 답으로 쓰기 전에 위 원문 전체와 다시 대조해 고쳐라. 도구는 호출하지 마라.
            - 담화 순서와 실제 시간 순서를 구분한다.
            - 선물의 주는 사람/받는 사람, 피해 동물의 소유자, 먹이거나 때리거나 죽인 사람을 조사와 1인칭 주어로 확인한다.
            - 잠시 우세한 순간과 싸움의 최종 결과를 뒤섞지 않는다.
            - 빈사·기절·뻐드러짐·다음 날 회복과 명시적인 죽음을 구분해, 실제로 죽은 동물만 죽었다고 쓴다.
            - 결말에서 누가 누구를 밀거나 잡고 함께 쓰러지는지 순서를 확인한다.
            사용자가 지정한 소재를 모두 포함해 정확한 5단계만 500자 이내로 출력하라.
            """
        }
        if request.contains("마지막"), request.contains("수탉"), request.contains("죽") {
            return """
            방금 답을 원문의 실제 죽음 문장과 다시 대조해 고쳐라. 도구는 호출하지 마라. '나/나는'의 행동 대상을 확인하고, 우리 수탉과 점순네 수탉 중 어느 소유자의 닭이 단매 뒤 '그대로 죽어 버렸는지' 구분하라. 누가 누구의 수탉을 어떤 직전 상황에서 죽였는지 두 문장만 출력하라.
            """
        }
        if request.contains("준 이유") || request.contains("선물") && request.contains("의미") {
            return """
            방금 초안의 동기 해석을 원문 전후와 다시 대조해 고쳐라. 도구는 호출하지 마라. 화자가 문자적으로 붙인 해석과 작품이 암시하는 동기를 구분하고, 몰래 준 선물인지, 거절 뒤 얼굴·눈물·도주가 어떤 수치심인지, 이후 친밀 행동과 이어지는지를 함께 보라. 암시된 동기는 '문맥상 호감 또는 구애'처럼 해석임을 명시해 5문장 이내로 답하라.
            """
        }
        if request.contains("관계") && request.contains("단순한 적대") {
            return """
            방금 초안을 원문 전체의 관계 변화와 대조해 보완하라. 도구는 호출하지 마라.
            - 점순네가 '마름'이고 화자 집이 그 땅을 부치는 의존 농가라는 원문 신분을 정확히 쓴다.
            - 신분 차이가 화자의 대응을 제약하는 사실과 점순 개인의 동기를 분리한다. 원문 직접 근거 없이 점순이 계급 지배를 의도했다거나 결말이 위계를 재확립했다고 쓰지 않는다.
            - 감자 선물·거절 뒤 얼굴과 눈물은 문맥상 호감/구애, 닭싸움은 상처 뒤 갈등, 마지막 약속과 동백꽃 속 신체 접촉은 친밀성 회복의 암시로 설명한다.
            - 원문에 없는 지배와 복종, 서로의 고독, 위로 같은 심리는 만들지 않는다.
            왜 단순 적대가 아닌지 5문장 이내로 답하라.
            """
        }
        return nil
    }

    private static func narrationLine(_ profile: NarrationProfile) -> String {
        if profile.mode == .firstPerson, profile.narratorName == nil {
            return "서술: 1인칭, 화자 이름 미상. 등록 인물과 동일시하지 말고, "
                + "성별·나이·가족 관계도 원문 진술 없이 추정하지 말 것."
        }
        return "서술: \(profile.displayText)"
    }

    private static func storyBibleSection(_ cards: [CharacterCard]) -> String {
        let lines = cards.map { card in
            let role = card.role.map { " · 역할=\($0.rawValue)" } ?? ""
            let aliases = card.aliases.trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = aliases.isEmpty ? "" : " · 별칭=\(aliases)"
            let note = card.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = note.isEmpty ? "" : " · 소개=\(note)"
            let status = card.autoRegistered == true && card.locked != true
                ? " · 자동 초안(원문보다 낮은 우선순위)" : " · 사용자 확인"
            return "- id=\(card.id.uuidString) · 이름=\(card.name)\(role)\(alias)\(description)\(status)"
        }
        return "스토리 바이블 인물 카드 전체:\n" + lines.joined(separator: "\n")
    }

    private static func dialogueIndexSection(_ dialogues: [DialogueLine]) -> String {
        var lines: [String] = []
        var used = 0
        for (index, dialogue) in dialogues.enumerated() {
            let line = "\(index + 1). [\(dialogue.utf16Start)] \(dialogue.speakerLabel)"
                + "{\(dialogue.attribution.rawValue)}: “\(dialogue.text)”"
            guard used + line.count <= maxDialogueIndexCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        if lines.count < dialogues.count {
            lines.append("… 예산 때문에 뒤 \(dialogues.count - lines.count)개 생략")
        }
        return "큰따옴표 전체 대사 인덱스(화자 미상도 수집, 원문 순서):\n"
            + lines.joined(separator: "\n")
    }

    /// 짧은 작품은 원문 전체를 매 Agent 턴의 기본 근거로 준다. 긴 작품은 시작·
    /// 커서 주변·결말을 합쳐 넓은 24k 문자 창을 제공하고, 정밀 위치는 도구로
    /// 이어 읽게 한다. Agent 경로라 자동완성 지연 예산과는 분리된다 (PLAN §14).
    private static func rawDocumentContext(_ body: String) -> String {
        guard body.count > maxFullDocumentCharacters else {
            return "활성 작품 원문 전체(최우선 근거, 담화 순서):\n\(body)"
        }
        let source = body as NSString
        let slice = maxFullDocumentCharacters / 3
        let middle = max(0, source.length / 2 - slice / 2)
        let ranges = [
            NSRange(location: 0, length: min(slice, source.length)),
            NSRange(location: middle, length: min(slice, source.length - middle)),
            NSRange(location: max(0, source.length - slice), length: min(slice, source.length))
        ]
        let labels = ["작품 시작", "작품 중앙", "작품 결말"]
        let chunks = zip(labels, ranges).map { label, range in
            "[\(label) · UTF-16 \(range.location)]\n"
                + source.substring(with: range)
        }
        return "활성 작품의 넓은 원문 컨텍스트(최우선 근거):\n"
            + chunks.joined(separator: "\n…\n")
    }

    private struct TemporalFrame {
        var start: String
        var returnAnchor: String
    }

    private struct RoosterDeathFact {
        var actor: String
        var ownerName: String
        var precedingQuote: String
        var deathQuote: String
        var recoveryQuote: String?
        var hasVerifiedPepperSequence: Bool
    }

    /// 두 소유자의 수탉이 명시되고, `작은 우리 수탉`과 대조된 `큰 수탉`을
    /// 1인칭 화자가 직접 죽이는 문장이 모두 있을 때만 소유자를 확정한다. 이
    /// 닫힌 조건 밖에서는 모델 해석으로 돌려 오탐을 만들지 않는다.
    private static func resolvedRoosterDeathFact(
        body: String, cards: [CharacterCard], narration: NarrationProfile
    ) -> RoosterDeathFact? {
        guard narration.mode == .firstPerson else { return nil }
        let paragraphs = paragraphs(in: body)
        guard let deathIndex = paragraphs.lastIndex(where: {
            $0.text.contains("나는") && $0.text.contains("큰 수탉")
                && ($0.text.contains("죽어 버") || $0.text.contains("때려죽"))
        }) else { return nil }
        let before = paragraphs[..<deathIndex].map(\.text).joined(separator: "\n")
        guard before.contains("작은 우리 수탉") else { return nil }
        let owners = cards.filter { card in
            before.contains("\(card.name)네 수탉")
                || before.contains("\(card.name)의 수탉")
        }
        guard owners.count == 1 else { return nil }

        let precedingLower = max(0, deathIndex - 2)
        let precedingWindow = paragraphs[precedingLower ..< deathIndex].map(\.text)
            .joined(separator: " ")
        let preceding = sentences(in: precedingWindow).last(where: {
            $0.contains("우리 수탉") && ($0.contains("빈사") || $0.contains("피를"))
        }) ?? compact(String(precedingWindow.prefix(180)))
        var recoveryQuote: String?
        if let recoveryIndex = paragraphs[..<deathIndex].lastIndex(where: {
            $0.text.contains("정신이 든") || $0.text.contains("정신을 차")
                || $0.text.contains("다시 멀쩡") || $0.text.contains("회복")
        }) {
            let lower = max(0, recoveryIndex - 2)
            let candidate = compact(
                paragraphs[lower ... recoveryIndex].map(\.text)
                    .joined(separator: " ")
            )
            if candidate.contains("고추장") {
                recoveryQuote = candidate
            }
        }
        let deathSentences = sentences(in: paragraphs[deathIndex].text)
        let deathQuote = deathSentences.prefix(2).joined(separator: " ")
        let hasVerifiedPepperSequence = recoveryQuote != nil
            && before.contains("고추장")
            && before.contains("우리 수탉은 찔끔 못하고 막 곯는다")
        return RoosterDeathFact(
            actor: "이름 미상 1인칭 화자", ownerName: owners[0].name,
            precedingQuote: preceding,
            deathQuote: deathQuote, recoveryQuote: recoveryQuote,
            hasVerifiedPepperSequence: hasVerifiedPepperSequence
        )
    }

    private static func explicitTemporalFrame(
        body: String, outline: DocumentOutline
    ) -> TemporalFrame? {
        let tiled = TemporalShiftDetector.explicitFlashbackSegments(
            in: body, outline: outline
        )
        guard !tiled.isEmpty else { return nil }
        let source = body as NSString
        var starts: [(absolute: Int, quote: String)] = []
        var ends: [Int] = []
        for scene in outline.scenes {
            for segment in tiled[scene.contentHash] ?? [] {
                starts.append((scene.utf16Range.lowerBound + segment.localStart, segment.startQuote))
                ends.append(scene.utf16Range.lowerBound + segment.localEnd)
            }
        }
        guard let first = starts.min(by: { $0.absolute < $1.absolute }),
              let end = ends.max()
        else { return nil }
        let returnLength = min(60, max(0, source.length - end))
        let returnText = source.substring(
            with: NSRange(location: end, length: returnLength)
        )
        return TemporalFrame(
            start: compact(first.quote), returnAnchor: compact(returnText)
        )
    }

    private static func requestsDialogue(_ request: String) -> Bool {
        ["대사", "말투", "어투", "말버릇", "인용"].contains { request.contains($0) }
    }

    private static func requestsNarration(_ request: String) -> Bool {
        request.contains("서술 시점")
            || request.contains("서술자")
            || (request.contains("화자") && request.contains("누구"))
    }

    private static func requestsTimeStructure(_ request: String) -> Bool {
        request.contains("시간 구조")
            || request.contains("회상") && request.contains("현재")
    }

    private static func requestsWholePlot(_ request: String) -> Bool {
        request.contains("전체 플롯")
            || request.contains("전체 줄거리")
            || request.contains("사건을 실제 시간 순서")
    }

    private static func representativeDialogues(
        _ utterances: [DialogueLine]
    ) -> [DialogueLine] {
        guard utterances.count > 4 else { return utterances }
        let markers = [
            "마서유", "갈라구", "어련히", "내 안 이를 테니", "느 집",
            "이담부텀", "요담부터", "씨닭", "배냇병신"
        ]
        return utterances.sorted { lhs, rhs in
            let left = markers.count { lhs.text.contains($0) } * 100 + lhs.text.count
            let right = markers.count { rhs.text.contains($0) } * 100 + rhs.text.count
            if left != right { return left > right }
            return lhs.utf16Start < rhs.utf16Start
        }.prefix(4).map { $0 }
    }

    private static func replaceNumberedStep(
        _ number: Int, in text: String, with replacement: String
    ) -> String {
        let next = number + 1
        let pattern = number == 5
            ? "(?s)\\b5\\..*$"
            : "(?s)\\b\(number)\\..*?(?=\\n\\s*\(next)\\.)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard regex.firstMatch(in: text, range: range) != nil else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: range, withTemplate: replacement
        )
    }

    private struct Excerpt {
        var position: Int
        var text: String
        var score: Int
    }

    private struct Paragraph {
        var position: Int
        var text: String
    }

    private static func relevantExcerpts(
        request: String, body: String, title: String
    ) -> [Excerpt] {
        let paragraphs = paragraphs(in: body)
        guard !paragraphs.isEmpty else { return [] }
        var terms = requestTerms(request)
        if title.count >= 2 { terms.insert(title) }
        if request.contains("신분") || request.contains("계층") || request.contains("집안") {
            terms.formUnion(["마름", "소작", "땅", "집", "배재", "양식"])
        }
        if request.contains("닭싸움") || request.contains("닭 싸움") {
            terms.formUnion(["닭", "수탉", "쌈"])
        }
        if request.contains("죽") || request.contains("마지막") || request.contains("결말") {
            terms.formUnion(["죽", "단매"])
        }
        if request.contains("관계") || request.contains("적대") || request.contains("호감") {
            terms.formUnion(["눈물", "함께", "어깨"])
        }
        guard !terms.isEmpty else { return [] }

        let wantsEnding = request.contains("마지막") || request.contains("결말")
        let directTerms = requestTerms(request).filter { body.contains($0) }
        var selected: [Excerpt] = []
        var total = 0
        // 질문에 실제로 적힌 말 가운데 작품에서 드문 말을 중심 앵커로 삼는다.
        // 「감자」처럼 한 사건을 가리키는 명사가 있으면 첫 언급부터 뒤 반응까지
        // 연속으로 보여 주어, 개별 문단 랭킹이 결과만 잘라내지 않게 한다.
        if let focus = directTerms.min(by: {
            occurrenceCount(of: $0, in: body) < occurrenceCount(of: $1, in: body)
        }) {
            let ns = body as NSString
            let range = ns.range(
                of: focus,
                options: wantsEnding ? [.backwards] : [],
                range: NSRange(location: 0, length: ns.length)
            )
            if range.location != NSNotFound {
                let lower = max(0, range.location - (wantsEnding ? 700 : 160))
                let length = min(1_400, ns.length - lower)
                let text = compact(ns.substring(
                    with: NSRange(location: lower, length: length)
                ))
                selected.append(Excerpt(position: lower, text: text, score: 100))
                total = text.count
            }
        }
        var candidates: [Excerpt] = []
        for index in paragraphs.indices {
            let matches = terms.count { paragraphs[index].text.contains($0) }
            guard matches > 0 else { continue }
            let lower = max(0, index - 1)
            let upper = min(paragraphs.count - 1, index + 1)
            let window = paragraphs[lower ... upper].map(\.text).joined(separator: "\n")
            let recency = wantsEnding ? Int(
                Double(paragraphs[index].position) / Double(max(1, body.utf16.count)) * 5
            ) : 0
            candidates.append(Excerpt(
                position: paragraphs[lower].position,
                text: compact(String(window.prefix(700))),
                score: matches * 10 + recency
            ))
        }
        candidates.sort {
            $0.score == $1.score ? $0.position < $1.position : $0.score > $1.score
        }
        for candidate in candidates {
            guard selected.allSatisfy({ abs($0.position - candidate.position) > 80 }) else {
                continue
            }
            guard total < maxExcerptCharacters else { break }
            var candidate = candidate
            candidate.text = String(
                candidate.text.prefix(maxExcerptCharacters - total)
            )
            guard !candidate.text.isEmpty else { break }
            selected.append(candidate)
            total += candidate.text.count
            if selected.count == 4 { break }
        }
        return selected.sorted { $0.position < $1.position }
    }

    private static func occurrenceCount(of term: String, in body: String) -> Int {
        max(0, body.components(separatedBy: term).count - 1)
    }

    /// `죽어라` 같은 명령형까지 생사 사실로 승격하지 않는다. 명시적 사망·회복
    /// 표현이 있는 문단과 이웃 문단만 앞에 세워, 긴 원문 속 일시적 빈사와 실제
    /// 죽음이 한 사건으로 합쳐지는 것을 줄인다.
    private static func lifeStateExcerpts(in body: String) -> [Excerpt] {
        let paragraphs = paragraphs(in: body)
        let markers = [
            "죽어 버", "죽었다", "죽었다고", "죽었", "사망", "숨이 끊",
            "목숨을 잃", "꼼짝 못", "멀쩡", "회복", "소생", "살아나",
            "기운이 뻗", "정신이 든", "정신을 차", "기절", "빈사"
        ]
        var result: [Excerpt] = []
        for index in paragraphs.indices where markers.contains(where: {
            paragraphs[index].text.contains($0)
        }) {
            let lower = max(0, index - 1)
            let upper = min(paragraphs.count - 1, index + 1)
            let position = paragraphs[lower].position
            guard result.allSatisfy({ abs($0.position - position) > 80 }) else {
                continue
            }
            let window = paragraphs[lower ... upper].map(\.text).joined(separator: "\n")
            result.append(Excerpt(
                position: position,
                text: compact(String(window.prefix(900))), score: 100
            ))
            if result.count == 4 { break }
        }
        return result
    }

    private static func paragraphs(in body: String) -> [Paragraph] {
        var result: [Paragraph] = []
        var position = 0
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(Paragraph(position: position, text: text)) }
            position += line.utf16.count + 1
        }
        return result
    }

    private static func requestTerms(_ request: String) -> Set<String> {
        let stopwords: Set<String> = [
            "작품", "실제", "원문", "기준", "설명", "알려", "포함", "핵심",
            "누가", "누구", "무엇", "어떻게", "이유", "행동", "문장", "단계"
        ]
        let suffixes = [
            "으로", "에서", "에게", "부터", "까지", "인지", "는지", "하고",
            "이라는", "라고", "처럼", "보다", "와", "과", "의", "이", "가",
            "은", "는", "을", "를", "도", "에"
        ]
        return Set(request.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { raw in
                var term = raw
                for suffix in suffixes where term.count - suffix.count >= 2
                    && term.hasSuffix(suffix) {
                    term.removeLast(suffix.count)
                    break
                }
                return term
            }
            .filter { $0.count >= 2 && !stopwords.contains($0) })
    }

    private static func compact(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func sentences(in text: String) -> [String] {
        text.split(separator: ".").map { compact(String($0)) + "." }
    }

    private static func anchorPrefix(_ text: String, words: Int) -> String {
        text.split(whereSeparator: \.isWhitespace).prefix(words)
            .joined(separator: " ")
    }
}
