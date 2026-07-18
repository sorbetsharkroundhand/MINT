import Foundation

/// 활성 문서의 메타·바이블 스냅샷 (PLAN §10) — MainActor(EntryStore)에서
/// 값 복사로 격리 경계를 넘긴다 (CompletionParameters와 같은 패턴).
public struct DocumentContext: Sendable, Equatable {
    public var title: String
    public var kind: EntryKind
    public var genre: String?
    public var characters: [CharacterCard]

    public init(
        title: String,
        kind: EntryKind,
        genre: String? = nil,
        characters: [CharacterCard] = []
    ) {
        self.title = title
        self.kind = kind
        self.genre = genre
        self.characters = characters
    }
}

/// 엔진에 넘기는 조립 완료 프롬프트 (PLAN §10) — 엔진은 조립에 관여하지 않는다.
public enum AssembledPrompt: Sendable, Equatable {
    /// 챗 템플릿 없이 그대로 이어쓸 텍스트 — KV 프리필 재사용 대상 (PLAN §12).
    case continuation(String)
    /// instruct 챗 — 시스템 + 사용자 메시지.
    case instruct(system: String, user: String)
}

/// AI 컨텍스트 리포트 (요구사항 §17) — **실제로 프롬프트에 실린 것만** 담는다.
/// 조립이 항목을 넣는 바로 그 자리에서 리포트에도 넣으므로, 인스펙터가 보는
/// 것과 모델이 받은 것이 구조적으로 같다 (별도 프리뷰 데이터 금지).
public struct ContextReport: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public enum Kind: String, Sendable, Equatable {
            case meta = "문서 정보"
            case card = "인물 카드"
            case state = "인물 상태"
            case knowledge = "인물 앎"
            case recentEvent = "최근 사건"
            case workSummary = "지난 줄거리"
            case chapterSummary = "장 요약"
            case sceneSummary = "앞선 장면"
            case currentScene = "지금 장면"
            case foreshadow = "미회수 복선"
            case dialogue = "대화 모드"
            case relation = "관계"
        }

        public var kind: Kind
        /// 프롬프트에 실린 줄 그대로.
        public var text: String
        /// 원문 보기 — 본문 검색 질의(인용·스니펫). nil이면 원문 앵커 없음.
        public var jumpQuery: String?
        /// 원문 보기 — UTF-16 위치 (스니펫은 UI가 본문에서 만든다).
        public var jumpUTF16: Int?

        public init(
            kind: Kind, text: String, jumpQuery: String? = nil, jumpUTF16: Int? = nil
        ) {
            self.kind = kind
            self.text = text
            self.jumpQuery = jumpQuery
            self.jumpUTF16 = jumpUTF16
        }
    }

    public var items: [Item]
    /// 조립 시각 — 인스펙터의 "언제 것인지" 표시.
    public var assembledAt: Date

    public init(items: [Item], assembledAt: Date = .now) {
        self.items = items
        self.assembledAt = assembledAt
    }

    public static let empty = ContextReport(items: [])
}

/// 예측 프롬프트 조립기 (PLAN §10–§11) — `[A 고정 헤더 | B 지식 | C 최근 원문]`.
///
/// 안정적인 것(A·B)이 앞, 매 키 입력마다 변하는 것(C)이 맨 뒤 — 이 순서라야
/// 직전 요청과의 공통 접두가 살아남아 KV 프리필 재사용이 가능하다 (PLAN §12).
/// 저널은 현행 그대로 C만(Fast 모드), 소설은 메타 헤더 + 인물 카드를 얹는다
/// (Smart/Story의 원형). 예측 시점엔 준비된 값의 조립만 한다 — LLM 호출·디스크
/// 접근 금지 (CLAUDE.md §2-2).
public enum ContextAssembler {

    /// A+B 문자 상한 — 소형 모델 프리필 예산 보호 (PLAN §11 초기값, 벤치로 조정).
    static let maxHeaderCharacters = 700
    /// 주입 카드 수 상한 — 예산 초과 시 삭감 1순위가 카드다 (PLAN §11).
    static let maxCards = 3
    /// 카드 한 장의 소개 글 상한 — 토큰당 품질 원칙 (CLAUDE.md §5-1).
    static let maxCardNoteCharacters = 140
    /// B(요약 지식) 문자 상한 — 초과 시 커서에서 먼 것부터 버린다 (PLAN §10 삭감).
    static let maxKnowledgeCharacters = 600

