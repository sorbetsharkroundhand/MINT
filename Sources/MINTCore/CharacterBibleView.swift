import SwiftUI

/// 스토리 바이블 v0 — 장르·인물 카드 편집 팝오버 (PLAN §7, M5: 사용자 수동 카드만).
///
/// 툴바의 "소설" 배지에서 연다. 여기 적은 내용이 소설 예측 프롬프트의
/// A 헤더에 그대로 실린다 — 카드가 짧을수록 토큰당 품질이 좋다 (PLAN §11).
/// 자동 감지·등록 제안은 M6 (감지는 자동, 등록은 사용자 확인 — CLAUDE.md §3).
struct CharacterBibleView: View {
    @ObservedObject var store: EntryStore
    let theme: MintTheme

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
            .frame(maxHeight: 300)

            Button {
                addCard()
            } label: {
                Label("인물 추가", systemImage: "plus")
                    .font(MintFonts.uiFont(12, .medium))
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private var cards: [CharacterCard] {
        store.activeEntry?.characters ?? []
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
    private func binding(for card: CharacterCard) -> Binding<CharacterCard> {
        Binding(
            get: {
                store.activeEntry?.characters?.first(where: { $0.id == card.id }) ?? card
            },
            set: { updated in
                if let id = store.activeEntry?.id { store.upsertCharacter(updated, in: id) }
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

/// 인물 카드 한 장 — 이름·별칭 한 줄 + 소개(성격·말투) 한 칸.
private struct CharacterCardRow: View {
    @Binding var card: CharacterCard
    let theme: MintTheme
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
