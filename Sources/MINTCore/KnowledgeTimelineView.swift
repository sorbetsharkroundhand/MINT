import SwiftUI

/// 이해 타임라인 (M6-5 → v4 Narrative Intelligence) — 백그라운드가 문서를 어떻게
/// 이해했는지 담화 순서로 보여준다 (PLAN §6.3·§6.5·§8).
///
/// 왜 필요한가: CLAUDE.md §1-5 "기억은 사용자의 것 — AI가 문서에서 이해한
/// 모든 것(인물·사건·요약)은 사용자가 볼 수 있고 **고칠 수 있어야** 한다".
///
/// v4에서 열람 전용을 벗어난다:
/// - 씬은 내용 기반 **제목**을 가진다 (컨텍스트 메뉴로 수정 — 오버라이드 저장).
/// - 사건은 **중요도 계층**으로 그린다 (핵심 = 큰 노드·자세히, 사소 = 접힘).
/// - 회상·꿈 등은 **브랜치 레일**로 갈라진다 (씬 유형 수정으로 편집).
/// - 씬·사건 클릭 → **근거 원문**으로 이동 (인용 우선, 없으면 씬 시작).
/// - 설정 충돌·복선 후보를 나열하고 판정은 사용자가 한다.
struct KnowledgeTimelineView: View {
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var store: EntryStore
    let theme: MintTheme
    /// 사이드바 섹션에 임베드됐는가 — 고정 폭·높이 상한을 풀고 공간을 채운다.
    var embedded = false