    /// C(최근 원문 창)에 A·B를 얹어 최종 프롬프트를 만든다.
    ///
    /// `knowledge`/`prefixStartUTF16`은 M6 — 인덱서가 발행한 스냅샷에서 C 창
    /// **밖**(이전) 씬의 요약만 골라 넣는다. 시점 차단(커서 이후 지식 미주입,
    /// CLAUDE.md §2-4)은 씬 위치 비교라 여기서 결정적으로 성립한다.
    public static func assemble(
        prefix: String,
        document: DocumentContext?,
        knowledge: KnowledgeSnapshot? = nil,
        prefixStartUTF16: Int = 0,
        style: PromptStyle
    ) -> AssembledPrompt {
        assembleWithReport(
            prefix: prefix, document: document, knowledge: knowledge,
            prefixStartUTF16: prefixStartUTF16, style: style
        ).prompt
    }

    /// 조립 + 컨텍스트 리포트 (요구사항 §16·§17) — 리포트는 프롬프트에 실제로
    /// 들어간 줄들의 기록이다. 인스펙터가 이걸 그대로 보여준다.
    public static func assembleWithReport(
        prefix: String,
        document: DocumentContext?,
        knowledge: KnowledgeSnapshot? = nil,
        prefixStartUTF16: Int = 0,
        style: PromptStyle
    ) -> (prompt: AssembledPrompt, report: ContextReport) {
        var items: [ContextReport.Item] = []
        var header = headerText(
            document: document, window: prefix,
            knowledge: knowledge, windowStart: prefixStartUTF16, report: &items)
        if document?.kind == .novel,
            let knowledge,
            case let block = knowledgeText(
                knowledge, before: prefixStartUTF16, report: &items),
            !block.isEmpty
        {
            header = header.isEmpty ? block : header + "\n" + block
        }
        // 지금 장면 (v4) — 커서가 속한 씬의 제목·유형. 커서가 씬을 넘을 때만
        // 변하므로 대화 블록과 같은 "맨 뒤" 자리다 (KV 프리픽스 보호).
        if document?.kind == .novel, let knowledge {
            let cursor = prefixStartUTF16 + (prefix as NSString).length
            let block = currentSceneText(knowledge, cursor: cursor, report: &items)
            if !block.isEmpty {
                header = header.isEmpty ? block : header + "\n" + block
            }
        }
        // 대화 모드 (PLAN §10, 모드와 직교) — 커서가 열린 따옴표 안이면 다음
        // 화자의 말투·예문·존대쌍을 승격한다. 헤더 맨 뒤에 붙는 이유: 이 블록은
        // 커서 위치에 따라 변하므로, 앞에 두면 A+B의 KV 프리픽스까지 식힌다.
        if document?.kind == .novel, let knowledge, let document,
            isInsideUtterance(prefix)
        {
            let cursor = prefixStartUTF16 + (prefix as NSString).length
            let block = dialogueText(
                knowledge, document: document, cursor: cursor, report: &items)
            if !block.isEmpty {
                header = header.isEmpty ? block : header + "\n" + block
            }
        }
        let report = ContextReport(items: items)
        switch style {
        case .continuation:
            // 헤더와 본문은 빈 줄 하나로만 구분 — 이어쓰기 흐름을 깨지 않는 최소 구조.
            return (.continuation(header.isEmpty ? prefix : header + "\n\n" + prefix), report)
        case .instruct:
            let system =
                header.isEmpty
                ? instructSystem
                : instructSystem + "\n\n[작품 정보]\n" + header
            return (.instruct(system: system, user: instructUser(prefix: prefix)), report)
        }
    }

