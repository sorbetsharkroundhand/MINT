import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 사이드바 섹션 (M6-8) — VSCode의 활동 바처럼 사이드바가 여러 패널을 담는다.
/// 문자열 raw값은 `@AppStorage("mint.sidebarSection")` 키의 값 — 툴바(소설 배지)와
/// 사이드바가 같은 키로 섹션을 전환한다.
enum SidebarSection: String {
    case files // 문서(폴더 트리) — 기존 사이드바
    case bible // 스토리 바이블 (PLAN §7)
    /// 서사 (v5 통합) — 이해 타임라인 + 서사 그래프가 하나의 화면이 됐다
    /// (PLAN §6.6). raw값 "timeline" 유지 — 기존 사용자의 저장된 섹션이 살아남는다.
    case narrative = "timeline"
    case context // AI 컨텍스트 인스펙터 (v4, 요구사항 §17)
    case agent // 읽기 전용 Writing Agent (PLAN §14 M10)
}

/// 일관성 경고 존재 표시 점 (M7) — indexer를 관찰해 경고가 생기는 즉시 뜬다.
private struct WarningDot: View {
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var store: EntryStore
    let theme: MintTheme

    var body: some View {
        // 일관성 경고 — "확인해 보세요" 신호.
        if indexer.snapshot?.entryID == store.activeID,
           !indexer.warnings.isEmpty {
            Circle()
                .fill(theme.novelC)
                .frame(width: 5, height: 5)
                .offset(x: -3, y: 3)
        }
    }
}

/// 섹션이 보여줄 내용이 없을 때의 안내 문구 한 장.
private struct SidebarSectionHint: View {
    let theme: MintTheme
    let text: String

    var body: some View {
        VStack {
            Text(text)
                .font(MintFonts.uiFont(11))
                .foregroundStyle(theme.ink3C)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            Spacer(minLength: 0)
        }
    }
}

/// 좌측 사이드바 (에디터 v3 — 디자인 이식, 파일시스템 v1 · 섹션화 M6-8).
///
/// 상단: 사이드바 전체 폭을 쓰는 52px 헤더 — 신호등 안전영역 뒤에 현재 섹션,
/// 문서 섹션일 때만 새 폴더·소설·저널 액션.
/// 그 아래 세로 활동 레일로 문서·바이블·서사·컨텍스트·Agent를 전환한다.
/// 팝오버였던 바이블·서사는 상시 패널로 승격한다.
/// 목록(문서 섹션): 폴더 트리(펼침/접힘) + 저널 행.
struct SidebarView: View {
    @ObservedObject var store: EntryStore
    /// AI 폴더 명명(requestFolderName)과 진행 표시(namingFolderIDs)에 쓴다.
    @ObservedObject var completion: CompletionController
    let theme: MintTheme
    /// 바이블·타임라인 섹션의 데이터 소스 — nil이면 문서 섹션만 (프리뷰 등).
    var indexer: BackgroundIndexer?
    /// nil이면 Agent 탭을 숨긴다(프리뷰·테스트의 기존 초기화 호환).
    var agent: AgentController?
    /// 활동 레일만 남긴 집중 상태. 아이콘을 누르면 해당 패널을 전체로 연다.
    var railOnly = false

    /// 현재 섹션 — 툴바의 소설 배지도 이 키를 써서 바이블 섹션을 연다.
    @AppStorage("mint.sidebarSection") private var sectionRaw = SidebarSection.files.rawValue
    @AppStorage("mint.sidebarVisible") private var legacySidebarVisible = true
    @AppStorage("mint.sidebarMode") private var sidebarModeRaw = ""
    private var section: SidebarSection {
        SidebarSection(rawValue: sectionRaw) ?? .files
    }

    /// 드래그&드롭 세션 상태 — 드래그 원본·드롭 표시 위치.
    @StateObject private var dragModel = SidebarDragModel()