    /// 제목 수정 중인 씬 해시 (인라인 편집).
    @State private var editingSceneHash: String?
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if let snapshot = liveSnapshot {
                let names = characterNames
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        warningsList
                        conflictsList(snapshot)
                        staleNotice(snapshot)
                        railRows(snapshot, names: names)
                        foreshadowList(snapshot)
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: embedded ? .infinity : 380)
            } else {
                warningsList
                placeholder
                if embedded { Spacer(minLength: 0) }
            }
        }
        .padding(14)
        .frame(width: embedded ? nil : 460)
    }

    /// 델타·대화 렌더링용 인물 id → 이름.
    private var characterNames: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: (store.activeEntry?.characters ?? [])
                .map { ($0.id, $0.name) })
    }

    // MARK: - 본문 이동 (M7 점프 + v4 근거 점프)

    /// 본문 위치 클릭 → 에디터 이동 (M7 점프).
    ///
    /// 위치를 직접 넘기지 않고 **그 자리의 본문 스니펫을 검색어로** 넘긴다 —
    /// 지식의 오프셋은 마크다운 좌표, 에디터 스토리지는 렌더된 텍스트라 좌표가
    /// 어긋날 수 있다. 에디터가 자기 텍스트에서 스니펫을 찾아 이동하면(기존
    /// 전역 검색 통로 `requestSearchJump`) 그 불일치를 구조적으로 피한다.
    private func jump(toUTF16 offset: Int) {
        guard let body = store.activeEntry?.body,
            let snippet = Self.jumpSnippet(in: body, atUTF16: offset)
        else { return }
        store.requestSearchJump(store.activeID, query: snippet)
    }

    /// 근거 인용으로 이동 — 인용 자체가 본문 부분 문자열이라 그대로 검색어다.
    private func jump(quote: String) {
        store.requestSearchJump(store.activeID, query: quote)
    }

    /// 사건의 근거로 이동 — 인용이 있으면 인용(직접 근거), 없으면 씬 시작(추론).
    private func jumpToEvidence(of event: StoryEvent, sceneStart: Int) {
        if let quote = event.quote {
            jump(quote: quote)
        } else {
            jump(toUTF16: sceneStart)
        }
    }

    /// 오프셋 자리에서 검색 가능한 스니펫을 뽑는다 — 마크다운 마커·공백을
    /// 건너뛰고 산문 한 토막(≤40 UTF-16)을 취한다. 줄이 짧으면 그 줄까지만
    /// (개행 넘어 이어붙이면 스토리지에 없는 문자열이 된다).
    static func jumpSnippet(in body: String, atUTF16 offset: Int) -> String? {
        let ns = body as NSString
        var start = min(max(0, offset), ns.length)
        // 마커·공백 건너뛰기 — "# 1장"의 "#·공백"은 에디터 스토리지에 없다.
        while start < ns.length,
            "#>*- \t\n".unicodeScalars.map({ UInt16($0.value) })
                .contains(ns.character(at: start))
        {
            start += 1
        }
        guard start < ns.length else { return nil }
        let end = min(start + 40, ns.length)
        var snippet = ns.substring(with: NSRange(location: start, length: end - start))
        if let newline = snippet.firstIndex(of: "\n") {
            snippet = String(snippet[..<newline])
        }
        snippet = snippet.trimmingCharacters(in: .whitespaces)
        return snippet.count >= 2 ? snippet : nil
    }

    // MARK: - 오버라이드 저장 (사용자 수정 → entries.json)

    /// 씬 키 오버라이드 저장 — 재앵커용 스니펫(씬 첫머리 산문)을 함께 담는다.
    private func setSceneOverride(
        _ kind: NarrativeOverride.Kind, sceneHash: String, start: Int, value: String
    ) {
        let anchor = store.activeEntry?.body.isEmpty == false
            ? Self.jumpSnippet(in: store.activeEntry!.body, atUTF16: start) : nil
        store.setNarrativeOverride(
            NarrativeOverride(kind: kind, key: sceneHash, value: value, anchor: anchor),
            in: store.activeID)
    }

    // MARK: - 헤더

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
            // 수동 이해 트리거 (M6-8·v4) — 증분 + 전체 다시 읽기.
            ManualIndexButton(indexer: indexer, theme: theme)
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

    // MARK: - 일관성 경고 (M7 — 결정적 검사)

    @ViewBuilder private var warningsList: some View {
        if indexer.snapshot?.entryID == store.activeID, !indexer.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(indexer.warnings) { warning in
                    Button {
                        jump(toUTF16: warning.utf16Position)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.novelC)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(warning.kind.rawValue)
                                    .font(MintFonts.uiFont(10.5, .semibold))
                                    .foregroundStyle(theme.inkC)
                                Text(warning.message)
                                    .font(MintFonts.uiFont(10.5))
                                    .foregroundStyle(theme.ink2C)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(theme.novelBgC))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("본문의 해당 위치로 이동")
                }
            }
        }
    }

    // MARK: - 설정 충돌 후보 (v4, 요구사항 §14)

    /// 미판정·확정 충돌만 보여준다 — "의도됨"·"무시"는 사용자가 이미 답한 것.
    @ViewBuilder private func conflictsList(_ snapshot: KnowledgeSnapshot) -> some View {
        let visible = snapshot.factConflicts.filter {
            $0.resolution == nil || $0.resolution == .confirmed
        }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visible) { resolved in
                    ConflictRow(
                        resolved: resolved,
                        facts: snapshot.facts,
                        theme: theme,
                        onJumpQuote: { jump(quote: $0) },
                        onJumpScene: { hash in
                            if let scene = snapshot.outline.scenes.first(where: {
                                $0.contentHash == hash
                            }) {
                                jump(toUTF16: scene.utf16Range.lowerBound)
                            }
                        },
                        onResolve: { resolution in
                            store.setNarrativeOverride(
                                NarrativeOverride(
                                    kind: .conflictResolution,
                                    key: resolved.conflict.id,
                                    value: resolution.rawValue),
                                in: store.activeID)
                        })
                }
            }
        }
    }

    /// 근거를 잃은 사용자 수정 알림 — 조용히 지우지 않는다 (요구사항 §9).
    @ViewBuilder private func staleNotice(_ snapshot: KnowledgeSnapshot) -> some View {
        if !snapshot.staleOverrides.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.ink3C)
                Text("직접 수정한 항목 \(snapshot.staleOverrides.count)개의 원문 근거가 사라졌어요 — 원문이 돌아오면 다시 적용돼요.")
                    .font(MintFonts.uiFont(10))
                    .foregroundStyle(theme.ink3C)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 레일 (씬·사건·브랜치)

    @ViewBuilder private func railRows(
        _ snapshot: KnowledgeSnapshot, names: [UUID: String]
    ) -> some View {
        let rows = TimelineRow.rows(from: snapshot, body: store.activeEntry?.body ?? "")
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                TimelineRowView(
                    row: row, theme: theme, characterNames: names,
                    isFirst: offset == 0, isLast: offset == rows.count - 1,
                    isEditingTitle: editingTitleBinding(for: row),
                    draftTitle: $draftTitle,
                    onJump: { jump(toUTF16: $0) },
                    onJumpQuote: { jump(quote: $0) },
                    onJumpEvidence: { event, start in jumpToEvidence(of: event, sceneStart: start) },
                    onEditTitle: { hash, start, current in
                        draftTitle = current
                        editingSceneHash = hash
                        _ = start
                    },
                    onCommitTitle: { hash, start in
                        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
                        editingSceneHash = nil
                        guard !trimmed.isEmpty else { return }
                        setSceneOverride(.sceneTitle, sceneHash: hash, start: start, value: trimmed)
                    },
                    onSetSceneType: { hash, start, type in
                        setSceneOverride(
                            .sceneType, sceneHash: hash, start: start, value: type.rawValue)
                    },
                    onResetScene: { hash in
                        store.removeNarrativeOverride(
                            kind: .sceneTitle, key: hash, in: store.activeID)
                        store.removeNarrativeOverride(
                            kind: .sceneType, key: hash, in: store.activeID)
                    },
                    onSetImportance: { event, value in
                        store.setNarrativeOverride(
                            NarrativeOverride(
                                kind: .eventImportance, key: event.stableKey,
                                value: String(value)),
                            in: store.activeID)
                    },
                    onRenameBranch: { branch, name in
                        setSceneOverride(
                            .branchName, sceneHash: branch.anchorHash,
                            start: branchStart(branch, snapshot), value: name)
                    },
                    onSetBranchChrono: { branch, chrono in
                        setSceneOverride(
                            .branchChrono, sceneHash: branch.anchorHash,
                            start: branchStart(branch, snapshot), value: chrono.rawValue)
                    },
                    onMergeBranch: { branch in
                        // 브랜치 해제 = 구간 씬 전부를 '현재'로 (요구사항 §8:
                        // 잘못 만든 브랜치를 Main으로 되돌리기).
                        for index in branch.sceneRange {
                            let scene = snapshot.outline.scenes[index]
                            setSceneOverride(
                                .sceneType, sceneHash: scene.contentHash,
                                start: scene.utf16Range.lowerBound,
                                value: SceneNarrativeType.present.rawValue)
                        }
                    })
            }
        }
    }

    private func branchStart(_ branch: NarrativeBranch, _ snapshot: KnowledgeSnapshot) -> Int {
        snapshot.outline.scenes[branch.sceneRange.lowerBound].utf16Range.lowerBound
    }

    private func editingTitleBinding(for row: TimelineRow) -> Bool {
        if case .scene(let scene) = row { return editingSceneHash == scene.hash }
        return false
    }

    // MARK: - 복선 (v4, 요구사항 §15)

    @ViewBuilder private func foreshadowList(_ snapshot: KnowledgeSnapshot) -> some View {
        let visible = snapshot.foreshadows.filter { $0.status != .ignored }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.novelC)
                    Text("복선")
                        .font(MintFonts.uiFont(11, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text("미회수 \(snapshot.unresolvedForeshadows.count)")
                        .font(MintFonts.monoUI(9))
                        .foregroundStyle(theme.ink3C)
                }
                .padding(.top, 4)
                ForEach(visible) { thread in
                    ForeshadowRow(
                        thread: thread, theme: theme,
                        onJump: { jump(quote: $0) },
                        onStatus: { status in
                            store.setNarrativeOverride(
                                NarrativeOverride(
                                    kind: .foreshadowStatus, key: thread.label,
                                    value: status.rawValue),
                                in: store.activeID)
                        })
                }
            }
        }
    }
}