    /// 커서가 속한 씬의 메타 한 줄 — "지금 장면: 아내의 외출 (회상)".
    /// 브랜치 안이면 유형이 곧 "지금 어느 서사 흐름에 있는가"다 (요구사항 §16).
    static func currentSceneText(
        _ knowledge: KnowledgeSnapshot, cursor: Int,
        report: inout [ContextReport.Item]
    ) -> String {
        guard let index = knowledge.outline.sceneIndex(at: cursor) else { return "" }
        let scene = knowledge.outline.scenes[index]
        guard let meta = knowledge.sceneMetaByHash[scene.contentHash] else { return "" }
        var pieces: [String] = []
        if let title = meta.title, !title.isEmpty { pieces.append(title) }
        if meta.type != .present { pieces.append("(\(meta.type.rawValue) 장면)") }
        if let location = meta.location, !location.isEmpty { pieces.append("· 장소: \(location)") }
        guard !pieces.isEmpty else { return "" }
        let line = "지금 장면: " + pieces.joined(separator: " ")
        report.append(
            ContextReport.Item(
                kind: .currentScene, text: line,
                jumpUTF16: scene.utf16Range.lowerBound))
        return line
    }

    /// B 블록 — C 창이 시작되기 **전에 끝난** 씬들의 요약 (PLAN §11).
    ///
    /// 구성: 작품 요약 → 이전 장 요약 → (커서와 같은 장의) 이전 씬 요약.
    /// 예산 초과 시 커서에서 먼 것부터 버린다 — 가까운 맥락이 더 예측에 기여한다.
    /// 창 시작이 512 격자에 스냅되므로(에디터·PLAN §12) 결과 문자열은 키 입력에
    /// 안정적 — KV 프리픽스가 식지 않는다.
    static func knowledgeText(_ knowledge: KnowledgeSnapshot, before windowStart: Int) -> String {
        var report: [ContextReport.Item] = []
        return knowledgeText(knowledge, before: windowStart, report: &report)
    }

    static func knowledgeText(
        _ knowledge: KnowledgeSnapshot, before windowStart: Int,
        report: inout [ContextReport.Item]
    ) -> String {
        let scenes = knowledge.outline.scenes
        // C 창 이전에 완전히 끝난 씬들 — 창과 겹치는 씬은 원문이 이미 C에 있다.
        let outside = scenes.filter { $0.utf16Range.upperBound <= windowStart }
        guard !outside.isEmpty else { return "" }

        // 커서(창)가 속한 장 — 같은 장의 씬은 요약으로, 이전 장은 장 요약으로.
        let cursorChapter = scenes.last(where: { $0.utf16Range.lowerBound <= windowStart })
            .map { Array($0.headingPath.prefix(2)) }

        var budget = maxKnowledgeCharacters
        var lines: [String] = []

        if let work = knowledge.workSummary, work.count + 12 <= budget {
            lines.append("지난 줄거리: \(work)")
            report.append(ContextReport.Item(kind: .workSummary, text: lines[0]))
            budget -= work.count + 12
        }

        // 미회수 복선 (v4, 요구사항 §16) — 사용자 **확정** 복선만, 최대 2줄.
        // 후보(candidate)는 넣지 않는다: AI 추측을 AI 입력으로 되먹이면 소음이
        // 자가 증폭한다 (품질 > 적극성). 씬 위치와 무관하게 안정적이라 KV에 안전.
        for thread in knowledge.foreshadows.filter({ $0.status == .confirmed }).prefix(2) {
            let line = "미회수 복선: \(thread.label) — \(thread.detail)"
            guard line.count <= budget else { break }
            lines.append(line)
            report.append(
                ContextReport.Item(
                    kind: .foreshadow, text: line, jumpQuery: thread.quotes.first))
            budget -= line.count
        }

        // 가까운 것부터 담고(예산 소진 시 먼 것이 자연히 빠진다) 문서 순서로 뒤집는다.
        var picked: [(line: String, item: ContextReport.Item)] = []
        var coveredChapters: Set<String> = []
        for scene in outside.reversed() {
            let chapter = Array(scene.headingPath.prefix(2))
            let chapterKey = chapter.joined(separator: " > ")
            let line: String
            let kind: ContextReport.Item.Kind
            if chapter == cursorChapter || knowledge.chapterSummariesByPath[chapterKey] == nil {
                // 같은 장(또는 장 요약이 아직 없는 장)은 씬 해상도로.
                guard let summary = knowledge.summariesByHash[scene.contentHash] else { continue }
                // 씬 제목(내용 기반, v4)이 있으면 헤딩보다 그쪽이 신호가 진하다.
                let label = knowledge.sceneMetaByHash[scene.contentHash]?.title
                    ?? scene.headingPath.last.flatMap { $0.isEmpty ? nil : $0 }
                line = label.map { "앞선 장면(\($0)): \(summary)" } ?? "앞선 장면: \(summary)"
                kind = .sceneSummary
            } else {
                // 이전 장은 장 해상도 한 줄로 — 장 하나당 한 번만.
                guard coveredChapters.insert(chapterKey).inserted else { continue }
                line = "\(chapterKey): \(knowledge.chapterSummariesByPath[chapterKey]!)"
                kind = .chapterSummary
            }
            guard line.count <= budget else { break }
            picked.append(
                (line,
                 ContextReport.Item(
                    kind: kind, text: line,
                    jumpUTF16: scene.utf16Range.lowerBound)))
            budget -= line.count
        }
        lines.append(contentsOf: picked.reversed().map(\.line))
        report.append(contentsOf: picked.reversed().map(\.item))
        return lines.joined(separator: "\n")
    }

