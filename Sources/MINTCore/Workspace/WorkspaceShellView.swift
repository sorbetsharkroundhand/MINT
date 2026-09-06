import SwiftUI

/// 저장된 폭을 창 크기에 맞춰 투영한다. 접거나 창을 줄여도 사용자 폭은 잃지 않는다.
struct WorkspaceLayoutState {
    var navigatorWidth: Double = 250

    func navigatorWidth(in availableWidth: CGFloat) -> CGFloat {
        let preferred = navigatorWidth.isFinite ? CGFloat(navigatorWidth) : 250
        return min(max(preferred, 200), min(360, max(200, availableWidth - 560)))
    }
}

/// 셸은 레이아웃만 소유한다. 문서 수명·저장·인덱싱은 상위 세션의 책임이다 (PLAN §5).
struct WorkspaceShellView<Navigator: View, Editor: View, Context: View>: View {
    @Binding var navigatorWidth: Double
    let navigatorVisible: Bool
    let contextVisible: Bool
    let theme: MintTheme
    @ViewBuilder var navigator: () -> Navigator
    @ViewBuilder var editor: () -> Editor
    @ViewBuilder var context: () -> Context

    var body: some View {
        GeometryReader { geometry in
            let width = WorkspaceLayoutState(navigatorWidth: navigatorWidth)
                .navigatorWidth(in: geometry.size.width)
            let contextOnRight = contextVisible && geometry.size.width - (navigatorVisible ? width : 0) >= 901
            HStack(spacing: 0) {
                if navigatorVisible {
                    navigator()
                        .frame(width: width)
                        .background(WorkspaceChromeSurface(theme: theme))
                }
                VStack(spacing: 0) {
                    editor()
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.editorSurfaceC)
                    if contextVisible && !contextOnRight {
                        theme.sepC.frame(height: 1)
                        context()
                            .frame(height: min(320, geometry.size.height * 0.4))
                            .background(WorkspaceChromeSurface(theme: theme))
                    }
                }
                if contextOnRight {
                    theme.sepC.frame(width: 1)
                    context()
                        .frame(width: 340)
                        .background(WorkspaceChromeSurface(theme: theme))
                }
            }
            .overlay(alignment: .leading) {
                if navigatorVisible {
                    SidebarResizeDivider(
                        width: Binding(get: { width }, set: { navigatorWidth = Double($0) }),
                        minWidth: 200, maxWidth: min(360, max(200, geometry.size.width - 560)),
                        theme: theme
                    )
                    .frame(width: 24)
                    .offset(x: width - 12)
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

/// 기존 문서 세션을 새 셸에 연결한다. 영속 프로젝트 세션 전환은 #104에서 담당한다.
struct WorkspaceSurface: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    var indexer: BackgroundIndexer?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.undoManager) private var windowUndoManager
    @StateObject private var palette = PaletteSettings.shared
    @AppStorage("mint.sidebarVisible") private var sidebarVisible = true
    @AppStorage("mint.sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage("mint.sidebarSection") private var section = SidebarSection.files.rawValue

    var body: some View {
        let theme = palette.theme(for: colorScheme)
        store.structureUndoManager = windowUndoManager
        return WorkspaceShellView(
            navigatorWidth: $sidebarWidth, navigatorVisible: sidebarVisible,
            contextVisible: section != SidebarSection.files.rawValue, theme: theme
        ) {
            ProjectNavigatorView(store: store, completion: completion, theme: theme)
        } editor: {
            EditorPane(store: store, completion: completion, settings: completion.settings,
                       theme: theme, indexer: indexer)
        } context: {
            VStack(spacing: 0) {
                HStack {
                    Text("글 도구").font(MintFonts.uiFont(12, .semibold))
                    Spacer()
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
        .ignoresSafeArea()
        .onAppear { section = SidebarSection.files.rawValue }
    }
}