    /// 이름 변경 중인 항목 — 저널·폴더가 id 공간을 공유한다.
    @State private var editingID: UUID?
    @State private var draftTitle = ""
    @State private var hoveredID: UUID?
    /// 내용이 있어 삭제 전 확인이 필요한 저널 — alert 표시 중.
    @State private var deleteCandidate: JournalEntry?
    /// 내용이 있어 삭제 전 확인이 필요한 폴더 — alert 표시 중.
    @State private var folderDeleteCandidate: JournalFolder?
    @FocusState private var renameFieldFocused: Bool
    /// 전역 검색어 — 비어 있지 않으면 트리 대신 검색 결과(평탄)를 보여준다.
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if railOnly {
                VStack(spacing: 0) {
                    Color.clear.frame(height: MintChrome.toolbarHeight)
                    theme.sepC.frame(height: 1)
                    activityRail
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // 신호등은 레일과 패널 어느 한쪽의 소유가 아니다. 상단 전체를
                    // 쓰는 전용 행에 두어 패널 제목과 겹치지 않게 한다.
                    header
                    theme.sepC.frame(height: 1)
                    HStack(spacing: 0) {
                        activityRail
                            .frame(width: MintChrome.activityRailWidth)
                        theme.sepC.frame(width: 1)
                        sectionContent
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .topLeading
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.ultraThinMaterial)
        .background(theme.sidebarTintC)
        .overlay(alignment: .trailing) { theme.sepC.frame(width: 1) }
        .onChange(of: renameFieldFocused) { _, focused in
            // Enter(onSubmit) 외에 포커스를 잃어도 커밋 — Esc는 editingID를
            // 먼저 비우므로 여기 걸리지 않는다.
            if !focused, let id = editingID { commitRename(id) }
        }
        .onChange(of: store.searchFocusRequests) { _, _ in
            // ⌘⇧F — 검색 필드로 포커스 (문서 섹션으로 전환해서).
            sectionRaw = SidebarSection.files.rawValue
            searchFieldFocused = true
        }
        .onChange(of: store.renameRequests) { _, _ in
            // 메뉴 "저널 이름 바꾸기" — 현재 저널의 인라인 편집을 시작한다.
            sectionRaw = SidebarSection.files.rawValue
            if let entry = store.activeEntry { startRename(entry) }
        }
        .alert(
            "‘\(deleteCandidate?.title ?? "")’을(를) 삭제할까요?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            presenting: deleteCandidate
        ) { entry in
            Button("삭제", role: .destructive) { store.delete(entry.id) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("작성한 내용이 함께 삭제되며 되돌릴 수 없어요.")
        }
        .alert(
            "‘\(folderDeleteCandidate?.name ?? "")’ 폴더를 삭제할까요?",
            isPresented: Binding(
                get: { folderDeleteCandidate != nil },
                set: { if !$0 { folderDeleteCandidate = nil } }
            ),
            presenting: folderDeleteCandidate
        ) { folder in
            Button("삭제", role: .destructive) { store.deleteFolder(folder.id) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("폴더 안의 하위 폴더와 저널이 함께 삭제되며 되돌릴 수 없어요.")
        }
    }

    /// 활동 레일을 뺀 실제 가용 폭을 각 패널에 명시적으로 제안한다. 콘텐츠의
    /// 이상적 크기가 사이드바 폭을 다시 밀어내는 순환을 끊는 레이아웃 경계다.
    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .files: filesSection
        case .bible: bibleSection
        case .narrative: narrativeSection
        case .context: contextSection
        case .agent: agentSection
        }
    }

    /// IDE 활동 레일. 문서 탐색과 작품 이해 도구를 같은 세로 축에 두되,
    /// 선택된 도구만 민트 광선으로 잇는다 — 패널마다 다른 탭 문법을 만들지 않는다.
    private var activityRail: some View {
        VStack(spacing: 7) {
            sectionTab(.files, icon: "doc.text", help: "문서")
            sectionTab(.bible, icon: "book.closed", help: "스토리 바이블")
            sectionTab(
                .narrative, icon: "arrow.triangle.branch",
                help: "서사 — 씬·사건·흐름·시간"
            )
            sectionTab(.context, icon: "eye", help: "AI 컨텍스트 — 예측이 참고한 정보")
            if agent != nil {
                sectionTab(.agent, icon: "sparkles", help: "Writing Agent — 작품 조회와 조언")
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.toolbarC)
    }

    private func sectionTab(
        _ target: SidebarSection, icon: String, help: String
    ) -> some View {
        Button {
            sectionRaw = target.rawValue
            if railOnly {
                sidebarModeRaw = SidebarPresentation.full.rawValue
                legacySidebarVisible = true
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(section == target ? theme.novelC : theme.ink3C)
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(
                        cornerRadius: MintChrome.controlRadius, style: .continuous
                    )
                    .fill(section == target ? theme.novelBgC : .clear)
                )
                .overlay(alignment: .leading) {
                    if section == target {
                        Capsule()
                            .fill(theme.novelC)
                            .frame(width: 2, height: 17)
                            .offset(x: -6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // 일관성 경고(M7) 점 — 비침습 배지 (CLAUDE.md §3). 관찰
                    // 서브뷰라 패스가 끝나는 즉시 나타난다.
                    if target == .narrative, let indexer {
                        WarningDot(indexer: indexer, store: store, theme: theme)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    /// 바이블 섹션 — 팝오버와 같은 뷰를 임베드 모드로 (M6-8 패널 승격).
    /// 저널이면 안내 + **소설 전환 버튼** — 여기서 막힌 사용자가 바로 풀 수 있게
    /// (M7 요청: 기존 문서를 소설로 바꾸는 통로가 없었다).
    @ViewBuilder private var bibleSection: some View {
        if store.activeEntry?.resolvedKind == .novel {
            CharacterBibleView(store: store, theme: theme, indexer: indexer, embedded: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("이 문서는 일반 저널이에요. 소설로 전환하면 인물·장르 관리와 백그라운드 이해(요약·사건·타임라인)가 켜져요.")
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.ink3C)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    store.setKind(.novel, for: store.activeID)
                } label: {
                    Label("소설로 전환", systemImage: "book.closed")
                        .font(MintFonts.uiFont(12, .medium))
                }
                Text("원문은 그대로예요 — 언제든 우클릭 메뉴에서 일반 저널로 되돌릴 수 있어요.")
                    .font(MintFonts.uiFont(10))
                    .foregroundStyle(theme.ink3C)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    /// 서사 섹션 (v5 통합) — 뷰 자체가 비소설 안내를 갖고 있다.
    @ViewBuilder private var narrativeSection: some View {
        if let indexer {
            NarrativeView(indexer: indexer, store: store, theme: theme, embedded: true)
        } else {
            SidebarSectionHint(theme: theme, text: "이해 파이프라인이 준비되지 않았어요.")
        }
    }

    /// AI 컨텍스트 섹션 (v4) — 최근 예측이 실제로 참고한 정보의 열람.
    private var contextSection: some View {
        ContextInspectorView(
            completion: completion, store: store, theme: theme, embedded: true
        )
    }

    /// Agent는 별도 진입점이지만 자동완성과 같은 KnowledgeSnapshot·모델을 쓴다.
    @ViewBuilder private var agentSection: some View {
        if let agent {
            AgentView(agent: agent, theme: theme, embedded: true)
        } else {
            SidebarSectionHint(theme: theme, text: "Writing Agent가 준비되지 않았어요.")
        }
    }

    /// 문서(폴더 트리) 섹션 — 기존 사이드바 본문 그대로.
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            theme.sepC.frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    if isSearching {
                        searchResults
                    } else {
                        ForEach(items) { item in
                            switch item {
                            case let .folder(folder, depth):
                                folderRow(folder, depth: depth)
                            case let .entry(entry, depth):
                                row(entry, depth: depth)
                            }
                        }
                        // 목록 바로 아래 빈 띠 — 루트 맨 끝으로 드롭하는 받이.
                        Color.clear
                            .frame(height: 44)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) {
                                if dragModel.indicator == .root {
                                    SidebarInsertionLine(theme: theme, depth: 0)
                                        .offset(y: 2)
                                }
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: RootAreaDropDelegate(
                                    store: store, model: dragModel
                                )
                            )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            // 짧은 목록에서 받이 띠 아래의 넓은 빈 영역도 루트 드롭을 받는다 —
            // 행 위 드롭은 더 깊은 히트 테스트가 이기므로 충돌하지 않는다.
            .onDrop(
                of: [.plainText],
                delegate: RootAreaDropDelegate(store: store, model: dragModel)
            )
        }
    }

    // MARK: - 트리 평탄화

    private enum SidebarItem: Identifiable {
        case folder(JournalFolder, depth: Int)
        case entry(JournalEntry, depth: Int)

        var id: UUID {
            switch self {
            case let .folder(folder, _): folder.id
            case let .entry(entry, _): entry.id
            }
        }
    }

    /// 트리를 위에서 아래로 편 목록 — 각 단계에서 폴더 먼저, 그다음 저널.
    private var items: [SidebarItem] {
        var result: [SidebarItem] = []
        appendChildren(of: nil, depth: 0, into: &result)
        return result
    }

    private func appendChildren(of parentID: UUID?, depth: Int, into result: inout [SidebarItem]) {
        for folder in store.childFolders(of: parentID) {
            result.append(.folder(folder, depth: depth))
            if store.isExpanded(folder.id) {
                appendChildren(of: folder.id, depth: depth + 1, into: &result)
            }
        }
        for entry in store.childEntries(of: parentID) {
            result.append(.entry(entry, depth: depth))
        }
    }

    // MARK: - 삭제

    /// 저널 삭제 요청 — 비어 있으면 바로 지우고, 내용이 있으면 한 번 더 묻는다.
    private func requestDelete(_ entry: JournalEntry) {
        if entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.delete(entry.id)
        } else {
            deleteCandidate = entry
        }
    }

    /// 폴더 삭제 요청 — 비어 있으면 바로 지우고, 내용물이 있으면 한 번 더 묻는다.
    private func requestDeleteFolder(_ folder: JournalFolder) {
        if store.folderHasContents(folder.id) {
            folderDeleteCandidate = folder
        } else {
            store.deleteFolder(folder.id)
        }
    }

    // MARK: - 헤더

    private var header: some View {
        // 레일이 "어디"를 고르고 헤더가 "무엇"인지 말한다. 문서 생성 액션은
        // 문서 패널에서만 보여 도구의 문맥을 흐리지 않는다.
        HStack(spacing: 2) {
            Text(sectionTitle)
                .font(MintFonts.uiFont(12, .semibold))
                .foregroundStyle(theme.ink2C)
                .lineLimit(1)
            Spacer(minLength: 0)
            if section == .files {
                HeaderIconButton(theme: theme, help: "새 폴더") {
                    store.newFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13.5, weight: .medium))
                }
                HeaderIconButton(theme: theme, help: "새 소설") {
                    store.newEntry(kind: .novel)
                } label: {
                    Image(systemName: "book.closed")
                        .font(.system(size: 13, weight: .medium))
                }
                HeaderIconButton(theme: theme, help: "새 저널") {
                    store.newEntry()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
            }
        }
        // 세 신호등의 오른쪽에서 제목이 시작된다. 버튼의 표준 순서·간격은
        // 그대로 두고 전용 안전영역을 배정해 macOS 근육 기억을 지킨다.
        .padding(.leading, MintChrome.windowControlsSafeWidth)
        .padding(.trailing, 12)
        .frame(height: MintChrome.toolbarHeight)
    }

    private var sectionTitle: String {
        switch section {
        case .files: "문서"
        case .bible: "스토리 바이블"
        case .narrative: "서사"
        case .context: "AI 컨텍스트"
        case .agent: "Writing Agent"
        }
    }

    // MARK: - 전역 검색

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.ink3C)
            TextField("모든 저널 검색", text: $searchText)
                .textFieldStyle(.plain)
                .font(MintFonts.uiFont(13))
                .foregroundStyle(theme.inkC)
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFieldFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink3C)
                }
                .buttonStyle(.plain)
                .help("검색 지우기")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .mintGlassSurface(theme: theme)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = store.search(searchText)
        if results.isEmpty {
            Text("일치하는 저널이 없어요")
                .font(MintFonts.uiFont(12))
                .foregroundStyle(theme.ink3C)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.top, 6)
        } else {
            ForEach(results) { entry in
                searchRow(entry)
            }
        }
    }