    // MARK: - 대화 모드 (PLAN §10 — 화자 추정·말투 승격·발화 끝 정지)

    /// 커서(프리픽스 끝)가 열린 따옴표 안인가 — 대화 모드 게이트 (결정적).
    /// 마지막 문단만 본다: 대사는 문단을 넘지 않는 것이 한국어 소설의 관례고,
    /// 앞 문단의 짝 안 맞는 따옴표(오탈자)가 온 문서를 대화 모드로 만들면 안 된다.
    public static func isInsideUtterance(_ prefix: String) -> Bool {
        let paragraph = prefix.suffix(from: prefix.lastIndex(of: "\n").map {
            prefix.index(after: $0)
        } ?? prefix.startIndex)
        var asciiOpen = false
        var depth = 0
        for char in paragraph {
            switch char {
            case "“", "「", "『": depth += 1
            case "”", "」", "』": depth = max(0, depth - 1)
            case "\"": asciiOpen.toggle()
            default: break
            }
        }
        return depth > 0 || asciiOpen
    }

    /// 대화 블록 — 다음 화자 추정(§10 ①) + 그 인물의 말투 카드 승격(②).
    /// 추정이 안 서면 빈 문자열 — 틀린 화자 지목은 대사를 통째로 망친다
    /// (품질 > 적극성, CLAUDE.md §1-2).
    static func dialogueText(
        _ knowledge: KnowledgeSnapshot, document: DocumentContext, cursor: Int
    ) -> String {
        var report: [ContextReport.Item] = []
        return dialogueText(knowledge, document: document, cursor: cursor, report: &report)
    }

    static func dialogueText(
        _ knowledge: KnowledgeSnapshot, document: DocumentContext, cursor: Int,
        report: inout [ContextReport.Item]
    ) -> String {
        guard let (speakerID, addresseeID) = knowledge.expectedSpeaker(before: cursor)
        else { return "" }
        let name = { (id: UUID) in document.characters.first(where: { $0.id == id })?.name }
        guard let speaker = name(speakerID) else { return "" }

        var line = "지금 대화 중 — 다음 발화: \(speaker)"
        if let addressee = name(addresseeID),
            let usage = knowledge.honorific(from: speakerID, to: addresseeID, before: cursor)
        {
            line += " (\(addressee)에게 \(usage.rawValue))"
        } else if let profile = knowledge.speechProfile(of: speakerID, before: cursor),
            let base = profile.defaultPoliteness
        {
            line += " (\(base.rawValue) 기본)"
        }
        if let profile = knowledge.speechProfile(of: speakerID, before: cursor),
            !profile.examples.isEmpty
        {
            let examples = profile.examples.map { "\"\($0)\"" }.joined(separator: " ")
            line += " · \(speaker) 말투 예: \(examples)"
        }
        report.append(ContextReport.Item(kind: .dialogue, text: line))
        // 화자→청자 관계 (v4) — 대사 어조의 핵심 신호. 커서 이전 마지막 관계.
        if let addressee = name(addresseeID),
            let relation = knowledge.relation(from: speakerID, to: addresseeID, before: cursor)
        {
            let relationLine = "\(speaker)→\(addressee) 관계: \(relation.value)"
            report.append(
                ContextReport.Item(
                    kind: .relation, text: relationLine, jumpQuery: relation.quote))
            line += "\n" + relationLine
        }
        return line
    }

