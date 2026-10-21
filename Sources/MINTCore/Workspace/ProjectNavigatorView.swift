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
    var askSupport: AskMINTSupport?
    var judgeSupport: ContinuityJudgeSupport?
    weak var spatialWorkspace: SpatialWorkspaceController?
    weak var pouch: WorkspacePouchController?
    weak var registeredSession: ProjectSession?
    var pendingSpatialJump: (jump: EditorSearchJump, identity: ProjectRuntimeIdentity)?
    private final class EditorReference { weak var editor: BlockTextView?; init(_ editor: BlockTextView) { self.editor = editor } }
    private var editors: [ProjectDocumentKey: EditorReference] = [:]
    var workspaceHover: ((BlockTextView, ProjectDocumentKey, Int) -> Void)?
    var workspaceHoverEnd: (() -> Void)?
    var workspacePolish: ((BlockTextView) -> Void)?
    var workspaceExcerpt: ((BlockTextView) -> Void)?
    func register(_ editor: BlockTextView, for key: ProjectDocumentKey, session: ProjectSession? = nil) {
        editors = editors.filter { $0.value.editor != nil }
        editors[key] = EditorReference(editor)
        if let session {
            registeredSession = session
            installSpatialInteraction(editor, key: key, session: session)
            scheduleSpatialNavigation()
        }
    }
    func editor(for key: ProjectDocumentKey) -> BlockTextView? { editors[key]?.editor }
    var registeredEditors: [ProjectDocumentKey: BlockTextView] { editors.compactMapValues(\.editor) }
    func installSpatialInteraction(_ editor: BlockTextView, key: ProjectDocumentKey, session: ProjectSession) {
        guard let spatialWorkspace, key.projectID == session.activeProject?.id else { return }
        editor.workspaceFind = { [weak self, weak editor] action in
            guard let self, let spatial = self.spatialWorkspace else { return false }
            if action == .showFindInterface {
                var query: String?
                if let editor, !editor.hasMarkedText(), editor.selectedRange().length > 0,
                   editor.selectedRange().length <= 500 {
                    query = (editor.string as NSString).substring(with: editor.selectedRange())
                }
                spatial.openSearch(scope: .document, query: query)
            } else if action == .nextMatch || action == .previousMatch {
                if let advance = spatial.advanceSearch { advance(action == .nextMatch ? 1 : -1) }
                else { spatial.openSearch(scope: .document) }
            } else { return false }
            return true
        }
        if let existing = editor.workspaceInteraction as? WorkspaceEditorInteraction, existing.key == key { return }
        editor.workspaceInteraction = WorkspaceEditorInteraction(editor: editor, key: key,
            session: session, requests: self, model: spatialWorkspace)
        editor.updateTrackingAreas()
    }
    private var consumedSearchFocusRequest = 0

    public init() {}

    public func focusEditor() { editorFocusRequest += 1 }
    public func focusSearch() { searchFocusRequest += 1 }
    func consumeSearchFocusRequest() -> Bool {
        guard searchFocusRequest != consumedSearchFocusRequest else { return false }
        consumedSearchFocusRequest = searchFocusRequest
        return true
    }

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
        if let spatialWorkspace, let session = registeredSession {
            spatialWorkspace.open(documentID)
            if let identity = session.runtimeIdentity, identity.key.documentID == documentID, let searchJump {
                pendingSpatialJump = (searchJump, identity); scheduleSpatialNavigation()
            }
        }
        focusEditor()
    }
}

