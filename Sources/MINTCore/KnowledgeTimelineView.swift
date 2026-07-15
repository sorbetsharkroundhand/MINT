import SwiftUI

/// 이해 타임라인 (M6-5) — 백그라운드가 문서를 어떻게 씬으로 쪼갰고 각 씬에서
/// 어떤 사건을 뽑았는지 담화 순서로 보여준다 (PLAN §6.3·§8).
///
/// 왜 필요한가: CLAUDE.md §1-5 "기억은 사용자의 것 — AI가 문서에서 이해한
/// 모든 것(인물·사건·요약)은 사용자가 볼 수 있어야 한다". 사건 로그가 사이드카
/// JSON에만 있으면 이 원칙이 깨진다.
///
/// gitgraph꼴 세로 레일: 씬은 채운 노드, 사건은 빈 노드. 시간축은 v1 담화 순서
/// (= 씬 배열 = 헤딩 구조, PLAN §8) — 스토리 시간이 아니다.
///
/// 읽기 전용이다 — 사건 수정(사용자 편집이 자동 추출을 이기는 규칙, §1-5)은
/// 바이블 패널 승격과 함께 온다.
struct KnowledgeTimelineView: View {
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var store: EntryStore
    let theme: MintTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if let snapshot = liveSnapshot {
                let rows = TimelineRow.rows(from: snapshot, body: store.activeEntry?.body ?? "")
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                            TimelineRowView(
                                row: row, theme: theme,
                                isFirst: offset == 0, isLast: offset == rows.count - 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 380)
            } else {
                placeholder
            }
        }
        .padding(14)
        .frame(width: 460)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(theme.novelC)
            Text("이해 타임라인")
                .font(MintFonts.uiFont(13, .semibold))
                .foregroundStyle(theme.inkC)
            Spacer()
            if let snapshot = liveSnapshot {
                Text("씬 \(snapshot.outline.scenes.count) · 사건 \(snapshot.events.count)")
                    .font(MintFonts.monoUI(10))
                    .foregroundStyle(theme.ink3C)
            }
            if indexer.isIndexing {
                Text("읽는 중")
                    .font(MintFonts.uiFont(10))
                    .foregroundStyle(theme.ink3C)
            }
        }
    }

    /// 활성 문서의 스냅샷만 — 문서를 막 바꾸면 인덱서 스냅샷이 아직 이전
    /// 문서 것일 수 있다. 남의 작품 타임라인을 보여주느니 비워 둔다.
    private var liveSnapshot: KnowledgeSnapshot? {
        guard let snapshot = indexer.snapshot,
            snapshot.entryID == store.activeEntry?.id
        else { return nil }
        return snapshot
    }

    private var placeholder: some View {
        Text(
            store.activeEntry?.resolvedKind == .novel
                ? "아직 이해한 내용이 없어요. 타이핑을 멈추면 백그라운드가 장면을 읽기 시작해요."
                : "소설 종류의 문서에서만 타임라인을 만들어요."
        )
        .font(MintFonts.uiFont(11))
        .foregroundStyle(theme.ink3C)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

// MARK: - 행 모델

/// 레일 위의 한 행 — 씬·사건·경고를 한 줄로 편다. 레일 연속성(위/아래 선)을
/// 계산하려면 중첩 구조보다 평평한 배열이 낫다.
enum TimelineRow: Identifiable {
    case scene(id: String, path: String, summary: String?, characters: Int)
    /// 씬 원문이 이해 상한을 넘어 잘린 구간 — 지식에 존재하지 않는 본문이다.
    case truncated(id: String, total: Int, read: Int)
    case event(id: String, event: StoryEvent)
    /// 씬은 있는데 아직 요약·사건이 없는 상태 (다음 패스 대기).
    case pending(id: String)

    var id: String {
        switch self {
        case .scene(let id, _, _, _): "s-\(id)"
        case .truncated(let id, _, _): "t-\(id)"
        case .event(let id, _): "e-\(id)"
        case .pending(let id): "p-\(id)"
        }
    }

    /// 스냅샷 + 원문 → 담화 순서의 행 배열.
    static func rows(from snapshot: KnowledgeSnapshot, body: String) -> [TimelineRow] {
        let text = body as NSString
        var eventsByScene: [String: [StoryEvent]] = [:]
        for event in snapshot.events {
            eventsByScene[event.sceneHash, default: []].append(event)
        }

        var rows: [TimelineRow] = []
        for (index, scene) in snapshot.outline.scenes.enumerated() {
            let path = scene.headingPath.filter { !$0.isEmpty }.joined(separator: " › ")
            let events = eventsByScene[scene.contentHash] ?? []
            rows.append(
                .scene(
                    id: scene.contentHash,
                    path: path.isEmpty ? "서두" : path,
                    summary: snapshot.summariesByHash[scene.contentHash],
                    characters: min(scene.utf16Range.count, max(0, text.length - scene.utf16Range.lowerBound))
                ))
            // 이해 상한 초과 — 뒷부분은 요약에도 사건에도 반영되지 않았다.
            if scene.utf16Range.count > BackgroundIndexer.maxSceneCharacters {
                rows.append(
                    .truncated(
                        id: scene.contentHash, total: scene.utf16Range.count,
                        read: BackgroundIndexer.maxSceneCharacters))
            }
            for (offset, event) in events.enumerated() {
                rows.append(.event(id: "\(scene.contentHash)-\(offset)", event: event))
            }
            if events.isEmpty, snapshot.summariesByHash[scene.contentHash] == nil {
                rows.append(.pending(id: "\(scene.contentHash)-\(index)"))
            }
        }
        return rows
    }
}

// MARK: - 행 렌더

private struct TimelineRowView: View {
    let row: TimelineRow
    let theme: MintTheme
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            rail
            content
                .padding(.bottom, isSceneRow ? 6 : 3)
            Spacer(minLength: 0)
        }
    }

    private var isSceneRow: Bool {
        if case .scene = row { return true }
        return false
    }

    /// 레일 — 행 높이만큼 세로선을 채우고 그 위에 노드를 얹는다. 행마다 자기
    /// 구간을 그리므로 행이 이어지면 선도 이어진다 (첫/마지막 행만 반쪽).
    private var rail: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : theme.sepStrongC)
                    .frame(width: 1, height: nodeCenter)
                Rectangle()
                    .fill(isLast ? Color.clear : theme.sepStrongC)
                    .frame(width: 1)
            }
            node
                .offset(y: nodeCenter - nodeSize / 2)
        }
        .frame(width: 11)
    }

    /// 노드 중심 — 텍스트 첫 줄의 시각적 중앙에 맞춘다.
    private var nodeCenter: CGFloat { isSceneRow ? 8 : 7 }
    private var nodeSize: CGFloat {
        switch row {
        case .scene: 9
        case .event: 6
        default: 5
        }
    }

    @ViewBuilder private var node: some View {
        switch row {
        case .scene:
            // 씬 = 채운 노드 (커밋).
            Circle()
                .fill(theme.novelC)
                .frame(width: nodeSize, height: nodeSize)
        case .event:
            // 사건 = 빈 노드.
            Circle()
                .strokeBorder(theme.novelC.opacity(0.75), lineWidth: 1.5)
                .frame(width: nodeSize, height: nodeSize)
        case .truncated:
            Circle()
                .fill(theme.ink3C)
                .frame(width: nodeSize, height: nodeSize)
        case .pending:
            Circle()
                .strokeBorder(theme.ink3C, lineWidth: 1)
                .frame(width: nodeSize, height: nodeSize)
        }
    }

    @ViewBuilder private var content: some View {
        switch row {
        case .scene(_, let path, let summary, let characters):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(path)
                        .font(MintFonts.serifUI(12, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text("\(characters.formatted())자")
                        .font(MintFonts.monoUI(9))
                        .foregroundStyle(theme.ink3C)
                }
                if let summary {
                    Text(summary)
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(theme.ink2C)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .truncated(_, let total, let read):
            // ⚠️ 헤딩 없는 장편이 씬 하나가 되면 여기서 대부분이 잘린다 (PLAN §8).
            Text("앞 \(read.formatted())자만 이해됨 — 나머지 \((total - read).formatted())자는 지식에 없어요")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
        case .event(_, let event):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(event.summary)
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.inkC)
                    .fixedSize(horizontal: false, vertical: true)
                ImportanceDots(importance: event.importance, theme: theme)
            }
        case .pending:
            Text("아직 안 읽음")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink3C)
        }
    }
}

/// 중요도 1–5 — 숫자보다 점이 훑기 쉽다 (조용한 UI, CLAUDE.md §3).
private struct ImportanceDots: View {
    let importance: Int
    let theme: MintTheme

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...5, id: \.self) { level in
                Circle()
                    .fill(level <= importance ? theme.novelC.opacity(0.55) : theme.sepC)
                    .frame(width: 3, height: 3)
            }
        }
        .help("중요도 \(importance)/5")
    }
}
