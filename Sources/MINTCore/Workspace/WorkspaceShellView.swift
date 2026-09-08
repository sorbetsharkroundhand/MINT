import SwiftUI

enum ToolDockPosition: String, CaseIterable, Codable, Sendable {
    case automatic
    case left
    case right
    case bottom
    case floating

    var label: String {
        switch self {
        case .automatic: "자동"
        case .left: "왼쪽"
        case .right: "오른쪽"
        case .bottom: "아래"
        case .floating: "플로팅"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "rectangle.3.group"
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .floating: "macwindow.on.rectangle"
        }
    }
}

/// 저장된 폭을 창 크기에 맞춰 투영한다. 접거나 창을 줄여도 사용자 폭은 잃지 않는다.
struct WorkspaceLayoutState {
    static let navigatorMinWidth: CGFloat = 200
    static let navigatorMaxWidth: CGFloat = 360
    static let editorMinWidth: CGFloat = 560
    static let navigatorCollapseThreshold: CGFloat = 150
    static let navigatorCollapseReleaseThreshold: CGFloat = 176

    var navigatorWidth: Double = 250

    func navigatorWidth(in availableWidth: CGFloat) -> CGFloat {
        let preferred = navigatorWidth.isFinite ? CGFloat(navigatorWidth) : 250
        return min(
            max(preferred, Self.navigatorMinWidth),
            min(
                Self.navigatorMaxWidth,
                max(Self.navigatorMinWidth, availableWidth - Self.editorMinWidth)))
    }

    /// Hysteresis for drag-to-collapse: arm only after a deliberate pull well past the
    /// minimum width, then require a larger reverse movement before disarming.
    static func navigatorCollapseArmed(
        projectedWidth: CGFloat,
        wasArmed: Bool
    ) -> Bool {
        if wasArmed {
            return projectedWidth < navigatorCollapseReleaseThreshold
        }
        return projectedWidth <= navigatorCollapseThreshold
    }

    static let toolWidth: CGFloat = 340
    static let bottomToolMaxHeight: CGFloat = 320
    static let floatingToolMaxHeight: CGFloat = 520

    /// Resolve the visible placement without mutating the persisted preference.
    /// Explicit side docks fall back to bottom when the editor's minimum width would
    /// be violated; widening the window automatically restores the saved side choice.
    static func effectiveToolDock(
        preferred: ToolDockPosition,
        availableWidth: CGFloat,
        navigatorVisible: Bool,
        navigatorWidth: CGFloat
    ) -> ToolDockPosition {
        let usedByNavigator = navigatorVisible ? navigatorWidth : 0
        let sideFits =
            availableWidth - usedByNavigator - toolWidth >= editorMinWidth

        switch preferred {
        case .automatic:
            return sideFits ? .right : .bottom
        case .left, .right:
            return sideFits ? preferred : .bottom
        case .bottom, .floating:
            return preferred
        }
    }
}

/// 셸은 레이아웃만 소유한다. 문서 수명·저장·인덱싱은 상위 세션의 책임이다 (PLAN §5).
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

    var body: some View {
        GeometryReader { geometry in
            let width = WorkspaceLayoutState(navigatorWidth: navigatorWidth)
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
                        .background(WorkspaceChromeSurface(theme: theme))
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
                        onCollapse: onNavigatorCollapse,
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

/// Connects the persistent project-routing session while preserving the current editor surface.
/// Project-first document ownership remains the #118 runtime handoff.
struct WorkspaceSurface: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    let projectSession: ProjectSession
    var indexer: BackgroundIndexer?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.undoManager) private var windowUndoManager
    @StateObject private var palette = PaletteSettings.shared
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @AppStorage("mint.sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage("mint.sidebarSection") private var section = SidebarSection.files.rawValue
    @AppStorage("mint.toolDockPosition")
    private var toolDockRaw = ToolDockPosition.automatic.rawValue
    @State private var trafficLightMaxX: CGFloat?

    var body: some View {
        let theme = palette.theme(for: colorScheme)
        store.structureUndoManager = windowUndoManager
        return WorkspaceShellView(
            navigatorWidth: $sidebarWidth,
            navigatorVisible: sidebarVisible,
            onNavigatorCollapse: {
                sidebarVisible = false
                store.requestEditorFocus()
            },
            contextVisible: section != SidebarSection.files.rawValue,
            toolDockPosition: ToolDockPosition(rawValue: toolDockRaw) ?? .automatic,
            theme: theme
        ) {
            ProjectNavigatorView(store: store, completion: completion, theme: theme)
        } editor: {
            EditorPane(
                store: store,
                completion: completion,
                settings: completion.settings,
                projectSession: projectSession,
                theme: theme,
                indexer: indexer)
        } context: {
            VStack(spacing: 0) {
                HStack {
                    Text("글 도구").font(MintFonts.uiFont(12, .semibold))
                    Spacer()
                    Menu {
                        ForEach(ToolDockPosition.allCases, id: \.self) { position in
                            Button {
                                toolDockRaw = position.rawValue
                                store.requestEditorFocus()
                            } label: {
                                Label(position.label, systemImage: position.systemImage)
                                if (ToolDockPosition(rawValue: toolDockRaw) ?? .automatic)
                                    == position
                                {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.3.group")
                            .font(MintFonts.uiFont(12))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("글 도구 위치")
                    .help("글 도구 위치")
                    Button {
                        section = SidebarSection.files.rawValue
                        store.requestEditorFocus()
                    } label: {
                        Image(systemName: "xmark").font(MintFonts.uiFont(12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("문서로 돌아가기")
                    .help("문서로 돌아가기")
                }
                .foregroundStyle(theme.ink2C)
                .padding(14)
                SidebarView(presentation: .context, store: store, completion: completion,
                            theme: theme, indexer: indexer)
            }
        }
        .environment(
            \.mintWindowChromeLeadingInset,
            WindowChromeGeometry.leadingContentInset(trafficLightMaxX: trafficLightMaxX))
        .background(WindowChromeProbe(trafficLightMaxX: $trafficLightMaxX))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { section = SidebarSection.files.rawValue }
    }
}