    /// 인물 한 명의 "최근" 줄 상한 — 사건 요약(≤80자)을 그대로 쓴다.
    static let maxRecentEventCharacters = 80
    /// 인물 한 명의 "상태@커서" 조각 상한 — 필드 5개 × 값 40자를 다 붙이면
    /// 카드 하나가 헤더 예산(700자)을 잠식한다 (토큰당 품질, CLAUDE.md §5-1).
    static let maxStateCharacters = 100

    /// A 고정 헤더 + B 인물 카드. 소설 전용 — 저널은 빈 문자열(Fast = C만).
    ///
    /// `knowledge`/`windowStart`(M6-5): 카드마다 **커서 이전 마지막 등장 사건**을
    /// 한 줄 붙인다 (PLAN §8 `lastAppearance`). 사건을 B 블록에 따로 나열하지
    /// 않는 이유: 같은 씬을 씬 요약이 이미 말하고 있어 지식이 겹치고 예산만
    /// 태운다. 사건이 요약 대비 더 가진 것은 **참여자 링크**뿐이므로, 그 값은
    /// "인물 → 그 인물의 사건"이라는 질의에서만 나온다 (PLAN §11 엔티티 앵커
    /// 검색). 이 줄이 M6 완료 기준의 "1200자 창 밖 인물을 쓰는 제안"을 겨눈다.
    /// 인물 한 명의 "앎" 조각 상한 — 최근 앎 2개까지 (토큰당 품질).
    static let maxKnowledgeFactsPerCard = 2

    static func headerText(
        document: DocumentContext?,
        window: String,
        knowledge: KnowledgeSnapshot? = nil,
        windowStart: Int = 0
    ) -> String {
        var report: [ContextReport.Item] = []
        return headerText(
            document: document, window: window, knowledge: knowledge,
            windowStart: windowStart, report: &report)
    }

