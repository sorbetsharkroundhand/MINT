import SwiftUI

/// 스토리 바이블 — 장르·인물 카드 편집 + 자동 이해 열람 팝오버 (PLAN §7, M6-8).
///
/// 툴바의 "소설" 배지에서 연다. 여기 적은 내용이 소설 예측 프롬프트의
/// A 헤더에 그대로 실린다 — 카드가 짧을수록 토큰당 품질이 좋다 (PLAN §11).
///
/// M6 마감 형태 (CLAUDE.md §1-5 "기억은 사용자의 것"):
/// - **열람**: 카드마다 백그라운드가 이해한 것(상태·최근 사건·말투)을 보여준다.
/// - **수정**: 카드 필드는 언제나 편집 가능 — 사용자 수정이 자동 추출을 이긴다.
/// - **locked**: 소개를 직접 고치면 자동 잠금 — 프로파일링이 덮지 못한다.
/// - **미확인 검토**: 감지된 후보를 전부 나열 — 등록은 사용자 확인 (CLAUDE.md §3).
struct CharacterBibleView: View {
    @ObservedObject var store: EntryStore
    let theme: MintTheme
    /// 인물 감지 깔때기 + 자동 이해 열람 (M6) — nil이면 수동 카드만 (프리뷰 등).
    var indexer: BackgroundIndexer?
    /// 사이드바 섹션에 임베드됐는가 — 고정 폭·높이 상한을 풀고 공간을 채운다.
    var embedded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.novelC)
                Text("스토리 바이블")
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                Spacer()
                // 수동 이해 트리거 (M6-8) — 자동(유휴)만이 아니라 사용자가
                // 원할 때도 이해를 만든다. 자동완성이 꺼져 있어도 동작한다.
                if let indexer {
                    ManualIndexButton(indexer: indexer, theme: theme)
                }
            }

            // 인물 후보 검토 — 비모달, 감지된 후보 전부 (PLAN §7 깔때기 2단).
            if let indexer {
                CandidateReviewList(indexer: indexer, store: store, theme: theme)
            }

            TextField("장르 (예: 판타지 · 로맨스 · 추리)", text: genreBinding)
                .textFieldStyle(.roundedBorder)
                .font(MintFonts.uiFont(12))

            Text("제목·장르·인물 카드가 예측에 함께 실려요. 최근 본문에 이름이 등장하는 인물이 우선돼요 (최대 3명).")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink2C)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        CharacterCardRow(
                            card: binding(for: card),
                            theme: theme,
                            understanding: understanding(of: card),
                            chronicle: chronicle(of: card),
                            knowledge: knowledgeLines(of: card),
                            relations: relationLines(of: card),
                            conversations: conversationLines(of: card),
                            onJump: { query in
                                // 재앵커 사다리 (요구사항 §28) — 인용이 수정됐으면
                                // 어절 지문으로 되찾는다.
                                let resolved = store.activeEntry.flatMap {
                                    SourceAnchor.resilientQuery(for: query, in: $0.body)
                                } ?? query
                                store.requestSearchJump(store.activeID, query: resolved)
                            },
                            onDelete: { remove(card) }
                        )
                    }
                    if cards.isEmpty {
                        Text("아직 인물이 없어요 — 주요 인물을 등록하면 제안이 이름과 말투를 지켜요.")
                            .font(MintFonts.uiFont(11))
                            .foregroundStyle(theme.ink3C)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: embedded ? .infinity : 320)

            Button {
                addCard()
            } label: {
                Label("인물 추가", systemImage: "plus")
                    .font(MintFonts.uiFont(12, .medium))
            }
        }
        .padding(14)
        .frame(width: embedded ? nil : 400)
    }

    private var cards: [CharacterCard] {
        store.activeEntry?.characters ?? []
    }

    /// 카드 하나에 대한 자동 이해 요약 (열람 전용, CLAUDE.md §1-5) — 프롬프트
    /// 카드 줄과 같은 질의(`stateAt`·`lastAppearance`·`speechProfile`)를 문서 끝
    /// 기준으로 접는다. 사용자가 보는 것과 예측이 아는 것이 같은 소스다.
    private func understanding(of card: CharacterCard) -> [String] {
        guard let snapshot = indexer?.snapshot,
            snapshot.entryID == store.activeID
        else { return [] }
        var lines: [String] = []
        let state = snapshot.stateAt(of: card.id, before: .max)
        if !state.isEmpty {
            let rendered = StateDelta.Field.allCases
                .compactMap { field in state[field].map { "\(field.rawValue) \($0)" } }
                .joined(separator: " · ")
            lines.append("상태: \(rendered)")
        }
        if let recent = snapshot.lastAppearance(of: card.id, before: .max) {
            lines.append("최근: \(recent.summary)")
        }
        if let profile = snapshot.speechProfile(of: card.id, before: .max) {
            var speech: [String] = []
            if let base = profile.defaultPoliteness { speech.append("\(base.rawValue) 기본") }
            if let example = profile.examples.last { speech.append("\"\(example)\"") }
            if !speech.isEmpty { lines.append("말투: \(speech.joined(separator: " · "))") }
        }
        return lines
    }

    /// 인물 연대기 (M7, PLAN §14) — 그 인물이 겪은 사건과 상태 변화를 담화
    /// 순서로 편다. StateDelta가 append-only인 덕에 이 UI가 "공짜로" 나온다
    /// (PLAN §7 — 상태를 덮어썼다면 역사가 없어 연대기도 없다).
    private func chronicle(of card: CharacterCard) -> [String] {
        guard let snapshot = indexer?.snapshot,
            snapshot.entryID == store.activeID,
            let offsets = snapshot.eventIndexByCharacter[card.id]
        else { return [] }
        return offsets.map { offset in
            let event = snapshot.events[offset]
            var line = event.summary
            let changes = event.deltas
                .filter { $0.characterID == card.id }
                .map { "\($0.field.rawValue) \($0.value)" }
            if !changes.isEmpty {
                line += " → \(changes.joined(separator: " · "))"
            }
            return line
        }
    }

    /// 활성 문서의 스냅샷 (문서 일치 확인 포함).
    private var snapshot: KnowledgeSnapshot? {
        guard let snapshot = indexer?.snapshot, snapshot.entryID == store.activeID
        else { return nil }
        return snapshot
    }

    /// 인물의 앎 (v4, 요구사항 §11) — 문서 끝 기준으로 접은 현재 앎.
    /// (text, 점프 질의) — 질의는 근거 인용, 없으면 nil (추론).
    private func knowledgeLines(of card: CharacterCard) -> [(text: String, jump: String?)] {
        guard let snapshot else { return [] }
        return snapshot.knowledge(of: card.id, before: .max).map { delta in
            ("\(delta.stance.rawValue): \(delta.fact)", delta.quote)
        }
    }

    /// 인물이 얽힌 관계들의 변화 이력 (v4, 요구사항 §12) — 방향 쌍별로
    /// "남편→아내: 사랑 → 의심 → 적대" 한 줄.
    private func relationLines(of card: CharacterCard) -> [(text: String, jump: String?)] {
        guard let snapshot else { return [] }
        let names = Dictionary(
            uniqueKeysWithValues: (store.activeEntry?.characters ?? []).map { ($0.id, $0.name) })
        // 방향 쌍별 그룹 (담화 순서 유지).
        var order: [String] = []
        var grouped: [String: [RelationDelta]] = [:]
        for delta in snapshot.relationDeltas
        where delta.fromID == card.id || delta.toID == card.id {
            let key = "\(delta.fromID.uuidString)>\(delta.toID.uuidString)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(delta)
        }
        return order.compactMap { key in
            guard let deltas = grouped[key], let first = deltas.first,
                let from = names[first.fromID], let to = names[first.toID]
            else { return nil }
            let evolution = deltas.map(\.value).joined(separator: " → ")
            return ("\(from)→\(to): \(evolution)", deltas.last?.quote)
        }
    }

    /// 인물의 대화 인덱스 (v4, 요구사항 §13) — 원문 복제 없이 위치 참조.
    /// 점프 질의 = 첫 대사 (본문 부분 문자열이라 그대로 검색된다).
    private func conversationLines(of card: CharacterCard) -> [(text: String, jump: String?)] {
        guard let snapshot else { return [] }
        let names = Dictionary(
            uniqueKeysWithValues: (store.activeEntry?.characters ?? []).map { ($0.id, $0.name) })
        return snapshot.conversations(involving: card.id).map { conversation in
            let others = conversation.participants
                .filter { $0 != card.id }
                .compactMap { names[$0] }
            let with = others.isEmpty ? "" : " ↔ \(others.joined(separator: "·"))"
            let scene = conversation.sceneHash
                .flatMap { snapshot.sceneMetaByHash[$0]?.title }
                .map { "[\($0)] " } ?? ""
            // 기록된 대화 표식 + 백그라운드 보완 주제 (요구사항 §21).
            let recorded = conversation.recordedID != nil ? "📌 " : ""
            let topic = conversation.topic.map { " · \($0)" } ?? ""
            let count = conversation.utteranceCount > 0 ? " · 발화 \(conversation.utteranceCount)" : ""
            return (
                "\(recorded)\(scene)\(card.name)\(with)\(count)\(topic) — “\(conversation.firstLine)”",
                conversation.firstLine
            )
        }
    }

    private var genreBinding: Binding<String> {
        Binding(
            get: { store.activeEntry?.genre ?? "" },
            set: { value in
                if let id = store.activeEntry?.id { store.setGenre(value, for: id) }
            }
        )
    }

    /// 카드 필드 편집 → 스토어 upsert (디바운스 저장). get은 항상 스토어의
    /// 최신 값 — 팝오버가 열린 채 다른 경로로 바뀌어도 어긋나지 않는다.
    /// **소개를 직접 고치면 잠근다** — 자동 프로파일링이 덮지 못한다 (PLAN §6.2).
    private func binding(for card: CharacterCard) -> Binding<CharacterCard> {
        Binding(
            get: {
                store.activeEntry?.characters?.first(where: { $0.id == card.id }) ?? card
            },
            set: { updated in
                guard let id = store.activeEntry?.id else { return }
                var updated = updated
                let current = store.activeEntry?.characters?.first(where: { $0.id == card.id })
                if let current, updated.note != current.note {
                    updated.locked = true
                }
                // 사용자가 손을 대면 자동 등록 표식은 사라진다 — 이제 사용자의
                // 카드다 (요구사항 §16).
                if let current, updated != current { updated.autoRegistered = nil }
                store.upsertCharacter(updated, in: id)
            }
        )
    }

    private func addCard() {
        guard let id = store.activeEntry?.id else { return }
        store.upsertCharacter(CharacterCard(), in: id)
    }

    private func remove(_ card: CharacterCard) {
        guard let id = store.activeEntry?.id else { return }
        store.removeCharacter(card.id, from: id)
    }
}