    @ViewBuilder
    private func searchRow(_ entry: JournalEntry) -> some View {
        let active = entry.id == store.activeID
        Button {
            // 저널만 여는 게 아니라 본문 매치 위치로 스크롤·표시까지 (요구 2).
            store.requestSearchJump(entry.id, query: searchText)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    // 트리와 같은 종류 아이콘 규칙 — 검색 결과에서도 저널/소설이 갈리게.
                    if entry.resolvedKind == .novel {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.novelC)
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(active ? theme.blueC : theme.ink3C)
                    }
                    Text(entry.title)
                        .font(MintFonts.uiFont(13, .semibold))
                        .foregroundStyle(active ? theme.inkC : theme.ink2C)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(store.dayLabel(for: entry))
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(theme.ink3C)
                }
                if let snippet = Self.snippet(entry.body, query: searchText) {
                    Text(snippet)
                        .font(MintFonts.uiFont(11.5))
                        .foregroundStyle(theme.ink3C)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? theme.activeBgC : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 매치 주변 발췌 — 앞뒤 24자에 줄임표. 본문 인덱스로 직접 잘라 안전하다.
    private static func snippet(_ body: String, query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let range = body.range(of: q, options: .caseInsensitive)
        else { return nil }
        let start =
            body.index(range.lowerBound, offsetBy: -24, limitedBy: body.startIndex)
                ?? body.startIndex
        let end =
            body.index(range.upperBound, offsetBy: 24, limitedBy: body.endIndex)
                ?? body.endIndex
        var text = String(body[start ..< end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start != body.startIndex { text = "…" + text }
        if end != body.endIndex { text += "…" }
        return text
    }

    // MARK: - 폴더 행

    @ViewBuilder
    private func folderRow(_ folder: JournalFolder, depth: Int) -> some View {
        let expanded = store.isExpanded(folder.id)
        let editing = editingID == folder.id
        let hovered = hoveredID == folder.id
        let dropTarget = dragModel.indicator == .into(folder.id)
        let naming = completion.namingFolderIDs.contains(folder.id)

        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.ink3C)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .animation(.easeOut(duration: 0.15), value: expanded)
                .frame(width: 12)

            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.ink2C)

            if editing {
                TextField("폴더 이름", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.kbdC))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(theme.blueC)
                    )
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(folder.id) }
                    .onExitCommand {
                        editingID = nil
                        renameFieldFocused = false
                    }
            } else {
                Text(folder.name)
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.ink2C)
                    .lineLimit(1)
                // AI가 이름을 짓는 동안 — 임시 이름("새 폴더") 옆 진행 점.
                if naming {
                    PulsingDots(color: theme.ink3C)
                }
            }

            Spacer(minLength: 6)

            if !editing {
                // opacity 토글 — 조건부 삽입이면 hover 때 행 높이가 튄다.
                HStack(spacing: 2) {
                    RowIconButton(
                        systemName: "folder.badge.plus", help: "새 하위 폴더", theme: theme
                    ) { store.newFolder(in: folder.id) }
                    RowIconButton(systemName: "plus", help: "폴더에 새 저널", theme: theme) {
                        store.newEntry(in: folder.id)
                    }
                }
                .opacity(hovered ? 1 : 0)
                .allowsHitTesting(hovered)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 11)
        .padding(.leading, CGFloat(depth) * 14)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dropTarget ? theme.activeBgC : (hovered ? theme.hoverC : .clear))
        )
        // 드롭 "안으로" 대상 표시 — 파란 링 (접힌 폴더에도 이동을 약속).
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(theme.blueC, lineWidth: 1.5)
            }
        }
        // 형제 폴더 사이 삽입선.
        .overlay(alignment: .top) {
            if dragModel.indicator == .before(folder.id) {
                SidebarInsertionLine(theme: theme, depth: depth).offset(y: -2)
            }
        }
        .overlay(alignment: .bottom) {
            if dragModel.indicator == .after(folder.id) {
                SidebarInsertionLine(theme: theme, depth: depth).offset(y: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hoveredID = $0 ? folder.id : nil }
        // 저널 행과 같은 이유 — 첫 탭 즉시 펼침/접힘 (더블탭이 오면 두 번
        // 토글돼 원상복구된 채 이름변경으로 들어간다).
        .simultaneousGesture(TapGesture().onEnded { store.toggleExpanded(folder.id) })
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRenameFolder(folder) })
        .onDrag {
            guard editingID == nil else { return NSItemProvider() }
            dragModel.beginDrag(.folder(id: folder.id))
            return NSItemProvider(object: folder.id.uuidString as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: FolderRowDropDelegate(
                folder: folder, expanded: expanded, store: store, model: dragModel,
                requestNaming: { completion.requestFolderName(for: $0, in: store) }
            )
        )
        .contextMenu {
            Button("새 저널") { store.newEntry(in: folder.id) }
            Button("새 소설") { store.newEntry(in: folder.id, kind: .novel) }
            Button("새 하위 폴더") { store.newFolder(in: folder.id) }
            Button("이름 바꾸기") { startRenameFolder(folder) }
            Button("삭제", role: .destructive) { requestDeleteFolder(folder) }
        }
    }

    // MARK: - 저널 행

    @ViewBuilder
    private func row(_ entry: JournalEntry, depth: Int) -> some View {
        let active = entry.id == store.activeID
        let editing = editingID == entry.id
        let hovered = hoveredID == entry.id
        let dropTarget = dragModel.indicator == .into(entry.id)

        HStack(spacing: 11) {
            // 종류별 아이콘 — 일반은 문서, 소설은 책. 소설은 비활성에서도 보라
            // 정체성을 유지해 목록만 훑어도 종류가 갈린다 (파랑 계열 = 저널).
            Group {
                if entry.resolvedKind == .novel {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            active ? theme.novelC : theme.novelC.opacity(0.6)
                        )
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(active ? theme.blueC : theme.ink3C)
                }
            }
            .frame(width: 11)

            if editing {
                TextField("제목", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.kbdC))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(theme.blueC)
                    )
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(entry.id) }
                    .onExitCommand {
                        editingID = nil
                        renameFieldFocused = false
                    }
            } else {
                // 소설 제목은 본문과 같은 세리프 — 목록에서도 "책" 느낌이 나게.
                Text(entry.title)
                    .font(entry.resolvedKind == .novel
                        ? MintFonts.serifUI(13, active ? .semibold : .medium)
                        : MintFonts.uiFont(13, active ? .semibold : .medium))
                    .foregroundStyle(active ? theme.inkC : theme.ink2C)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if active, !editing {
                DeleteButton(theme: theme) { requestDelete(entry) }
            } else if !editing {
                Text(store.dayLabel(for: entry))
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.ink3C)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .padding(.leading, CGFloat(depth) * 14)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dropTarget
                    ? theme.activeBgC
                    : active
                    ? (entry.resolvedKind == .novel ? theme.novelBgC : theme.activeBgC)
                    : (hovered ? theme.hoverC : .clear))
        )
        // 드롭 "안으로"(= 두 저널을 새 폴더로 병합) 대상 표시 — 파란 링.
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(theme.blueC, lineWidth: 1.5)
            }
        }
        // 형제 사이 삽입선 — 행 위/아래 2pt 간격에 걸쳐 그린다.
        .overlay(alignment: .top) {
            if dragModel.indicator == .before(entry.id) {
                SidebarInsertionLine(theme: theme, depth: depth).offset(y: -2)
            }
        }
        .overlay(alignment: .bottom) {
            if dragModel.indicator == .after(entry.id) {
                SidebarInsertionLine(theme: theme, depth: depth).offset(y: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hoveredID = $0 ? entry.id : nil }
        // onTapGesture(count:2)+onTapGesture 조합은 단일 클릭이 더블클릭 판별
        // 타임아웃(수백 ms)을 기다린다 — 전환이 느려 보이는 주범. simultaneous로
        // 첫 탭에서 즉시 select하고, 두 번째 탭이 오면 그때 이름변경에 들어간다.
        .simultaneousGesture(TapGesture().onEnded { store.select(entry.id) })
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(entry) })
        .onDrag {
            // 이름 변경 중엔 드래그를 시작하지 않는다 — 빈 프로바이더를 돌려주면
            // 델리게이트들이 dragged==nil로 거부한다.
            guard editingID == nil else { return NSItemProvider() }
            dragModel.beginDrag(.entry(id: entry.id))
            return NSItemProvider(object: entry.id.uuidString as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: EntryRowDropDelegate(
                entry: entry, store: store, model: dragModel,
                requestNaming: { completion.requestFolderName(for: $0, in: store) }
            )
        )
        .contextMenu {
            Button("이름 바꾸기") { startRename(entry) }
            // 작성일 바꾸기 (L9) — 상단바 달력 버튼이 사라진 뒤의 유일한 진입점.
            // 저널마다 붙는 속성이라 앱 설정이 아니라 이 문맥 메뉴가 제자리다
            // (이름 바꾸기·종류 전환·내보내기와 같은 층).
            Button("작성일 바꾸기…") { promptForDate(entry) }
            moveMenu(for: entry)
            // 종류 전환 (M7 요청) — 원문 불변, 소설이 되면 이해 파이프라인이
            // 돌기 시작하고 저널이 되면 멈춘다 (지식은 파생이라 안전).
            if entry.resolvedKind == .novel {
                Button("일반 저널로 전환") { store.setKind(.journal, for: entry.id) }
            } else {
                Button("소설로 전환") { store.setKind(.novel, for: entry.id) }
            }
            // 소설만 — 전자책(EPUB)으로 내보내기 (요구 7).
            if entry.resolvedKind == .novel {
                Button("EPUB으로 내보내기…") { EpubExporter.exportWithPanel(entry) }
            }
            Button("삭제", role: .destructive) { requestDelete(entry) }
        }
    }

    /// 작성일 선택 — 문맥 메뉴에서 부르므로 SwiftUI 팝오버(앵커 없음) 대신
    /// NSAlert + NSDatePicker로 띄운다. 취소하면 아무것도 바꾸지 않는다.
    private func promptForDate(_ entry: JournalEntry) {
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = entry.createdAt

        let alert = NSAlert()
        alert.messageText = "작성일 바꾸기"
        alert.informativeText = "어제 일을 오늘 적었다면 날짜를 맞춰 두세요."
        alert.accessoryView = picker
        alert.addButton(withTitle: "바꾸기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.setDate(entry.id, to: picker.dateValue)
    }

    /// 저널을 다른 폴더/루트로 옮기는 문맥 메뉴 — 이미 만든 글도 정리할 수 있게 (M3).
    private func moveMenu(for entry: JournalEntry) -> some View {
        Menu("이동") {
            Button("루트로 이동") { store.move(entry.id, toFolder: nil) }
                .disabled(entry.folderID == nil)
            if !store.folders.isEmpty {
                Divider()
                ForEach(store.folders) { folder in
                    Button(folder.name) { store.move(entry.id, toFolder: folder.id) }
                        .disabled(entry.folderID == folder.id)
                }
            }
        }
    }

    // MARK: - 이름 변경

    private func startRename(_ entry: JournalEntry) {
        store.select(entry.id)
        draftTitle = entry.title
        editingID = entry.id
        // 필드가 뷰 트리에 붙은 다음 틱에 포커스를 준다.
        Task { renameFieldFocused = true }
    }

    private func startRenameFolder(_ folder: JournalFolder) {
        draftTitle = folder.name
        editingID = folder.id
        Task { renameFieldFocused = true }
    }

    private func commitRename(_ id: UUID) {
        if store.folders.contains(where: { $0.id == id }) {
            store.renameFolder(id, to: draftTitle)
        } else {
            store.rename(id, to: draftTitle)
        }
        editingID = nil
    }
}

/// 헤더의 아이콘 버튼 — hover 시 라운드 배경 (기존 ＋ 버튼 디테일 공유).
private struct HeaderIconButton<Label: View>: View {
    let theme: MintTheme
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(theme.ink2C)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// 폴더 행 hover 시 나타나는 작은 추가 버튼 (하위 폴더·저널).
private struct RowIconButton: View {
    let systemName: String
    let help: String
    let theme: MintTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? theme.inkC : theme.ink3C)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered ? theme.hoverC : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// 활성 행의 ✕ — hover 시 빨간 배경 (디자인).
private struct DeleteButton: View {
    let theme: MintTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 12))
                .foregroundStyle(hovered ? theme.dangerC : theme.ink3C)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered
                            ? theme.dangerC.opacity(0.14) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("이 저널 삭제")
    }
}
