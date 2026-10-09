import SwiftUI

/// Transient editor requests shared by the project workspace and menu commands. Manuscript
/// state remains exclusively owned by `ProjectSession`.
@MainActor
public final class ProjectEditorRequests: ObservableObject {
    @Published public private(set) var editorFocusRequest = 0
    @Published public private(set) var searchFocusRequest = 0
    @Published public private(set) var renameRequest = 0
    @Published public internal(set) var searchJump: EditorSearchJump?
    @Published internal var sourceReturnPoint: SourceWritingPosition?
    @Published internal var sourceNavigationError: String?
    weak var nativeEditor: BlockTextView?
    var nativeEditorKey: ProjectDocumentKey?

    public init() {}

    public func focusEditor() { editorFocusRequest += 1 }
    public func focusSearch() { searchFocusRequest += 1 }
    public func beginRename() { renameRequest += 1 }

    public func jump(to result: ProjectSearchResult, in session: ProjectSession) {
        guard let project = session.activeProject,
            project.id == result.projectID,
            !project.trashedDocumentIDs.contains(result.documentID),
            project.documents.contains(where: { $0.id == result.documentID })
        else { return }
        session.selectDocument(result.documentID)
        issueJump(documentID: result.documentID, query: result.query)
    }

    public func issueJump(documentID: WritingDocumentID, query: String) {
        searchJump = EditorSearchJump(
            documentID: documentID,
            query: query,
            sequence: (searchJump?.sequence ?? 0) + 1)
        focusEditor()
    }
}