    static func headerText(
        document: DocumentContext?,
        window: String,
        knowledge: KnowledgeSnapshot? = nil,
        windowStart: Int = 0,
        report: inout [ContextReport.Item]
    ) -> String {
        guard let document, document.kind == .novel else { return "" }
        // 줄 + 그 줄이 만든 리포트 항목들 — 예산에서 줄이 떨어지면 항목도
        // 함께 떨어진다 (리포트 = 실제 주입의 거울, 요구사항 §17).
        var lines: [(text: String, items: [ContextReport.Item])] = []

        var meta: [String] = []
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { meta.append("제목: \(title)") }
        if let genre = document.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
            !genre.isEmpty
        {
            meta.append("장르: \(genre)")
        }
        // "소설"이라는 신호 자체가 몇 토큰으로 톤을 바꾼다
        // (docs/autocomplete-context.md 개선 1).
        meta.append("종류: 소설")
        let metaLine = meta.joined(separator: " · ")
        lines.append((metaLine, [ContextReport.Item(kind: .meta, text: metaLine)]))

        for card in selectCards(from: document.characters, window: window) {
            let aliases = aliasList(card)
            let name =
                aliases.isEmpty
                ? card.name : "\(card.name)(\(aliases.joined(separator: "·")))"
            let note = String(
                card.note
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(maxCardNoteCharacters))
            var line = note.isEmpty ? "등장인물 \(name)" : "등장인물 \(name): \(note)"
            var cardItems: [ContextReport.Item] = [
                ContextReport.Item(kind: .card, text: line)
            ]
            // 상태@커서 (PLAN §7 카드 스키마, §8 `state_at`) — 창 시작 시점까지의
            // 델타를 접은 결과. 일관성 > 유창성(CLAUDE.md §3)의 실탄이다:
            // "생사=사망"이 든 카드가 죽은 인물의 등장을 프롬프트 수준에서 막는다.
            if let knowledge {
                let state = knowledge.stateAt(of: card.id, before: windowStart)
                if !state.isEmpty {
                    // CaseIterable 순서로 고정 렌더링 — 같은 상태가 패스마다 다른
                    // 순서로 찍히면 KV 프리픽스가 식는다 (PLAN §12).
                    let rendered = StateDelta.Field.allCases
                        .compactMap { field in state[field].map { "\(field.rawValue)=\($0)" } }
                        .joined(separator: " · ")
                    let piece = "상태@커서: \(rendered.prefix(maxStateCharacters))"
                    line += " · " + piece
                    cardItems.append(
                        ContextReport.Item(kind: .state, text: "\(card.name) \(piece)"))
                }
                // 앎@커서 (v4, 요구사항 §11·§16) — 그 시점까지 이 인물이 가진
                // 앎의 최근 조각. "아직 모르는 비밀을 대사로 말하는" 제안을
                // 프롬프트 수준에서 막는 재료다.
                let known = knowledge.knowledge(of: card.id, before: windowStart)
                if !known.isEmpty {
                    let rendered = known.suffix(maxKnowledgeFactsPerCard)
                        .map { "\($0.fact)(\($0.stance.rawValue))" }
                        .joined(separator: "; ")
                    let piece = "앎: \(rendered)"
                    line += " · " + piece
                    cardItems.append(
                        ContextReport.Item(
                            kind: .knowledge, text: "\(card.name) \(piece)",
                            jumpQuery: known.last?.quote))
                }
            }
            // 커서가 이미 보고 있는 사건은 붙이지 않는다 — C 창에 원문이 그대로
            // 있는데 요약을 겹쳐 넣으면 토큰만 쓴다 (`lastAppearance`가 창 밖
            // 사건만 돌려주므로 이 조건은 질의에서 이미 성립).
            if let recent = knowledge?.lastAppearance(of: card.id, before: windowStart) {
                let piece = "최근: \(recent.summary.prefix(maxRecentEventCharacters))"
                line += " · " + piece
                cardItems.append(
                    ContextReport.Item(
                        kind: .recentEvent, text: "\(card.name) \(piece)",
                        jumpQuery: recent.quote))
            }
            lines.append((line, cardItems))
        }
        // 줄 단위 예산 — 통짜 prefix는 마지막 줄을 중간에서 잘라 리포트와
        // 프롬프트가 어긋난다. 예산을 넘는 줄부터 통째로 버린다.
        var total = 0
        var kept: [String] = []
        for (text, items) in lines {
            guard total + text.count + 1 <= maxHeaderCharacters else { break }
            kept.append(text)
            total += text.count + 1
            report.append(contentsOf: items)
        }
        return kept.joined(separator: "\n")
    }

    /// 카드 선택 — 최근 창에 이름·별칭이 언급된 카드 우선, 남는 자리는 목록
    /// 앞(주인공일 확률이 높다)에서 채운다. 결과는 항상 문서의 카드 순서 —
    /// 언급 최신순 정렬은 창이 밀릴 때마다 순서를 흔들어 KV 프리픽스를 식힌다.
    /// 세대 단위 랭킹은 M6 (PLAN §11).
    static func selectCards(from cards: [CharacterCard], window: String) -> [CharacterCard] {
        let valid = cards.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard valid.count > maxCards else { return valid }

        var picked = valid.filter { card in
            window.contains(card.name)
                || aliasList(card).contains(where: { window.contains($0) })
        }
        if picked.count < maxCards {
            for card in valid where !picked.contains(where: { $0.id == card.id }) {
                picked.append(card)
                if picked.count >= maxCards { break }
            }
        }
        let chosen = Set(picked.prefix(maxCards).map(\.id))
        return valid.filter { chosen.contains($0.id) }
    }

    /// 쉼표 구분 별칭 원문 → 빈 항목을 뺀 배열.
    private static func aliasList(_ card: CharacterCard) -> [String] {
        card.aliases.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - instruct 프롬프트 (엔진에서 이관 — 프롬프트의 단일 소유자는 조립기)

    static let instructSystem = """
        너는 글쓰기 자동완성 엔진이다. 사용자가 쓰던 글의 마지막 부분을 받아, \
        그 마지막 글자 바로 뒤에 자연스럽게 이어질 짧은 다음 구절(최대 한 문장)을 \
        출력한다. 설명·인사·따옴표·머리말 없이 이어질 본문만 출력한다.
        """

    static func instructUser(prefix: String) -> String {
        """
        다음 글에 바로 이어질 내용을 짧게 이어써라.

        \(prefix)
        """
    }
}