/// 감지된 인물 후보 검토 목록 (M6-8, PLAN §7) — 후보 전부를 나열한다.
/// "등록"은 카드 생성 + 백그라운드 프로파일링, "무시"는 거부 목록행(재질문 금지).
/// 답하기 전엔 아무것도 바꾸지 않는다 — 자동 등록 절대 금지 (CLAUDE.md §3).
private struct CandidateReviewList: View {
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var store: EntryStore
    let theme: MintTheme

    /// 후보 근거 요약 한 줄 — 신뢰도·별칭 변형까지 (요구사항 §16·§17).
    fileprivate func candidateDetail(_ candidate: CharacterDetector.Candidate) -> String {
        var pieces = ["언급 \(candidate.mentions)회 · 씬 \(candidate.sceneCount)곳"]
        pieces.append("신뢰 \(candidate.confidence.rawValue)")
        if !candidate.aliasForms.isEmpty {
            pieces.append("표기: \(candidate.aliasForms.joined(separator: "·"))")
        }
        return pieces.joined(separator: " · ")
    }

    var body: some View {
        if indexer.candidatesEntryID == store.activeID,
            !indexer.characterCandidates.isEmpty
        {
            VStack(spacing: 4) {
                ForEach(indexer.characterCandidates, id: \.name) { candidate in
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.novelC)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(
                                candidate.aliasOfKnown.map {
                                    "'\(candidate.name)' — '\($0)'의 별칭일까요?"
                                } ?? "'\(candidate.name)' — 인물로 등록할까요?"
                            )
                            .font(MintFonts.uiFont(11.5, .medium))
                            .foregroundStyle(theme.inkC)
                            Text(candidateDetail(candidate))
                                .font(MintFonts.uiFont(10))
                                .foregroundStyle(theme.ink3C)
                        }
                        Spacer()
                        // 별칭 후보 (요구사항 §17) — 병합은 사용자 결정.
                        if let owner = candidate.aliasOfKnown {
                            Button("별칭으로") {
                                indexer.approveCandidateAsAlias(candidate, of: owner)
                            }
                            .font(MintFonts.uiFont(11, .semibold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(theme.novelC)
                        }
                        if candidate.aliasOfKnown == nil {
                            Button("등록") { indexer.approveCandidate(candidate) }
                                .font(MintFonts.uiFont(11, .semibold))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(theme.novelC)
                        } else {
                            Button("새 인물") { indexer.approveCandidate(candidate) }
                                .font(MintFonts.uiFont(11))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Button("무시") { indexer.rejectCandidate(candidate) }
                            .font(MintFonts.uiFont(11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.novelBgC)
                    )
                }
            }
        }
    }
}

/// 인물 카드 한 장 — 이름·별칭·소개(편집 가능) + 자동 이해(열람 전용) + 잠금 +
/// 연대기(M7 — 사건·상태 변화 담화 순서 열람).
private struct CharacterCardRow: View {
    @Binding var card: CharacterCard
    let theme: MintTheme
    /// 백그라운드가 이해한 것 — 읽기 전용 표시 (빈 배열이면 숨김).
    let understanding: [String]
    /// 인물 연대기 — 사건 요약(+델타) 담화 순서 (빈 배열이면 숨김).
    let chronicle: [String]
    /// 앎 — 이 인물이 아는/의심하는/오해하는/숨기는 것 (v4, 요구사항 §11).
    let knowledge: [(text: String, jump: String?)]
    /// 관계 변화 이력 (v4, 요구사항 §12).
    let relations: [(text: String, jump: String?)]
    /// 대화 인덱스 (v4, 요구사항 §13) — 클릭 → 원문 대화로 이동.
    let conversations: [(text: String, jump: String?)]
    /// 원문 점프 (requestSearchJump 통로).
    var onJump: ((String) -> Void)?
    let onDelete: () -> Void
    @State private var deleteHovered = false
    @State private var chronicleExpanded = false
    @State private var knowledgeExpanded = false
    @State private var relationsExpanded = false
    @State private var conversationsExpanded = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("이름", text: $card.name)
                    .textFieldStyle(.roundedBorder)
                    .font(MintFonts.uiFont(12))
                    .frame(width: 110)
                TextField("별칭·호칭 (쉼표 구분)", text: $card.aliases)
                    .textFieldStyle(.roundedBorder)
                    .font(MintFonts.uiFont(12))
                // 자동 등록 표식 (요구사항 §16) — HIGH 신뢰 감지로 만들어진 카드.
                // 편집하면 사라진다. 삭제는 오른쪽 휴지통 한 번이다.
                if card.autoRegistered == true {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.novelC)
                        .help("자동 등록된 인물 — 이름·별칭을 고치거나 삭제할 수 있어요")
                }
                // 잠금 토글 — 잠기면 자동 프로파일링이 소개를 채우지 않는다.
                Button {
                    card.locked = card.locked == true ? nil : true
                } label: {
                    Image(systemName: card.locked == true ? "lock.fill" : "lock.open")
                        .font(.system(size: 11))
                        .foregroundStyle(card.locked == true ? theme.novelC : theme.ink3C)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    card.locked == true
                        ? "잠김 — 자동 이해가 이 카드를 고치지 않아요"
                        : "열림 — 소개가 비어 있으면 자동 이해가 채울 수 있어요")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(deleteHovered ? theme.novelC : theme.ink3C)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { deleteHovered = $0 }
                .help("인물 삭제")
            }
            TextField("성격·말투·관계 — 짧게 (예: 신중하고 직설적. 반말, \"…거든\" 버릇)",
                text: $card.note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(MintFonts.uiFont(12))
                .lineLimit(2...4)
            // 자동 이해 — 예측 카드 줄과 같은 질의 결과의 열람 (CLAUDE.md §1-5).
            // 편집은 원문·카드에서 한다 — 파생 지식을 직접 고치게 하면 원문과
            // 어긋난 채 다음 패스가 도로 덮는다 (원문이 유일한 진실, §2-1).
            if !understanding.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(understanding, id: \.self) { line in
                        Text(line)
                            .font(MintFonts.uiFont(10.5))
                            .foregroundStyle(theme.ink2C)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
            // 연대기 (M7) — 접힌 채 시작, 사건 수만 보인다 (조용한 UI).
            if !chronicle.isEmpty {
                Button {
                    chronicleExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: chronicleExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text("연대기 · 사건 \(chronicle.count)")
                            .font(MintFonts.uiFont(10.5, .medium))
                    }
                    .foregroundStyle(theme.ink3C)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if chronicleExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(chronicle.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(index + 1)")
                                    .font(MintFonts.monoUI(9))
                                    .foregroundStyle(theme.ink3C)
                                Text(line)
                                    .font(MintFonts.uiFont(10.5))
                                    .foregroundStyle(theme.ink2C)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                }
            }
            // 앎 (v4) — 이 인물이 아는 것만이 예측 대사에 실린다 (§11).
            jumpSection(
                title: "앎", count: knowledge.count,
                expanded: $knowledgeExpanded, entries: knowledge)
            // 관계 변화 (v4, §12) — 방향 쌍별 변화 이력.
            jumpSection(
                title: "관계", count: relations.count,
                expanded: $relationsExpanded, entries: relations)
            // 대화 인덱스 (v4, §13) — 클릭하면 원문 대화로 이동.
            jumpSection(
                title: "대화", count: conversations.count,
                expanded: $conversationsExpanded, entries: conversations)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.chipC)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.chipBorderC, lineWidth: 1)
        )
    }

    /// 접힘 섹션 공용 — 연대기와 같은 조용한 UI 문법 (제목 · 개수, 접힌 채 시작).
    /// 항목에 점프 질의가 있으면 클릭 → 원문 이동.
    @ViewBuilder private func jumpSection(
        title: String, count: Int,
        expanded: Binding<Bool>, entries: [(text: String, jump: String?)]
    ) -> some View {
        if count > 0 {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(
                        systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right"
                    )
                    .font(.system(size: 8, weight: .semibold))
                    Text("\(title) · \(count)")
                        .font(MintFonts.uiFont(10.5, .medium))
                }
                .foregroundStyle(theme.ink3C)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        if let jump = entry.jump, let onJump {
                            Button {
                                onJump(jump)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Image(systemName: "arrow.right.circle")
                                        .font(.system(size: 8))
                                        .foregroundStyle(theme.blueC)
                                    Text(entry.text)
                                        .font(MintFonts.uiFont(10.5))
                                        .foregroundStyle(theme.ink2C)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("원문으로 이동")
                        } else {
                            Text(entry.text)
                                .font(MintFonts.uiFont(10.5))
                                .foregroundStyle(theme.ink2C)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            }
        }
    }
}
