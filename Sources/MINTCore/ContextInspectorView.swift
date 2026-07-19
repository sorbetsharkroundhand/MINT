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
                        excludedList
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
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.novelC)
                        .help("고정됨 — 관련성이 낮아져도 컨텍스트에 유지돼요")
                }
                Spacer()
                // Pin/Exclude (요구사항 §31) — 오버라이드(entries.json)로 저장돼
                // 실제 조립 파이프라인이 그대로 읽는다. UI 전용 프리뷰가 아니다.
                if !item.stableKey.isEmpty {
                    Button {
                        togglePin(item)
                    } label: {
                        Image(systemName: item.pinned ? "pin.slash" : "pin")
                            .font(.system(size: 9))
                            .foregroundStyle(item.pinned ? theme.novelC : theme.ink3C)
                    }
                    .buttonStyle(.plain)
                    .help(item.pinned ? "고정 해제" : "고정 — 항상 컨텍스트에 유지")
                    Button {
                        exclude(item)
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.ink3C)
                    }
                    .buttonStyle(.plain)
                    .help("제외 — 자동 컨텍스트에서 빼요 (아래 목록에서 복원 가능)")
                }
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

    // MARK: - Pin / Exclude (요구사항 §31)

    private func togglePin(_ item: ContextReport.Item) {
        if item.pinned {
            store.removeNarrativeOverride(
                kind: .contextPin, key: item.stableKey, in: store.activeID)
        } else {
            store.setNarrativeOverride(
                NarrativeOverride(kind: .contextPin, key: item.stableKey, value: "고정"),
                in: store.activeID)
        }
    }

    private func exclude(_ item: ContextReport.Item) {
        store.setNarrativeOverride(
            NarrativeOverride(kind: .contextExclude, key: item.stableKey, value: "제외"),
            in: store.activeID)
    }

    /// 제외 중인 항목 목록 — 복원 통로 (조용히 사라진 채 잊히지 않게).
    @ViewBuilder fileprivate var excludedList: some View {
        let excluded = (store.activeEntry?.narrativeOverrides ?? [])
            .filter { $0.kind == .contextExclude }
        if !excluded.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("제외 중 \(excluded.count)")
                    .font(MintFonts.uiFont(9.5, .semibold))
                    .foregroundStyle(theme.ink3C)
                ForEach(excluded) { override in
                    HStack(spacing: 5) {
                        Text(override.key)
                            .font(MintFonts.monoUI(9))
                            .foregroundStyle(theme.ink3C)
                            .lineLimit(1)
                        Spacer()
                        Button("복원") {
                            store.removeNarrativeOverride(
                                kind: .contextExclude, key: override.key,
                                in: store.activeID)
                        }
                        .font(MintFonts.uiFont(9.5))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func hasJump(_ item: ContextReport.Item) -> Bool {
        item.jumpQuery != nil || item.jumpUTF16 != nil
    }

    /// 원문 보기 — 인용이 있으면 인용 검색, 위치만 있으면 그 자리 스니펫 검색
    /// (타임라인과 같은 requestSearchJump 통로 — 좌표 불일치를 구조적으로 회피).
    private func jump(_ item: ContextReport.Item) {
        if let quote = item.jumpQuery {
            let query = store.activeEntry.flatMap {
                SourceAnchor.resilientQuery(for: quote, in: $0.body)
            } ?? quote
            store.requestSearchJump(store.activeID, query: query)
        } else if let offset = item.jumpUTF16,
            let body = store.activeEntry?.body,
            let snippet = NarrativeView.jumpSnippet(in: body, atUTF16: offset)
        {
            store.requestSearchJump(store.activeID, query: snippet)
        }
    }
}
