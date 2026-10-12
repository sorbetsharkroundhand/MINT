import SwiftUI

enum WorkspaceMotion {
    static let navigator = Animation.spring(response: 0.3, dampingFraction: 0.9)
}

/// The shell owns presentation only; document lifetime, storage and indexing belong to the session.
struct WorkspaceShellView<Navigator: View, Editor: View, Context: View>: View {
    @Binding var navigatorWidth: Double
    let navigatorVisible: Bool
    let onNavigatorCollapse: () -> Void
    let contextVisible: Bool
    let toolDockPosition: ToolDockPosition
    let theme: MintTheme
    @ViewBuilder var navigator: () -> Navigator
    @ViewBuilder var editor: () -> Editor
    @ViewBuilder var context: () -> Context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigatorDragProjectedWidth: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let width = WorkspaceLayoutState(
                navigatorWidth: Double(navigatorDragProjectedWidth ?? CGFloat(navigatorWidth)))
                .navigatorWidth(in: geometry.size.width)
            let effectiveDock = WorkspaceLayoutState.effectiveToolDock(
                preferred: toolDockPosition,
                availableWidth: geometry.size.width,
                navigatorVisible: navigatorVisible,
                navigatorWidth: width)

            HStack(spacing: 0) {
                if navigatorVisible {
                    navigator()
                        .frame(width: width)
                        .opacity(navigatorDragOpacity)
                        .clipped()
                        .background(WorkspaceChromeSurface(theme: theme))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if contextVisible && effectiveDock == .left {
                    context()
                        .frame(width: WorkspaceLayoutState.toolWidth)
                        .background(WorkspaceToolSurface(theme: theme, floating: false))
                    theme.sepC.frame(width: 1)
                }

                VStack(spacing: 0) {
                    editor()
                        .frame(
                            minWidth: WorkspaceLayoutState.editorMinWidth,
                            maxWidth: .infinity,
                            maxHeight: .infinity)
                        .background(theme.editorSurfaceC)

                    if contextVisible && effectiveDock == .bottom {
                        theme.sepC.frame(height: 1)
                        context()
                            .frame(
                                height: min(
                                    WorkspaceLayoutState.bottomToolMaxHeight,
                                    geometry.size.height * 0.4))
                            .background(WorkspaceToolSurface(theme: theme, floating: false))
                    }
                }

                if contextVisible && effectiveDock == .right {
                    theme.sepC.frame(width: 1)
                    context()
                        .frame(width: WorkspaceLayoutState.toolWidth)
                        .background(WorkspaceToolSurface(theme: theme, floating: false))
                }
            }
            .overlay(alignment: .leading) {
                if navigatorVisible {
                    SidebarResizeDivider(
                        width: Binding(get: { width }, set: { navigatorWidth = Double($0) }),
                        minWidth: WorkspaceLayoutState.navigatorMinWidth,
                        maxWidth: min(
                            WorkspaceLayoutState.navigatorMaxWidth,
                            max(
                                WorkspaceLayoutState.navigatorMinWidth,
                                geometry.size.width - WorkspaceLayoutState.editorMinWidth)),
                        collapseThreshold: WorkspaceLayoutState.navigatorCollapseThreshold,
                        collapseReleaseThreshold:
                            WorkspaceLayoutState.navigatorCollapseReleaseThreshold,
                        onCollapse: {
                            settleNavigatorDrag(collapse: true)
                        },
                        onDragPreview: { projectedWidth in
                            navigatorDragProjectedWidth = projectedWidth
                        },
                        onDragSettled: {
                            settleNavigatorDrag(collapse: false)
                        },
                        theme: theme
                    )
                    .frame(width: 24)
                    .offset(x: width - 12)
                }
            }
            .overlay(alignment: .topTrailing) {
                if contextVisible && effectiveDock == .floating {
                    context()
                        .frame(
                            width: WorkspaceLayoutState.toolWidth,
                            height: min(
                                WorkspaceLayoutState.floatingToolMaxHeight,
                                max(240, geometry.size.height - 36)))
                        .background(WorkspaceToolSurface(theme: theme, floating: true))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: MintRadius.lg,
                                style: .continuous))
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: MintRadius.lg,
                                style: .continuous)
                                .strokeBorder(theme.sepC))
                        .shadow(
                            color: .black.opacity(MintElevation.floating.opacity),
                            radius: MintElevation.floating.radius,
                            y: MintElevation.floating.y)
                        .padding(18)
                }
            }

        }
        .background(theme.editorSurfaceC)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            theme.editorSurfaceC
        } else {
            Rectangle().fill(.thinMaterial)
        }
    }
}