/// 수동 이해 트리거 (M6-8 → v4) — 기본 클릭은 **증분** 읽기(바뀐 씬만),
/// 메뉴에서 **처음부터 다시 읽기**(파생 캐시 폐기 후 전체 재분석)를 고른다.
/// 이미 전부 분석된 문서에서도 항상 동작한다 — "분석돼 있어서 다시 못 읽는"
/// 상태를 없앤다 (요구사항 §1). 사용자 수정은 entries.json에 있어 안전하다.
struct ManualIndexButton: View {
    @ObservedObject var indexer: BackgroundIndexer
    let theme: MintTheme

    var body: some View {
        if indexer.isIndexing {
            Text("읽는 중…")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink3C)
        } else {
            Menu {
                Button {
                    indexer.requestPass()
                } label: {
                    Label("지금 읽기 — 바뀐 부분만", systemImage: "sparkles")
                }
                Button {
                    indexer.requestFullPass()
                } label: {
                    Label("처음부터 다시 읽기", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Label("지금 읽기", systemImage: "sparkles")
                    .font(MintFonts.uiFont(10.5, .medium))
                    .foregroundStyle(theme.novelC)
            } primaryAction: {
                indexer.requestPass()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("클릭: 바뀐 씬만 읽기 · 메뉴: 전체 다시 읽기 (직접 수정한 내용은 보존돼요)")
        }
    }
}

// MARK: - 행 모델

/// 레일 위의 한 행 — 씬·사건·브랜치 경계를 한 줄로 편다. 레일 연속성(위/아래 선)을
/// 계산하려면 중첩 구조보다 평평한 배열이 낫다.
enum TimelineRow: Identifiable {
    struct SceneInfo {
        var hash: String
        /// 내용 기반 제목 (없으면 nil → 헤딩 경로가 주 라벨).
        var title: String?
        var titleUserEdited: Bool
        /// 헤딩 경로 라벨 ("1부 › 3장 (2/5)") — 제목이 있으면 보조 표시.
        var path: String
        var summary: String?
        var type: SceneNarrativeType
        var typeUserEdited: Bool
        var pov: String?
        var location: String?
        var characters: Int
        var start: Int
        /// 씬 대표 중요도 (사건 최댓값, 없으면 nil) — 노드 크기.
        var importance: Int?
        /// 브랜치 안 씬인가 — 들여쓴 보조 레일.
        var inBranch: Bool
    }

    case branchStart(branch: NarrativeBranch)
    case branchEnd(branch: NarrativeBranch)
    case scene(SceneInfo)
    /// 씬 원문이 이해 상한을 넘어 잘린 구간 — 지식에 존재하지 않는 본문이다.
    case truncated(id: String, total: Int, read: Int)
    case event(id: String, event: StoryEvent, start: Int, inBranch: Bool)
    /// 사소한 사건 묶음 (중요도 ≤2 여러 개) — 접힌 채 시작 (Progressive Disclosure).
    case minorEvents(id: String, events: [StoryEvent], start: Int, inBranch: Bool)
    /// 씬은 있는데 아직 요약·사건이 없는 상태 (다음 패스 대기).
    case pending(id: String, inBranch: Bool)

    var id: String {
        switch self {
        case .branchStart(let branch): "bs-\(branch.anchorHash)"
        case .branchEnd(let branch): "be-\(branch.anchorHash)"
        case .scene(let scene): "s-\(scene.hash)"
        case .truncated(let id, _, _): "t-\(id)"
        case .event(let id, _, _, _): "e-\(id)"
        case .minorEvents(let id, _, _, _): "m-\(id)"
        case .pending(let id, _): "p-\(id)"
        }
    }

    /// 클릭 시 에디터가 이동할 본문 위치 (UTF-16).
    var jumpTargetUTF16: Int? {
        switch self {
        case .scene(let scene): scene.start
        case .event(_, _, let start, _): start
        case .minorEvents(_, _, let start, _): start
        case .branchStart, .branchEnd, .truncated, .pending: nil
        }
    }

    var inBranch: Bool {
        switch self {
        case .scene(let scene): scene.inBranch
        case .event(_, _, _, let inBranch): inBranch
        case .minorEvents(_, _, _, let inBranch): inBranch
        case .pending(_, let inBranch): inBranch
        case .branchStart, .branchEnd: true
        case .truncated: false
        }
    }

    /// 사소 판정 경계 — 이하이면 접힘 대상 (Progressive Disclosure).
    static let minorImportanceCap = 2

    /// 스냅샷 + 원문 → 담화 순서의 행 배열 (브랜치 경계 포함).
    static func rows(from snapshot: KnowledgeSnapshot, body: String) -> [TimelineRow] {
        let text = body as NSString
        var eventsByScene: [String: [StoryEvent]] = [:]
        for event in snapshot.events {
            eventsByScene[event.sceneHash, default: []].append(event)
        }

        // 세그먼트 수 — 같은 헤딩 경로가 몇 조각으로 쪼개졌는지 (라벨 "1장 (3/14)").
        var segmentCounts: [[String]: Int] = [:]
        for scene in snapshot.outline.scenes {
            segmentCounts[scene.headingPath, default: 0] += 1
        }

        // 씬 인덱스 → 그 씬이 여는/닫는 브랜치.
        var branchStartAt: [Int: NarrativeBranch] = [:]
        var branchEndAt: [Int: NarrativeBranch] = [:]
        var branchMembers: Set<Int> = []
        for branch in snapshot.branches {
            branchStartAt[branch.sceneRange.lowerBound] = branch
            branchEndAt[branch.sceneRange.upperBound - 1] = branch
            branchMembers.formUnion(branch.sceneRange)
        }

        var rows: [TimelineRow] = []
        for (index, scene) in snapshot.outline.scenes.enumerated() {
            let inBranch = branchMembers.contains(index)
            if let branch = branchStartAt[index] {
                rows.append(.branchStart(branch: branch))
            }

            var path = scene.headingPath.filter { !$0.isEmpty }.joined(separator: " › ")
            if path.isEmpty { path = "서두" }
            // 상한 초과로 쪼개진 씬은 순번을 붙인다 (docs/m6-scene-split.md §4).
            if let count = segmentCounts[scene.headingPath], count > 1 {
                path += " (\(scene.segmentIndex + 1)/\(count))"
            }
            let meta = snapshot.sceneMetaByHash[scene.contentHash]
            let events = eventsByScene[scene.contentHash] ?? []
            rows.append(
                .scene(
                    SceneInfo(
                        hash: scene.contentHash,
                        title: meta?.title,
                        titleUserEdited: meta?.titleUserEdited ?? false,
                        path: path,
                        summary: snapshot.summariesByHash[scene.contentHash],
                        type: meta?.type ?? .present,
                        typeUserEdited: meta?.typeUserEdited ?? false,
                        pov: meta?.pov,
                        location: meta?.location,
                        characters: min(
                            scene.utf16Range.count,
                            max(0, text.length - scene.utf16Range.lowerBound)),
                        start: scene.utf16Range.lowerBound,
                        importance: events.map(\.importance).max(),
                        inBranch: inBranch
                    )))
            // 이해 상한 초과 — 뒷부분은 요약에도 사건에도 반영되지 않았다.
            if scene.utf16Range.count > BackgroundIndexer.maxSceneCharacters {
                rows.append(
                    .truncated(
                        id: scene.contentHash, total: scene.utf16Range.count,
                        read: BackgroundIndexer.maxSceneCharacters))
            }
            // 중요도 계층 (요구사항 §5): 핵심·보통 사건은 개별 행, 사소한 사건
            // (≤2)이 2개 이상이면 접힌 묶음 하나로 — 타임라인이 늘어지지 않는다.
            let major = events.filter { $0.importance > minorImportanceCap }
            let minor = events.filter { $0.importance <= minorImportanceCap }
            for (offset, event) in major.enumerated() {
                rows.append(
                    .event(
                        id: "\(scene.contentHash)-\(offset)", event: event,
                        start: scene.utf16Range.lowerBound, inBranch: inBranch))
            }
            if minor.count == 1 {
                rows.append(
                    .event(
                        id: "\(scene.contentHash)-minor0", event: minor[0],
                        start: scene.utf16Range.lowerBound, inBranch: inBranch))
            } else if minor.count >= 2 {                rows.append(
                    .minorEvents(
                        id: "\(scene.contentHash)-minor", events: minor,
                        start: scene.utf16Range.lowerBound, inBranch: inBranch))
            }
            if events.isEmpty, snapshot.summariesByHash[scene.contentHash] == nil {
                rows.append(.pending(id: "\(scene.contentHash)-\(index)", inBranch: inBranch))
            }

            if let branch = branchEndAt[index] {
                rows.append(.branchEnd(branch: branch))
            }
        }
        return rows
    }
}

// MARK: - 행 렌더

private struct TimelineRowView: View {
    let row: TimelineRow
    let theme: MintTheme
    /// 델타 렌더링용 인물 id → 이름. 카드가 지워져 못 찾는 델타는 표시하지 않는다.
    let characterNames: [UUID: String]
    let isFirst: Bool
    let isLast: Bool
    let isEditingTitle: Bool
    @Binding var draftTitle: String
    var onJump: ((Int) -> Void)?
    var onJumpQuote: ((String) -> Void)?
    var onJumpEvidence: ((StoryEvent, Int) -> Void)?
    var onEditTitle: ((String, Int, String) -> Void)?
    var onCommitTitle: ((String, Int) -> Void)?
    var onSetSceneType: ((String, Int, SceneNarrativeType) -> Void)?
    var onResetScene: ((String) -> Void)?
    var onSetImportance: ((StoryEvent, Int) -> Void)?
    var onRenameBranch: ((NarrativeBranch, String) -> Void)?
    var onSetBranchChrono: ((NarrativeBranch, ChronoRelation) -> Void)?
    var onMergeBranch: ((NarrativeBranch) -> Void)?

    /// 사소 묶음 펼침 상태.
    @State private var minorExpanded = false
    @State private var branchNameDraft = ""
    @State private var renamingBranch = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            rail
            content
                .padding(.bottom, verticalPadding)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let target = row.jumpTargetUTF16 { onJump?(target) }
        }
        .help(row.jumpTargetUTF16 != nil ? "본문의 해당 위치로 이동" : "")
    }

