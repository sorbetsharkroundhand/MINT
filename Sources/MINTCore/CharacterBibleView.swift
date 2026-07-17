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
            .frame(maxHeight: 320)

            Button {
                addCard()
            } label: {
                Label("인물 추가", systemImage: "plus")
                    .font(MintFonts.uiFont(12, .medium))
            }
        }
        .padding(14)
        .frame(width: 400)
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
                            Text("'\(candidate.name)' — 인물로 등록할까요?")
                                .font(MintFonts.uiFont(11.5, .medium))
                                .foregroundStyle(theme.inkC)
                            Text("언급 \(candidate.mentions)회 · 씬 \(candidate.sceneCount)곳")
                                .font(MintFonts.uiFont(10))
                                .foregroundStyle(theme.ink3C)
                        }
                        Spacer()
                        Button("등록") { indexer.approveCandidate(candidate) }
                            .font(MintFonts.uiFont(11, .semibold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(theme.novelC)
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

/// 인물 카드 한 장 — 이름·별칭·소개(편집 가능) + 자동 이해(열람 전용) + 잠금.
private struct CharacterCardRow: View {
    @Binding var card: CharacterCard
    let theme: MintTheme
    /// 백그라운드가 이해한 것 — 읽기 전용 표시 (빈 배열이면 숨김).
    let understanding: [String]
    let onDelete: () -> Void
    @State private var deleteHovered = false

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
}