struct ProjectNavigatorView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var editorRequests: ProjectEditorRequests
    let theme: MintTheme

    @State private var searchText = ""
    @State private var searchResults: [ProjectSearchResult] = []
    @State private var editingKey: ProjectDocumentKey?
    @State private var draftTitle = ""
    @State private var showingTrash = false
    @FocusState private var searchFocused: Bool
    @FocusState private var renameFocused: Bool

    private var visibleDocuments: [WritingDocument] {
        guard let project = session.activeProject else { return [] }
        return project.documents.filter { !project.trashedDocumentIDs.contains($0.id) }
    }

    private var trashedDocuments: [WritingDocument] {
        guard let project = session.activeProject else { return [] }
        return project.documents.filter { project.trashedDocumentIDs.contains($0.id) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            theme.sepC.frame(height: 1)
            searchField
            theme.sepC.frame(height: 1)
            if let error = session.lastErrorMessage {
                Text(error)
                    .mintUIFont(11)
                    .foregroundStyle(theme.dangerC)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                theme.sepC.frame(height: 1)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if isSearching { searchRows } else { documentRows }
                }
                .padding(8)
            }
        }
        .background(theme.sidebarTintC)
        .overlay(alignment: .trailing) { theme.sepC.frame(width: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mint.navigator")
        .accessibilityLabel("문서 탐색기")
        .task(id: searchTaskID) {
            guard isSearching, let project = session.activeProject else {
                searchResults = []
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let snapshot = project
            let query = searchText
            let results = await Task.detached(priority: .userInitiated) {
                ProjectSearch.results(query: query, in: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            searchResults = results
        }
        .onChange(of: editorRequests.searchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: editorRequests.renameRequest) { _, _ in
            if let document = session.selectedDocument { startRename(document) }
        }
        .onChange(of: renameFocused) { _, focused in
            if !focused { commitRename() }
        }
        .sheet(isPresented: $showingTrash) {
            ProjectTrashView(
                documents: trashedDocuments,
                theme: theme,
                onRestore: { ProjectCommandActions(session: session).restoreDocument($0) })
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            recentProjectsMenu
            Spacer(minLength: 8)
            Button {
                ProjectCommandActions(session: session).newDocument(.manuscript)
                editorRequests.focusEditor()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("새 문서")
            .accessibilityLabel("새 문서")

            if !trashedDocuments.isEmpty {
                Button { showingTrash = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .help("휴지통")
                    .accessibilityLabel("휴지통")
            }
        }
        .foregroundStyle(theme.ink2C)
        .padding(.leading, 74)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    private var recentProjectsMenu: some View {
        Menu {
            if session.recentProjects.isEmpty {
                Text("최근 프로젝트 없음")
            } else {
                ForEach(session.recentProjects) { recent in
                    Button {
                        Task {
                            do {
                                try await session.activateProject(id: recent.id)
                                editorRequests.focusEditor()
                            } catch {
                                // ProjectSession keeps the current owner and publishes the error.
                            }
                        }
                    } label: {
                        Text(recent.title)
                        if recent.id == session.activeProject?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(session.activeProject?.title ?? "프로젝트").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .mintUIFont(12, .semibold)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("최근 프로젝트")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.ink3C)
            TextField("프로젝트 검색", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.ink3C)
            }
        }
        .mintUIFont(12)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous).fill(theme.chipC))
        .overlay(
            RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                .strokeBorder(theme.chipBorderC))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var documentRows: some View {
        ForEach(visibleDocuments) { document in documentRow(document) }
    }

    @ViewBuilder
    private var searchRows: some View {
        if searchResults.isEmpty {
            Text("일치하는 문서가 없어요")
                .mintUIFont(12)
                .foregroundStyle(theme.ink3C)
                .padding(8)
        } else {
            ForEach(searchResults) { result in
                Button { editorRequests.jump(to: result, in: session) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title)
                            .mintUIFont(13, .semibold)
                            .foregroundStyle(theme.ink2C)
                            .lineLimit(1)
                        if let snippet = result.snippet {
                            Text(snippet)
                                .mintUIFont(11.5)
                                .foregroundStyle(theme.ink3C)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func documentRow(_ document: WritingDocument) -> some View {
        let selected = document.id == session.selectedDocumentID
        return HStack(spacing: 8) {
            Image(systemName: document.kind == .manuscript ? "doc.text" : "note.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? theme.blueC : theme.ink3C)
            if editingKey == documentKey(for: document) {
                TextField("문서 이름", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(document.title)
                    .mintUIFont(13, selected ? .semibold : .regular)
                    .foregroundStyle(selected ? theme.inkC : theme.ink2C)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                .fill(selected ? theme.activeBgC : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectDocument(document.id)
            editorRequests.focusEditor()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mint.document.\(document.id.rawValue.uuidString)")
        .accessibilityLabel(Text(document.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            session.selectDocument(document.id)
            editorRequests.focusEditor()
        }
        .contextMenu {
            Button("이름 바꾸기") { startRename(document) }
            Button("휴지통으로 이동", role: .destructive) {
                session.selectDocument(document.id)
                ProjectCommandActions(session: session).trashDocument()
                editorRequests.focusEditor()
            }
        }
    }

    private var searchTaskID: String {
        "\(session.runtimeIdentity?.generation ?? 0):\(searchText)"
    }

    private func startRename(_ document: WritingDocument) {
        guard let key = documentKey(for: document) else { return }
        editingKey = key
        draftTitle = document.title
        renameFocused = true
    }

    private func commitRename() {
        guard let editingKey else { return }
        session.renameDocument(editingKey, to: draftTitle)
        self.editingKey = nil
    }

    private func cancelRename() {
        editingKey = nil
        renameFocused = false
    }

    private func documentKey(for document: WritingDocument) -> ProjectDocumentKey? {
        guard let projectID = session.activeProject?.id else { return nil }
        return ProjectDocumentKey(projectID: projectID, documentID: document.id)
    }
}

private struct ProjectTrashView: View {
    let documents: [WritingDocument]
    let theme: MintTheme
    let onRestore: (WritingDocumentID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("휴지통").mintUIFont(15, .semibold)
                Spacer()
                Button("닫기") { dismiss() }
            }
            ForEach(documents) { document in
                HStack {
                    Text(document.title)
                    Spacer()
                    Button("복원") { onRestore(document.id) }
                }
            }
            if documents.isEmpty {
                Text("휴지통이 비어 있어요").foregroundStyle(theme.ink3C)
            }
            Spacer(minLength: 0)
        }
        .mintUIFont(12)
        .foregroundStyle(theme.inkC)
        .padding(18)
        .frame(minWidth: 360, minHeight: 240)
        .background(theme.sidebarTintC)
    }
}