    private var verticalPadding: CGFloat {
        switch row {
        case .scene: 6
        case .branchStart, .branchEnd: 4
        default: 3
        }
    }

    /// 레일 — 행 높이만큼 세로선을 채우고 그 위에 노드를 얹는다. 브랜치 안
    /// 행은 보조 레일(파랑)이 오른쪽에 하나 더 생긴다 — git graph의 문학판.
    private var rail: some View {
        HStack(alignment: .top, spacing: 0) {
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
            if row.inBranch {
                Rectangle()
                    .fill(theme.blueC.opacity(0.45))
                    .frame(width: 2)
                    .padding(.leading, 2)
            }
        }
    }

    /// 노드 중심 — 텍스트 첫 줄의 시각적 중앙에 맞춘다.
    private var nodeCenter: CGFloat { isSceneRow ? 8 : 7 }

    private var isSceneRow: Bool {
        if case .scene = row { return true }
        return false
    }

    /// 중요도 기반 노드 크기 (요구사항 §5) — 핵심은 크게, 사소는 작게.
    private var nodeSize: CGFloat {
        switch row {
        case .scene(let scene):
            switch scene.importance ?? 3 {
            case 5: return 11
            case 4: return 10
            default: return 9
            }
        case .event(_, let event, _, _):
            switch event.importance {
            case 5: return 9
            case 4: return 8
            case 3: return 6
            default: return 4.5
            }
        case .minorEvents: return 4.5
        case .branchStart, .branchEnd: return 5
        default: return 5
        }
    }