struct ProjectNavigatorView: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var editorRequests: ProjectEditorRequests
    let theme: MintTheme
    let onClose: () -> Void
    var spatial: SpatialWorkspaceController? = nil

    @State private var searchText = ""
    @State private var searchResults: [ProjectSearchResult] = []
    @State private var editingKey: ProjectDocumentKey?
    @State private var draftTitle = ""
    @State private var showingTrash = false
    @State private var searchVisible = false
    @State private var hoveredDocument: WritingDocumentID?
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
            if spatial == nil || searchVisible { searchField }
            if let error = session.lastErrorMessage {
                Text(error)
                    .mintUIFont(11)
                    .foregroundStyle(theme.dangerC)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                theme.sepC.frame(height: 1)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: spatial == nil ? 2 : 4) {
                    if isSearching { searchRows } else { documentRows }
                }
                .padding(spatial == nil ? 8 : 6)
            }
        }
        .background(theme.cardSurfaceC)
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
        .task(id: editorRequests.searchFocusRequest) { await focusSearchIfRequested() }
        .onChange(of: editorRequests.renameRequest) { _, _ in
            if let document = session.selectedDocument { startRename(document) }
        }
        .onChange(of: renameFocused) { _, focused in
            if !focused { commitRename() }
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused && !isSearching { searchVisible = false }
        }
        .sheet(isPresented: $showingTrash) {
            ProjectTrashView(
                documents: trashedDocuments,
                theme: theme,
                onRestore: { ProjectCommandActions(session: session).restoreDocument($0) })
        }
    }

    private func focusSearchIfRequested() async {
        guard editorRequests.consumeSearchFocusRequest() else { return }
        searchVisible = true
        let projectID = session.activeProject?.id
        // Apply focus after native field insertion; an onAppear request can be lost.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        guard !Task.isCancelled, session.activeProject?.id == projectID else { return }
        searchFocused = true
    }

    private var header: some View {
        if spatial != nil {
            return AnyView(SpatialTileHeader(tile: .navigator, title: "문서", theme: theme, actions: [
                SpatialHeaderAction(id: "mint.navigator.new", label: "새 문서", symbol: "plus") {
                    ProjectCommandActions(session: session).newDocument(.manuscript); editorRequests.focusEditor()
                },
                SpatialHeaderAction(id: "mint.navigator.close", label: "파일 목록 숨기기", symbol: "xmark", perform: onClose)
            ]).frame(height: 32).contextMenu {
                Button("프로젝트 검색") { spatial?.openSearch() }
                ForEach(session.recentProjects) { recent in
                    Button(recent.title) { Task { try? await session.activateProject(id: recent.id); editorRequests.focusEditor() } }
                }
                if !trashedDocuments.isEmpty { Button("휴지통") { showingTrash = true } }
            }.opacity(spatial?.whisperTyping == true ? 0.08 : 1)
                .animation(WorkspaceHTMLStyle.animation(0.32), value: spatial?.whisperTyping))
        }
        return AnyView(legacyHeader)
    }

    private var legacyHeader: some View {
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
            WorkspaceActionButton(identifier: "mint.navigator.close", label: "파일 목록 숨기기",
                symbol: "xmark", theme: theme, action: onClose).frame(width: 32, height: 32)
        }
        .foregroundStyle(theme.ink2C)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(height: 36)
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
                Text(session.activeProject?.title ?? "프로젝트")
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .mintUIFont(11.5, .medium)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("최근 프로젝트")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.workspaceMutedC)
            TextField("프로젝트 검색", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityIdentifier("mint.navigator.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.workspaceMutedC)
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
                .foregroundStyle(theme.workspaceMutedC)
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
                                .foregroundStyle(theme.workspaceMutedC)
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
        let editingName = editingKey == documentKey(for: document)
        return HStack(spacing: 8) {
            if let spatial {
                Circle().fill(selected ? theme.inkC : theme.ink2C)
                    .opacity(spatial.layout.contains(.document(document.id)) ? 0.75 : 0.20)
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: document.kind == .manuscript ? "doc.text" : "note.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? theme.blueC : theme.workspaceMutedC)
            }
            if editingName {
                TextField("문서 이름", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .accessibilityIdentifier("mint.navigator.rename")
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(document.title)
                    .mintUIFont(spatial == nil ? 12 : 11.5, selected ? .medium : .regular)
                    .foregroundStyle(selected ? theme.inkC : theme.ink2C)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let spatial, !editingName {
                let open = spatial.layout.contains(.document(document.id))
                if open && spatial.layout.openDocuments.count == 1 {
                    Text("열림").font(MintFonts.monoUI(9.5)).foregroundStyle(theme.workspaceMutedC)
                } else if open {
                    WorkspaceActionButton(identifier: "mint.navigator.tile.\(document.id.rawValue.uuidString)",
                        label: "이 문서 창 닫기", symbol: "xmark", theme: theme) {
                        _ = spatial.close(.document(document.id)); editorRequests.focusEditor()
                    }.frame(width: 16, height: 16).opacity(hoveredDocument == document.id ? 1 : 0)
                } else {
                    WorkspaceTextAction(title: "열기", identifier: "mint.navigator.tile.\(document.id.rawValue.uuidString)", theme: theme) {
                        spatial.open(document.id); editorRequests.focusEditor()
                    }.frame(width: 30, height: 16).opacity(hoveredDocument == document.id ? 1 : 0)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                .fill(selected ? theme.activeBgC : (hoveredDocument == document.id ? theme.hoverC : .clear)))
        .onHover { hoveredDocument = $0 ? document.id : nil }
        .animation(WorkspaceHTMLStyle.animation(0.20), value: hoveredDocument)
        .animation(WorkspaceHTMLStyle.animation(0.24), value: spatial?.navigatorDrop)
        .overlay {
            if spatial != nil && !editingName {
                SpatialNavigatorDragRegion(documentID: document.id) {
                    spatial?.open(document.id)
                }.padding(.trailing, 28)
            }
        }
        .padding(.top, spatial?.navigatorDrop?.target == document.id && spatial?.navigatorDrop?.after == false ? 14 : 0)
        .padding(.bottom, spatial?.navigatorDrop?.target == document.id && spatial?.navigatorDrop?.after == true ? 14 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editingName else { return }
            if let spatial { spatial.open(document.id) } else { session.selectDocument(document.id) }
            editorRequests.focusEditor()
        }
        .accessibilityElement(children: editingName ? .contain : .combine)
        .accessibilityIdentifier("mint.document.\(document.id.rawValue.uuidString)")
        .accessibilityLabel(Text(document.title))
        .accessibilityAddTraits(editingName ? [] : .isButton)
        .accessibilityAction {
            guard !editingName else { return }
            if let spatial { spatial.open(document.id) } else { session.selectDocument(document.id) }
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
                Text("휴지통이 비어 있어요").foregroundStyle(theme.workspaceMutedC)
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