struct WorkspaceToolSurface: View {
    let theme: MintTheme
    let floating: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            if floating {
                RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous)
                    .fill(theme.editorSurfaceC)
            } else {
                theme.editorSurfaceC
            }
        } else if floating {
            RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous)
                .fill(.regularMaterial)
        } else {
            Rectangle().fill(.thinMaterial)
        }
    }
}

/// Connects the workspace directly to the sole mutable project owner.
struct WorkspaceSurface: View {
    @ObservedObject var projectSession: ProjectSession
    @ObservedObject var editorRequests: ProjectEditorRequests
    @ObservedObject var completion: CompletionController
    @ObservedObject var livingMargin: LivingMarginModel
    var editorBridge: ProjectEditorBridge? = nil
    var positionStore: WritingPositionStore = .shared
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var palette = PaletteSettings.shared
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @AppStorage("mint.sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage("mint.sidebarSection") private var section = SidebarSection.files.rawValue
    @AppStorage("mint.toolDockPosition")
    private var toolDockRaw = ToolDockPosition.automatic.rawValue
    @AppStorage("mint.chromeHidden") private var chromeHidden = false
    @State private var trafficLightMaxX: CGFloat?

    var body: some View {
        let theme = palette.theme(for: colorScheme)
        let presentation = WorkspacePresentationState(navigatorVisible: sidebarVisible,
            navigatorWidth: sidebarWidth, rawToolSection: section,
            rawToolDock: toolDockRaw, chromeHidden: chromeHidden)
        WorkspaceShellView(
            navigatorWidth: $sidebarWidth,
            navigatorVisible: sidebarVisible,
            onNavigatorCollapse: {
                sidebarVisible = false
                editorRequests.focusEditor()
            },
            contextVisible: presentation.toolSection != nil,
            toolDockPosition: presentation.toolDock,
            theme: theme
        ) {
            ProjectNavigatorView(
                session: projectSession,
                editorRequests: editorRequests,
                theme: theme)
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
            let tool = WorkspaceToolPresentation.descriptor(for: section)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.ink2C)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: MintRadius.sm, style: .continuous)
                                .fill(theme.chipC)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.title)
                            .mintUIFont(12, .semibold)
                            .foregroundStyle(theme.inkC)
                        Text(tool.subtitle)
                            .mintUIFont(10.5)
                            .foregroundStyle(theme.ink3C)
                            .lineLimit(1)
                    }
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
                    Button {
                        WorkspaceToolSelection.hide(currentSection: &section)
                        editorRequests.focusEditor()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.ink2C)
                    .accessibilityLabel("문서로 돌아가기")
                    .help("문서로 돌아가기")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                theme.sepC.frame(height: 1)
                    .accessibilityHidden(true)
                if section == SidebarSection.margin.rawValue {
                    LivingMarginView(
                        model: livingMargin,
                        mode: activeWritingMode,
                        theme: theme,
                        onJumpToEvidence: { anchor in
                            let sequence = (editorRequests.searchJump?.sequence ?? 0) + 1
                            guard let jump = LivingMarginWorkspaceBridge.jump(
                                to: anchor,
                                in: projectSession,
                                sequence: sequence)
                            else { return }
                            editorRequests.issueJump(
                                documentID: jump.documentID,
                                query: jump.query)
                        },
                        onAction: nil)
                } else if let selectedSection = presentation.toolSection {
                    ProjectWriterToolsView(session: projectSession, completion: completion,
                        editorRequests: editorRequests, section: selectedSection, theme: theme)
                        .id(projectSession.runtimeIdentity?.key)
                } else {
                    ProjectToolUnavailableView(theme: theme)
                }
            }
        }
        .tint(theme.blueC)
        .environment(
            \.mintWindowChromeLeadingInset,
            WindowChromeGeometry.leadingContentInset(trafficLightMaxX: trafficLightMaxX))
        .background(WindowChromeProbe(trafficLightMaxX: $trafficLightMaxX))
        .ignoresSafeArea(.container, edges: .top)
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
