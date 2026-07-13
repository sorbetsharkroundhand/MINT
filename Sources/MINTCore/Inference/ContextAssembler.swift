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

    /// C(최근 원문 창)에 A·B를 얹어 최종 프롬프트를 만든다.
    public static func assemble(
        prefix: String,
        document: DocumentContext?,
        style: PromptStyle
    ) -> AssembledPrompt {
        let header = headerText(document: document, window: prefix)
        switch style {
        case .continuation:
            // 헤더와 본문은 빈 줄 하나로만 구분 — 이어쓰기 흐름을 깨지 않는 최소 구조.
            return .continuation(header.isEmpty ? prefix : header + "\n\n" + prefix)
        case .instruct:
            let system =
                header.isEmpty
                ? instructSystem
                : instructSystem + "\n\n[작품 정보]\n" + header
            return .instruct(system: system, user: instructUser(prefix: prefix))
        }
    }

    /// A 고정 헤더 + B 인물 카드. 소설 전용 — 저널은 빈 문자열(Fast = C만).
    static func headerText(document: DocumentContext?, window: String) -> String {
        guard let document, document.kind == .novel else { return "" }
        var lines: [String] = []

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
        lines.append(meta.joined(separator: " · "))

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
            lines.append(note.isEmpty ? "등장인물 \(name)" : "등장인물 \(name): \(note)")
        }
        return String(lines.joined(separator: "\n").prefix(maxHeaderCharacters))
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
