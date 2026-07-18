import SwiftUI

/// AI 컨텍스트 인스펙터 (v4, 요구사항 §17) — 최근 예측이 **실제로** 참고한
/// 컨텍스트를 항목별로 보여준다.
///
/// 데이터 소스는 `CompletionController.lastContextReport` — 조립기가 프롬프트를
/// 만들며 그 자리에서 남긴 기록이라, 여기 보이는 것과 모델이 받은 것이 항상
/// 같다 (별도 프리뷰 데이터 금지). 항목에 원문 앵커(인용·위치)가 있으면
/// 클릭으로 본문을 확인할 수 있다 — "AI가 왜 이렇게 썼지?"의 답.
struct ContextInspectorView: View {
    @ObservedObject var completion: CompletionController
    @ObservedObject var store: EntryStore
    let theme: MintTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.novelC)
                Text("AI 컨텍스트")
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                Spacer()
                if let report = completion.lastContextReport {
                    Text("항목 \(report.items.count)")
                        .font(MintFonts.monoUI(10))
                        .foregroundStyle(theme.ink3C)
                }
            }
            Divider()
            if let report = completion.lastContextReport, !report.items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("최근 예측이 참고한 정보예요. 최근 원문(C 창)은 항상 함께 실려요.")
                            .font(MintFonts.uiFont(10))
                            .foregroundStyle(theme.ink3C)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                            itemRow(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text(
                    store.activeEntry?.resolvedKind == .novel
                        ? "아직 예측이 없어요. 소설 본문에서 타이핑을 멈추면 예측이 만들어지고, 그때 참고한 컨텍스트가 여기 보여요."
                        : "소설 종류의 문서에서 예측이 만들어질 때 참고 컨텍스트가 여기 보여요."
                )
                .font(MintFonts.uiFont(11))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }

    @ViewBuilder private func itemRow(_ item: ContextReport.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(item.kind.rawValue)
                    .font(MintFonts.uiFont(9, .semibold))
                    .foregroundStyle(theme.novelC)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(theme.novelBgC))
                Spacer()
                if hasJump(item) {
                    Button {
                        jump(item)
                    } label: {
                        Label("원문", systemImage: "arrow.right.circle")
                            .font(MintFonts.uiFont(9.5))
                            .foregroundStyle(theme.blueC)
                    }
                    .buttonStyle(.plain)
                    .help("이 정보의 근거 원문으로 이동")
                }
            }
            Text(item.text)
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink2C)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.chipC))
    }

    private func hasJump(_ item: ContextReport.Item) -> Bool {
        item.jumpQuery != nil || item.jumpUTF16 != nil
    }

    /// 원문 보기 — 인용이 있으면 인용 검색, 위치만 있으면 그 자리 스니펫 검색
    /// (타임라인과 같은 requestSearchJump 통로 — 좌표 불일치를 구조적으로 회피).
    private func jump(_ item: ContextReport.Item) {
        if let quote = item.jumpQuery {
            store.requestSearchJump(store.activeID, query: quote)
        } else if let offset = item.jumpUTF16,
            let body = store.activeEntry?.body,
            let snippet = KnowledgeTimelineView.jumpSnippet(in: body, atUTF16: offset)
        {
            store.requestSearchJump(store.activeID, query: snippet)
        }
    }
}