    @ViewBuilder private var node: some View {
        switch row {
        case .scene:
            Circle()
                .fill(theme.novelC)
                .frame(width: nodeSize, height: nodeSize)
        case .event(_, let event, _, _):
            if event.importance >= 4 {
                Circle()
                    .fill(theme.novelC.opacity(0.85))
                    .frame(width: nodeSize, height: nodeSize)
            } else {
                Circle()
                    .strokeBorder(theme.novelC.opacity(0.75), lineWidth: 1.5)
                    .frame(width: nodeSize, height: nodeSize)
            }
        case .minorEvents:
            Circle()
                .strokeBorder(theme.ink3C, lineWidth: 1)
                .frame(width: nodeSize, height: nodeSize)
        case .branchStart, .branchEnd:
            Circle()
                .fill(theme.blueC.opacity(0.7))
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

    /// 사건의 델타들 → "상태: 서연 위치=병원 앞 · 민준 감정=불안" 한 줄.
    private func deltaLine(_ event: StoryEvent) -> String? {
        let pieces = event.deltas.compactMap { delta -> String? in
            guard let name = characterNames[delta.characterID] else { return nil }
            return "\(name) \(delta.field.rawValue)=\(delta.value)"
        }
        return pieces.isEmpty ? nil : "상태: \(pieces.joined(separator: " · "))"
    }

    @ViewBuilder private var content: some View {
        switch row {
        case .branchStart(let branch):
            branchLabel(branch, opening: true)
        case .branchEnd:
            HStack(spacing: 5) {
                Image(systemName: "arrow.turn.left.down")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.blueC.opacity(0.8))
                Text("본줄기로 복귀")
                    .font(MintFonts.uiFont(10))
                    .foregroundStyle(theme.ink3C)
            }
        case .scene(let scene):
            sceneContent(scene)
        case .truncated(_, let total, let read):
            // ⚠️ 헤딩 없는 장편이 씬 하나가 되면 여기서 대부분이 잘린다 (PLAN §8).
            Text("앞 \(read.formatted())자만 이해됨 — 나머지 \((total - read).formatted())자는 지식에 없어요")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
        case .event(_, let event, let start, _):
            eventContent(event, start: start)
        case .minorEvents(_, let events, let start, _):
            minorContent(events, start: start)
        case .pending:
            Text("아직 안 읽음")
                .font(MintFonts.uiFont(10.5))
                .foregroundStyle(theme.ink3C)
        }
    }

    // MARK: 브랜치 행

    @ViewBuilder private func branchLabel(_ branch: NarrativeBranch, opening: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8))
                .foregroundStyle(theme.blueC.opacity(0.9))
            if renamingBranch {
                TextField(
                    "브랜치 이름", text: $branchNameDraft,
                    onCommit: {
                        renamingBranch = false
                        let trimmed = branchNameDraft.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { onRenameBranch?(branch, trimmed) }
                    }
                )
                .textFieldStyle(.roundedBorder)
                .font(MintFonts.uiFont(10.5))
                .frame(width: 140)
            } else {
                Text(branch.name)
                    .font(MintFonts.uiFont(10.5, .semibold))
                    .foregroundStyle(theme.inkC)
            }
            Text(branch.chrono.rawValue)
                .font(MintFonts.uiFont(9))
                .foregroundStyle(theme.blueC)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(theme.blueC.opacity(0.12)))
            if branch.userEdited {
                UserEditedMark(theme: theme)
            }
        }
        .contextMenu {
            Button("이름 바꾸기") {
                branchNameDraft = branch.name
                renamingBranch = true
            }
            Menu("시간 관계") {
                ForEach(ChronoRelation.allCases, id: \.rawValue) { relation in
                    Button {
                        onSetBranchChrono?(branch, relation)
                    } label: {
                        if branch.chrono == relation {
                            Label(relation.rawValue, systemImage: "checkmark")
                        } else {
                            Text(relation.rawValue)
                        }
                    }
                }
            }
            Divider()
            Button("브랜치 해제 — 본줄기로 합치기") { onMergeBranch?(branch) }
        }
    }

    // MARK: 씬 행

    @ViewBuilder private func sceneContent(_ scene: TimelineRow.SceneInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditingTitle {
                TextField(
                    "씬 제목", text: $draftTitle,
                    onCommit: { onCommitTitle?(scene.hash, scene.start) }
                )
                .textFieldStyle(.roundedBorder)
                .font(MintFonts.serifUI(12, .semibold))
                .frame(width: 200)
            } else {
                HStack(spacing: 5) {
                    // 내용 기반 제목이 주 라벨, 헤딩 경로·씬 번호는 보조 (요구사항 §6).
                    Text(scene.title ?? scene.path)
                        .font(MintFonts.serifUI(12, .semibold))
                        .foregroundStyle(theme.inkC)
                        .fixedSize(horizontal: false, vertical: true)
                    if scene.titleUserEdited || scene.typeUserEdited {
                        UserEditedMark(theme: theme)
                    }
                    if scene.type != .present {
                        Text(scene.type.rawValue)
                            .font(MintFonts.uiFont(9))
                            .foregroundStyle(theme.blueC)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.blueC.opacity(0.12)))
                    }
                    Text("\(scene.characters.formatted())자")
                        .font(MintFonts.monoUI(9))
                        .foregroundStyle(theme.ink3C)
                }
                if scene.title != nil {
                    // 보조 라벨 — 어느 헤딩·몇 번째 조각인지.
                    Text(scene.path)
                        .font(MintFonts.uiFont(9))
                        .foregroundStyle(theme.ink3C)
                }
            }
            if let summary = scene.summary {
                Text(summary)
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.ink2C)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if scene.pov != nil || scene.location != nil {
                Text(
                    [scene.pov.map { "시점: \($0)" }, scene.location.map { "장소: \($0)" }]
                        .compactMap { $0 }.joined(separator: " · ")
                )
                .font(MintFonts.uiFont(9.5))
                .foregroundStyle(theme.ink3C)
            }
        }
        .contextMenu {
            Button("제목 수정") {
                onEditTitle?(scene.hash, scene.start, scene.title ?? "")
            }
            Menu("장면 유형") {
                ForEach(SceneNarrativeType.allCases, id: \.rawValue) { type in
                    Button {
                        onSetSceneType?(scene.hash, scene.start, type)
                    } label: {
                        if scene.type == type {
                            Label(type.rawValue, systemImage: "checkmark")
                        } else {
                            Text(type.rawValue)
                        }
                    }
                }
            }
            if scene.titleUserEdited || scene.typeUserEdited {
                Divider()
                Button("AI 분석으로 되돌리기") { onResetScene?(scene.hash) }
            }
        }
    }

    // MARK: 사건 행

    @ViewBuilder private func eventContent(_ event: StoryEvent, start: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(event.summary)
                    .font(MintFonts.uiFont(11, event.importance >= 4 ? .semibold : .regular))
                    .foregroundStyle(theme.inkC)
                    // 사소한 사건은 한 줄로 간결히 (요구사항 §5 요약 밀도).
                    .lineLimit(event.importance <= TimelineRow.minorImportanceCap ? 1 : nil)
                    .fixedSize(
                        horizontal: false,
                        vertical: event.importance > TimelineRow.minorImportanceCap)
                ImportanceDots(importance: event.importance, theme: theme)
                if let quote = event.quote {
                    Button {
                        onJumpQuote?(quote)
                    } label: {
                        Image(systemName: "text.quote")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.blueC)
                    }
                    .buttonStyle(.plain)
                    .help("근거 원문 보기: “\(quote)”")
                }
            }
            // 상태 델타 (M6-5b) — 핵심·보통 사건에서만 (사소는 요약 한 줄뿐).
            if event.importance > TimelineRow.minorImportanceCap,
                let rendered = deltaLine(event)
            {
                Text(rendered)
                    .font(MintFonts.uiFont(10))
                    .foregroundStyle(theme.ink3C)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            Menu("중요도") {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        onSetImportance?(event, level)
                    } label: {
                        if event.importance == level {
                            Label("\(level)", systemImage: "checkmark")
                        } else {
                            Text("\(level)")
                        }
                    }
                }
            }
            Button("근거 원문 보기") { onJumpEvidence?(event, start) }
        }
    }

    // MARK: 사소 사건 묶음

    @ViewBuilder private func minorContent(_ events: [StoryEvent], start: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                minorExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: minorExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                    Text("사소한 사건 \(events.count)개")
                        .font(MintFonts.uiFont(10))
                }
                .foregroundStyle(theme.ink3C)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if minorExpanded {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("·")
                            .foregroundStyle(theme.ink3C)
                        Text(event.summary)
                            .font(MintFonts.uiFont(10.5))
                            .foregroundStyle(theme.ink2C)
                            .lineLimit(1)
                        ImportanceDots(importance: event.importance, theme: theme)
                    }
                    .contextMenu {
                        Menu("중요도") {
                            ForEach(1...5, id: \.self) { level in
                                Button("\(level)") { onSetImportance?(event, level) }
                            }
                        }
                        Button("근거 원문 보기") { onJumpEvidence?(event, start) }
                    }
                }
            }
        }
    }
}

