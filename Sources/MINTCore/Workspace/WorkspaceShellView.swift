import SwiftUI

enum WorkspaceMotion {
    static let navigator = Animation.spring(response: 0.3, dampingFraction: 0.9)
}

/// The shell owns presentation only; document lifetime, storage and indexing belong to the session.
struct WorkspaceShellView<Navigator: View, Editor: View, Context: View, Rail: View>: View {
    @Binding var navigatorWidth: Double
    let presentation: WorkspacePresentationState
    let onNavigatorCollapse: () -> Void
    let railWidth: CGFloat
    let theme: MintTheme
    @ViewBuilder var navigator: () -> Navigator
    @ViewBuilder var editor: () -> Editor
    @ViewBuilder var context: () -> Context
    @ViewBuilder var rail: () -> Rail
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.mintWorkspaceAccessibilityOptions) private var accessibilityOptions
    @State private var navigatorDragProjectedWidth: CGFloat?
    private var reduceMotion: Bool { systemReduceMotion || accessibilityOptions.reduceMotion }

    var body: some View {
        GeometryReader { geometry in
            let layout = WorkspaceLayoutPolicy.resolve(availableWidth: geometry.size.width,
                presentation: presentation, railWidth: railWidth,
                projectedNavigatorWidth: navigatorDragProjectedWidth)
            let contextVisible = presentation.contextVisible
            let effectiveDock = layout.toolDock
            let height = max(0, geometry.size.height - 2 * WorkspaceLayoutPolicy.outerInset)
            let railReservation = railWidth > 0 ? railWidth + WorkspaceLayoutPolicy.surfaceGap : 0
            let navigatorLeading = WorkspaceLayoutPolicy.outerInset + railReservation
                + (layout.navigatorPlacement == .overlay && contextVisible && effectiveDock == .left
                    ? WorkspaceLayoutState.toolWidth + WorkspaceLayoutPolicy.toolSeparatorWidth : 0)

            HStack(spacing: 0) {
                if railWidth > 0 {
                    rail().frame(width: railWidth)
                    Color.clear.frame(width: WorkspaceLayoutPolicy.surfaceGap)
                }
                // This allocation changes width; the actual navigator keeps one overlay slot.
                Color.clear.frame(width: layout.navigatorReservation)
                HStack(spacing: 0) {
                    if contextVisible && effectiveDock == .left {
                        context().frame(width: WorkspaceLayoutState.toolWidth)
                            .background(WorkspaceToolSurface(theme: theme, floating: false))
                            .clipShape(RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous))
                        Color.clear.frame(width: WorkspaceLayoutPolicy.toolSeparatorWidth)
                    }
                    VStack(spacing: 0) {
                        WorkspaceFrame(theme: theme) {
                            editor().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if contextVisible && effectiveDock == .bottom {
                            Color.clear.frame(height: WorkspaceLayoutPolicy.surfaceGap)
                            context().frame(height: min(WorkspaceLayoutState.bottomToolMaxHeight, height * 0.4))
                                .background(WorkspaceToolSurface(theme: theme, floating: false))
                                .clipShape(RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous))
                        }
                    }
                    .frame(width: layout.manuscriptWidth, height: height)
                    if contextVisible && effectiveDock == .right {
                        Color.clear.frame(width: WorkspaceLayoutPolicy.toolSeparatorWidth)
                        context().frame(width: WorkspaceLayoutState.toolWidth)
                            .background(WorkspaceToolSurface(theme: theme, floating: false))
                            .clipShape(RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(WorkspaceLayoutPolicy.outerInset)
            .overlay(alignment: .topLeading) {
                if presentation.navigatorVisible {
                    navigator()
                        .frame(width: layout.navigatorWidth, height: height)
                        .opacity(navigatorDragOpacity)
                        .background(theme.cardSurfaceC)
                        .clipShape(RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous))
                        .offset(x: navigatorLeading, y: WorkspaceLayoutPolicy.outerInset)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if presentation.navigatorVisible {
                    SidebarResizeDivider(
                        width: Binding(get: { layout.navigatorWidth }, set: { navigatorWidth = Double($0) }),
                        minWidth: WorkspaceLayoutState.navigatorMinWidth,
                        maxWidth: max(WorkspaceLayoutState.navigatorMinWidth, layout.navigatorMaximumWidth),
                        collapseThreshold: WorkspaceLayoutState.navigatorCollapseThreshold,
                        collapseReleaseThreshold: WorkspaceLayoutState.navigatorCollapseReleaseThreshold,
                        onCollapse: { settleNavigatorDrag(collapse: true) },
                        onDragPreview: { navigatorDragProjectedWidth = $0 },
                        onDragSettled: { settleNavigatorDrag(collapse: false) }, theme: theme)
                        .frame(width: 24, height: height)
                        .offset(x: navigatorLeading + layout.navigatorWidth - 12,
                                y: WorkspaceLayoutPolicy.outerInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                if contextVisible && effectiveDock == .floating {
                    context()
                        .frame(width: WorkspaceLayoutState.toolWidth,
                            height: min(WorkspaceLayoutState.floatingToolMaxHeight, max(240, geometry.size.height - 36)))
                        .background(WorkspaceToolSurface(theme: theme, floating: true))
                        .clipShape(RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous))
                        .shadow(color: .black.opacity(MintElevation.floating.opacity),
                            radius: MintElevation.floating.radius, y: MintElevation.floating.y)
                        .padding(18)
                }
            }
        }
        .background(theme.workspaceSurfaceC)
    }

    private var navigatorDragOpacity: Double {
        guard let projectedWidth = navigatorDragProjectedWidth else { return 1 }
        let collapseRange =
            WorkspaceLayoutState.navigatorMinWidth
            - WorkspaceLayoutState.navigatorCollapseThreshold
        let progress = min(
            1,
            max(
                0,
                (WorkspaceLayoutState.navigatorMinWidth - projectedWidth) / collapseRange))
        return 1 - Double(progress) * 0.2
    }

    private func settleNavigatorDrag(collapse: Bool) {
        withAnimation(reduceMotion ? nil : WorkspaceMotion.navigator) {
            navigatorDragProjectedWidth = nil
            if collapse {
                onNavigatorCollapse()
            }
        }
    }
}

struct WorkspaceChromeSurface: View {
    let theme: MintTheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.mintWorkspaceAccessibilityOptions) private var accessibilityOptions

    var body: some View {
        if systemReduceTransparency || accessibilityOptions.reduceTransparency {
            theme.workspaceSurfaceC
        } else {
            Rectangle().fill(.thinMaterial).overlay(theme.toolbarC)
        }
    }
}

struct WorkspaceToolSurface: View {
    let theme: MintTheme
    let floating: Bool
    var body: some View {
        WorkspacePaperSurface(theme: theme, identifier: "mint.workspace.tool",
            surface: floating ? theme.pill.withAlphaComponent(1) : theme.cardSurface)
    }
}

/// Connects the workspace directly to the sole mutable project owner.
struct WorkspaceSurface: View {
    @ObservedObject var projectSession: ProjectSession
    @ObservedObject var editorRequests: ProjectEditorRequests
    @ObservedObject var completion: CompletionController
    @ObservedObject var livingMargin: LivingMarginModel
    let indexer: BackgroundIndexer
    var editorBridge: ProjectEditorBridge? = nil
    var positionStore: WritingPositionStore = .shared
    var writingDiagnostics: WritingDiagnosticsRuntime? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @StateObject private var palette = PaletteSettings.shared
    @StateObject private var outline = DocumentOutlineController()
    @StateObject private var spatial = SpatialWorkspaceController()
    @State private var marginOpened = false
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @AppStorage("mint.sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage("mint.sidebarSection") private var section = SidebarSection.files.rawValue
    @AppStorage("mint.toolDockPosition")
    private var toolDockRaw = ToolDockPosition.automatic.rawValue
    @AppStorage("mint.chromeHidden") private var chromeHidden = false

    var body: some View {
        let theme = palette.theme(for: colorScheme)
        let presentation = WorkspacePresentationState(navigatorVisible: sidebarVisible,
            navigatorWidth: sidebarWidth, rawToolSection: section,
            rawToolDock: toolDockRaw, chromeHidden: chromeHidden, outlineVisible: outlineVisible,
            marginVisible: marginVisible, mapVisible: mapVisible)
        VStack(spacing: 0) {
            WorkspaceWindowChrome(projectTitle: projectSession.activeProject?.title ?? "프로젝트", theme: theme)
            spatialWorkspace(theme: theme)
        }
        .tint(theme.blueC)
        .ignoresSafeArea(.container, edges: .top)
        .task(id: projectSession.runtimeIdentity) {
            outline.update(activeWritingMode == .general ? projectSession.selectedDocumentSnapshot : nil)
        }
        .onAppear {
            configureSpatial()
            completion.observeForegroundCompletion(owner: outline) { [weak outline] busy in
                outline?.setForegroundBusy(busy)
            }
        }
        .onDisappear { outline.stop() }
        .onChange(of: projectSession.selectedDocumentID) { _, _ in configureSpatial() }
        .onChange(of: projectSession.activeProject?.id) { _, _ in configureSpatial() }
        .onChange(of: projectSession.activeProject?.trashedDocumentIDs) { _, _ in configureSpatial() }
        .onChange(of: section) { _, value in
            let tile: WorkspaceTileID?
            switch value {
            case SidebarSection.bible.rawValue: tile = .characters
            case SidebarSection.narrative.rawValue: tile = .narrative
            case SidebarSection.context.rawValue: tile = .context
            case SidebarSection.margin.rawValue: tile = .margin
            default: tile = nil
            }
            if let tile, !spatial.layout.contains(tile) { spatial.toggle(tile) }
        }
        .onChange(of: sidebarVisible) { _, value in
            if spatial.layout.contains(.navigator) != value { spatial.toggle(.navigator) }
        }
        .onChange(of: projectSession.workspaceMode) { _, mode in
            if mode == .map && !spatial.layout.contains(.map) { spatial.toggle(.map) }
            if mode == .outline && !spatial.layout.contains(.outline) { spatial.toggle(.outline) }
        }
        .onChange(of: outline.prepared) { _, prepared in
            updateOutlinePosition(identity: prepared?.identity)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { notification in
            guard let editor = notification.object as? BlockTextView, editor === editorRequests.nativeEditor else { return }
            updateOutlinePosition(identity: projectSession.runtimeIdentity)
        }
        .onChange(of: section) { _, _ in
            if outlineVisible || mapVisible { projectSession.selectWorkspaceMode(.write) }
            if section != SidebarSection.margin.rawValue { marginOpened = false }
        }
        .onChange(of: projectSession.runtimeIdentity?.key.projectID) { _, _ in marginOpened = false }
    }

    private func configureSpatial() {
        guard let project = projectSession.activeProject else { return }
        spatial.configure(project: project, selected: projectSession.selectedDocumentID,
            defaults: projectSession.presentationPreferences)
        editorRequests.spatialWorkspace = spatial
        spatial.onActivate = { [weak projectSession, weak editorRequests] id in
            projectSession?.selectDocument(id); editorRequests?.focusEditor()
        }
        spatial.onCommit = { [weak projectSession] layout in
            guard let project = projectSession?.activeProject else { return }
            projectSession?.reorderDocuments(layout.reorderedDocuments(project.documents.map(\.id)), projectID: project.id)
            if let selected = projectSession?.selectedDocumentID, !layout.openDocuments.contains(selected),
               let next = layout.openDocuments.first { projectSession?.selectDocument(next) }
        }
        spatial.onNavigationOrder = { [weak projectSession] order in
            guard let project = projectSession?.activeProject else { return }
            var next = order.makeIterator()
            let ids = project.documents.map { document in
                project.trashedDocumentIDs.contains(document.id) ? document.id : (next.next() ?? document.id)
            }
            projectSession?.reorderDocuments(ids, projectID: project.id)
        }
        let stored: WorkspaceTileID?
        switch section {
        case SidebarSection.bible.rawValue: stored = .characters
        case SidebarSection.narrative.rawValue: stored = .narrative
        case SidebarSection.context.rawValue: stored = .context
        default: stored = nil
        }
        if let stored, !spatial.layout.contains(stored) { spatial.toggle(stored) }
    }

    private func spatialWorkspace(theme: MintTheme) -> some View {
        SpatialWorkspaceCanvas(model: spatial, theme: theme) { tile in
            switch tile {
            case .document(let id):
                return AnyView(SpatialDocumentTile(session: projectSession, requests: editorRequests,
                    completion: completion, model: spatial, documentID: id, theme: theme,
                    editorBridge: editorBridge, positionStore: positionStore))
            case .navigator:
                return AnyView(SpatialNavigatorPane(session: projectSession, requests: editorRequests, model: spatial,
                    theme: theme, onClose: { spatial.toggle(.navigator); sidebarVisible = false; editorRequests.focusEditor() }))
            default:
                return AnyView(spatialTool(tile, theme: theme))
            }
        }
        .background(theme.workspaceSurfaceC)
        .overlay(alignment: .leading) {
            WorkspaceRail(navigatorVisible: $sidebarVisible, section: $section,
                session: projectSession, requests: editorRequests, theme: theme,
                openSettings: { openSettings() }, onShowLivingMargin: { spatial.toggle(.margin) },
                marginSelected: spatial.layout.contains(.margin))
                .fixedSize().padding(.leading, 8)
        }
    }

    private func spatialTool(_ tile: WorkspaceTileID, theme: MintTheme) -> some View {
        VStack(spacing: 0) {
            SpatialTileHeader(tile: tile, title: spatialToolTitle(tile), theme: theme, actions: [
                SpatialHeaderAction(id: "mint.tile.close.\(tile.id)", label: "주머니에 넣기", symbol: "xmark") {
                    _ = spatial.close(tile)
                    if tile == .map || tile == .outline { projectSession.selectWorkspaceMode(.write) }
                    editorRequests.focusEditor()
                }
            ]).frame(height: 32)
            Group {
                switch tile {
                case .margin: livingMarginPanel(theme: theme)
                case .map:
                    StoryMapWorkspacePanel(session: projectSession, indexer: indexer, completion: completion,
                        requests: editorRequests, theme: theme)
                case .outline:
                    DocumentOutlineView(controller: outline, requests: editorRequests, session: projectSession, theme: theme)
                default:
                    ProjectWriterToolsView(session: projectSession, completion: completion, editorRequests: editorRequests,
                        section: tile == .characters ? .bible : (tile == .narrative ? .narrative : .context), theme: theme)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(theme.cardSurfaceC)
            .clipShape(RoundedRectangle(cornerRadius: MintRadius.lg))
    }

    private func spatialToolTitle(_ tile: WorkspaceTileID) -> String {
        switch tile {
        case .characters: "인물"
        case .narrative: "서사 흐름"
        case .margin: "마진 노트"
        case .map: "이야기 지도"
        case .outline: "문서 개요"
        case .review: "검토"
        default: "참고 기록"
        }
    }

    private var outlineVisible: Bool {
        activeWritingMode == .general && projectSession.workspaceMode == .outline
    }
    private var mapVisible: Bool { activeWritingMode == .fiction && projectSession.workspaceMode == .map }
    private var marginAvailable: Bool {
        writingDiagnostics != nil || marginOpened || !livingMargin.visibleInsights(for: activeWritingMode).isEmpty
    }
    private var marginVisible: Bool {
        marginOpened && section == SidebarSection.margin.rawValue && !outlineVisible && !mapVisible
    }
    private func toggleMargin() {
        if marginVisible {
            marginOpened = false; WorkspaceToolSelection.hide(currentSection: &section)
        } else {
            projectSession.selectWorkspaceMode(.write)
            WorkspaceToolSelection.showLivingMargin(currentSection: &section); marginOpened = true
        }
        editorRequests.focusEditor()
    }

    private func updateOutlinePosition(identity: ProjectRuntimeIdentity?) {
        let offset = identity.flatMap { editorRequests.nativeEditor?.outlineSourcePosition(identity: $0) }
        outline.notePosition(offset, identity: identity)
    }

    private func workspace(presentation: WorkspacePresentationState, theme: MintTheme) -> some View {
        WorkspaceShellView(
            navigatorWidth: $sidebarWidth,
            presentation: presentation,
            onNavigatorCollapse: hideNavigator,
            railWidth: WorkspaceLayoutPolicy.railWidth,
            theme: theme
        ) {
            ProjectNavigatorView(
                session: projectSession,
                editorRequests: editorRequests,
                theme: theme, onClose: hideNavigator)
        } editor: {
            EditorPane(
                projectSession: projectSession,
                editorRequests: editorRequests,
                completion: completion,
                settings: completion.settings,
                theme: theme,
                editorBridge: editorBridge,
                positionStore: positionStore)
        } context: {
            let tool = mapVisible
                ? WorkspaceToolDescriptor(title: "이야기 지도", subtitle: "장면과 사건을 원문에서 살펴보기", systemImage: "point.3.connected.trianglepath.dotted")
                : (outlineVisible
                    ? WorkspaceToolDescriptor(title: "문서 개요", subtitle: "원고의 제목과 현재 위치", systemImage: "list.bullet.indent")
                    : WorkspaceToolPresentation.descriptor(for: section))
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(theme.ink3C)
                        .accessibilityHidden(true)
                    Text(tool.title)
                        .mintUIFont(11.5, .medium)
                        .foregroundStyle(theme.ink2C)
                        .lineLimit(1)
                        .help(tool.subtitle)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(ToolDockPosition.allCases, id: \.self) { position in
                            Button {
                                toolDockRaw = position.rawValue
                                editorRequests.focusEditor()
                            } label: {
                                Label(position.label, systemImage: position.systemImage)
                                if presentation.toolDock == position {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.3.group")
                            .mintUIFont(12)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("글 도구 위치")
                    .help("글 도구 위치")
                    Group {
                        if mapVisible {
                            WorkspaceActionButton(identifier: "mint.story-map.close", label: "문서로 돌아가기",
                                symbol: "xmark", theme: theme) {
                                    projectSession.selectWorkspaceMode(.write); editorRequests.focusEditor()
                                }.frame(width: 26, height: 26)
                        } else {
                            Button {
                                if outlineVisible { projectSession.selectWorkspaceMode(.write) }
                                else { marginOpened = false; WorkspaceToolSelection.hide(currentSection: &section) }
                                editorRequests.focusEditor()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.ink2C)
                    .accessibilityIdentifier(mapVisible ? "mint.story-map.close" : "mint.context.close")
                    .accessibilityLabel("문서로 돌아가기")
                    .help("문서로 돌아가기")
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                if mapVisible {
                    StoryMapWorkspacePanel(session: projectSession, indexer: indexer, completion: completion,
                        requests: editorRequests, theme: theme)
                } else if outlineVisible {
                    DocumentOutlineView(controller: outline, requests: editorRequests,
                        session: projectSession, theme: theme)
                } else if section == SidebarSection.margin.rawValue {
                    livingMarginPanel(theme: theme)
                } else if let selectedSection = presentation.toolSection {
                    ProjectWriterToolsView(session: projectSession, completion: completion,
                        editorRequests: editorRequests, section: selectedSection, theme: theme)
                        .id(projectSession.runtimeIdentity?.key)
                } else {
                    ProjectToolUnavailableView(theme: theme)
                }
            }
        } rail: {
            WorkspaceRail(navigatorVisible: $sidebarVisible, section: $section,
                session: projectSession, requests: editorRequests, theme: theme,
                openSettings: { openSettings() }, onShowLivingMargin: livingMarginOpenAction,
                marginSelected: marginVisible)
        }
    }

    private var livingMarginOpenAction: (() -> Void)? {
        guard marginAvailable else { return nil }
        return { toggleMargin() }
    }

    private func livingMarginPanel(theme: MintTheme) -> some View {
        VStack(spacing: 0) {
            if let writingDiagnostics {
                WritingDiagnosticsStatusView(runtime: writingDiagnostics)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                theme.sepC.frame(height: 1).accessibilityHidden(true)
            }
            LivingMarginView(model: livingMargin, mode: activeWritingMode, theme: theme,
                onJumpToEvidence: navigateMarginEvidence,
                onAction: writingQualityAction, supportsAction: { $0.kind == .writingQuality })
            if let error = editorRequests.sourceNavigationError {
                Text(error).mintUIFont(11).foregroundStyle(theme.ink3C).padding(12)
            }
            if editorRequests.sourceReturnPoint?.key.projectID == projectSession.activeProject?.id {
                Button("집필 위치로 돌아가기") { editorRequests.returnToWriting(in: projectSession) }
                    .mintUIFont(11).padding(12)
                    .accessibilityIdentifier("mint.living-margin.return")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspacePaperSurface(theme: theme, identifier: "mint.living-margin"))
    }

    private func navigateMarginEvidence(_ insight: MarginInsight, _ anchor: EvidenceAnchor) {
        if insight.kind == .writingQuality {
            guard let writingDiagnostics else {
                editorRequests.sourceNavigationError = "원문 위치를 확인할 수 없어요. 새 제안을 확인해 주세요."
                return
            }
            _ = writingDiagnostics.navigateMarginEvidence(insightID: insight.id, evidence: anchor, requests: editorRequests)
        } else {
            let sequence = (editorRequests.searchJump?.sequence ?? 0) + 1
            guard let jump = LivingMarginWorkspaceBridge.jump(to: anchor, in: projectSession, sequence: sequence) else { return }
            editorRequests.issueJump(documentID: jump.documentID, query: jump.query)
        }
    }

    private var writingQualityAction: ((MarginInsight, MarginAction) -> Void)? {
        guard let writingDiagnostics else { return nil }
        return { insight, action in
            guard insight.kind == .writingQuality else { return }
            do { try writingDiagnostics.performMarginAction(insightID: insight.id, action: action) }
            catch { } // The runtime publishes a safe, localized action status.
        }
    }

    private func hideNavigator() {
        sidebarVisible = false
        editorRequests.focusEditor()
    }

    private var activeWritingMode: WritingMode {
        projectSession.activeProject?.mode ?? .general
    }
}

private struct ProjectToolUnavailableView: View {
    let theme: MintTheme

    var body: some View {
        VStack(alignment: .leading) {
            Text("이 프로젝트 도구는 아직 사용할 수 없어요.")
                .mintUIFont(11)
                .foregroundStyle(theme.ink3C)
                .padding(14)
            Spacer(minLength: 0)
        }
    }
}

struct WorkspaceToolDescriptor: Equatable {
    let title: String
    let subtitle: String
    let systemImage: String
}

enum WorkspaceToolPresentation {
    static func isVisible(_ rawSection: String) -> Bool {
        switch SidebarSection(rawValue: rawSection) {
        case .bible, .narrative, .context: true
        case .files, .margin, .none: false
        }
    }

    static func descriptor(for rawSection: String) -> WorkspaceToolDescriptor {
        switch SidebarSection(rawValue: rawSection) {
        case .margin:
            WorkspaceToolDescriptor(
                title: "리빙 마진",
                subtitle: "원고 옆에서 확인할 제안",
                systemImage: "sparkles")
        case .bible:
            WorkspaceToolDescriptor(
                title: "인물과 작품 정보",
                subtitle: "저장된 장르와 인물 설정",
                systemImage: "book.closed")
        case .narrative:
            WorkspaceToolDescriptor(
                title: "작가 수정과 기록",
                subtitle: "저장된 판정과 대화 기록",
                systemImage: "arrow.triangle.branch")
        case .context:
            WorkspaceToolDescriptor(
                title: "제안에 쓰인 내용",
                subtitle: "참조한 원문과 저장된 선택",
                systemImage: "text.magnifyingglass")
        case .files, .none:
            WorkspaceToolDescriptor(
                title: "글 도구",
                subtitle: "원고를 돕는 보조 도구",
                systemImage: "sidebar.right")
        }
    }
}

/// Selection helpers mutate presentation state only. The close button itself restores
/// editor focus so callers that merely update stored presentation state stay side-effect free.
enum WorkspaceToolSelection {
    static func showLivingMargin(currentSection: inout String) {
        currentSection = SidebarSection.margin.rawValue
    }

    static func hide(currentSection: inout String) {
        currentSection = SidebarSection.files.rawValue
    }
}

/// Resolves project evidence without projecting the manuscript into a legacy entry.
@MainActor
enum LivingMarginWorkspaceBridge {
    @discardableResult
    static func jump(
        to anchor: EvidenceAnchor,
        in session: ProjectSession,
        sequence: Int
    ) -> EditorSearchJump? {
        guard let project = session.activeProject,
            !project.trashedDocumentIDs.contains(anchor.documentID),
            let document = project.documents.first(where: { $0.id == anchor.documentID }),
            let query = anchor.resolvedQuery(in: document.body)
        else { return nil }

        session.selectDocument(document.id)
        return EditorSearchJump(
            documentID: document.id,
            query: query,
            sequence: sequence)
    }
}
