import AppKit
import SwiftUI

/// 좌측 저널 사이드바 (에디터 v3 — 디자인 이식, 파일시스템 v1).
///
/// 상단: 신호등 옆을 채우는 52px 헤더(우측 날짜 툴바와 같은 높이) —
/// "MINT"(세리프) + 새 폴더(폴더＋) + 새 저널(＋).
/// 목록: 폴더 트리(펼침/접힘, hover 시 하위 폴더·저널 추가) + 저널 행.
struct SidebarView: View {
    @ObservedObject var store: EntryStore
    let theme: MintTheme

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
        VStack(alignment: .leading, spacing: 0) {
            header
            theme.sepC.frame(height: 1)
            searchField
            theme.sepC.frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    if isSearching {
                        searchResults
                    } else {
                        ForEach(items) { item in
                            switch item {
                            case .folder(let folder, let depth):
                                folderRow(folder, depth: depth)
                            case .entry(let entry, let depth):
                                row(entry, depth: depth)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .background(theme.sidebarTintC)
        .overlay(alignment: .trailing) { theme.sepC.frame(width: 1) }
        .onChange(of: renameFieldFocused) { _, focused in
            // Enter(onSubmit) 외에 포커스를 잃어도 커밋 — Esc는 editingID를
            // 먼저 비우므로 여기 걸리지 않는다.
            if !focused, let id = editingID { commitRename(id) }
        }
        .onChange(of: store.searchFocusRequests) { _, _ in
            // ⌘⇧F — 검색 필드로 포커스.
            searchFieldFocused = true
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

    // MARK: - 트리 평탄화

    private enum SidebarItem: Identifiable {
        case folder(JournalFolder, depth: Int)
        case entry(JournalEntry, depth: Int)

        var id: UUID {
            switch self {
            case .folder(let folder, _): folder.id
            case .entry(let entry, _): entry.id
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
        HStack(spacing: 2) {
            Text("MINT")
                .font(MintFonts.serifUI(19, .semibold))
                .foregroundStyle(theme.inkC)
            Spacer(minLength: 4)
            HeaderIconButton(theme: theme, help: "새 폴더") {
                store.newFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13.5, weight: .medium))
            }
            HeaderIconButton(theme: theme, help: "새 저널") {
                store.newEntry()
            } label: {
                Text("＋").font(.system(size: 19))
            }
        }
        // 신호등 줄(타이틀바 안전영역) 바로 아래 — 우측 툴바(52px)와 같은
        // 높이라 날짜 줄과 헤더 줄이 한 줄로 이어진다.
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 52)
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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.chipC))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.chipBorderC))
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
            store.select(entry.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
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
                    .fill(active ? theme.activeBgC : .clear))
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
        var text = String(body[start..<end])
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
                .fill(hovered ? theme.hoverC : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hoveredID = $0 ? folder.id : nil }
        // 저널 행과 같은 이유 — 첫 탭 즉시 펼침/접힘 (더블탭이 오면 두 번
        // 토글돼 원상복구된 채 이름변경으로 들어간다).
        .simultaneousGesture(TapGesture().onEnded { store.toggleExpanded(folder.id) })
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRenameFolder(folder) })
        .contextMenu {
            Button("새 저널") { store.newEntry(in: folder.id) }
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

        HStack(spacing: 11) {
            Circle()
                .fill(active ? theme.blueC : theme.ink3C)
                .frame(width: 7, height: 7)

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
                Text(entry.title)
                    .font(MintFonts.uiFont(13, active ? .semibold : .medium))
                    .foregroundStyle(active ? theme.inkC : theme.ink2C)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if active && !editing {
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
                .fill(active ? theme.activeBgC : (hovered ? theme.hoverC : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hoveredID = $0 ? entry.id : nil }
        // onTapGesture(count:2)+onTapGesture 조합은 단일 클릭이 더블클릭 판별
        // 타임아웃(수백 ms)을 기다린다 — 전환이 느려 보이는 주범. simultaneous로
        // 첫 탭에서 즉시 select하고, 두 번째 탭이 오면 그때 이름변경에 들어간다.
        .simultaneousGesture(TapGesture().onEnded { store.select(entry.id) })
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(entry) })
        .contextMenu {
            Button("이름 바꾸기") { startRename(entry) }
            Button("삭제", role: .destructive) { requestDelete(entry) }
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
                .foregroundStyle(hovered ? Color(nsColor: NSColor(hex: 0xFF453A)) : theme.ink3C)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered
                            ? Color(nsColor: NSColor(hex: 0xFF453A, alpha: 0.14)) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("이 저널 삭제")
    }
}