/// 사용자 수정 표식 — AI 추출과 시각적으로 구분 (요구사항 §18).
struct UserEditedMark: View {
    let theme: MintTheme

    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 8))
            .foregroundStyle(theme.novelC)
            .help("직접 수정한 항목 — 재분석해도 덮어쓰지 않아요")
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

// MARK: - 설정 충돌 행 (요구사항 §14)

private struct ConflictRow: View {
    let resolved: KnowledgeSnapshot.ResolvedConflict
    let facts: [ContinuityFact]
    let theme: MintTheme
    var onJumpQuote: (String) -> Void
    var onJumpScene: (String) -> Void
    var onResolve: (ConflictResolution) -> Void

    private func fact(_ id: String) -> ContinuityFact? {
        facts.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.2")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.novelC)
                Text(resolved.resolution == .confirmed ? "설정 충돌 (확정)" : "설정 충돌 후보")
                    .font(MintFonts.uiFont(10.5, .semibold))
                    .foregroundStyle(theme.inkC)
                if resolved.resolution != nil { UserEditedMark(theme: theme) }
            }
            if !resolved.conflict.reason.isEmpty {
                Text(resolved.conflict.reason)
                    .font(MintFonts.uiFont(10.5))
                    .foregroundStyle(theme.ink2C)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 두 근거 모두 원문으로 (요구사항: "관련된 두 원문 근거를 모두 확인").
            ForEach([resolved.conflict.aID, resolved.conflict.bID], id: \.self) { factID in
                if let fact = fact(factID) {
                    Button {
                        if let quote = fact.quote {
                            onJumpQuote(quote)
                        } else {
                            onJumpScene(fact.sceneHash)
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 8))
                            Text("\(fact.subject): \(fact.statement)")
                                .font(MintFonts.uiFont(10))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(theme.blueC)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("근거 원문 보기")
                }
            }
            if resolved.resolution == nil {
                HStack(spacing: 6) {
                    Button("충돌 맞음") { onResolve(.confirmed) }
                    Button("의도된 설정") { onResolve(.intended) }
                    Button("무시") { onResolve(.ignored) }
                }
                .font(MintFonts.uiFont(10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.novelBgC))
    }
}

// MARK: - 복선 행 (요구사항 §15)

private struct ForeshadowRow: View {
    let thread: ForeshadowThread
    let theme: MintTheme
    var onJump: (String) -> Void
    var onStatus: (ForeshadowStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(thread.label)
                    .font(MintFonts.uiFont(10.5, .semibold))
                    .foregroundStyle(theme.inkC)
                Text(statusLabel)
                    .font(MintFonts.uiFont(9))
                    .foregroundStyle(thread.status == .resolved ? theme.ink3C : theme.novelC)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(theme.novelBgC))
                if thread.userEdited { UserEditedMark(theme: theme) }
                if let quote = thread.quotes.first {
                    Button {
                        onJump(quote)
                    } label: {
                        Image(systemName: "text.quote")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.blueC)
                    }
                    .buttonStyle(.plain)
                    .help("근거 원문 보기")
                }
            }
            Text(thread.detail)
                .font(MintFonts.uiFont(10))
                .foregroundStyle(theme.ink2C)
                .fixedSize(horizontal: false, vertical: true)
            if thread.status == .candidate || thread.status == .confirmed {
                HStack(spacing: 6) {
                    if thread.status == .candidate {
                        Button("복선 확정") { onStatus(.confirmed) }
                        Button("무시") { onStatus(.ignored) }
                    }
                    if thread.status == .confirmed {
                        Button("회수됨") { onStatus(.resolved) }
                    }
                }
                .font(MintFonts.uiFont(10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.leading, 4)
    }

    private var statusLabel: String {
        var label = thread.status.rawValue
        if thread.isReinforced, thread.status != .resolved {
            label += " · \(thread.sceneHashes.count)곳"
        }
        return label
    }
}
