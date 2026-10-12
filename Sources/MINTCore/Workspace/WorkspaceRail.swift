import SwiftUI

struct WorkspaceRail: View {
    @Binding var navigatorVisible: Bool
    @Binding var section: String
    @ObservedObject var session: ProjectSession
    let requests: ProjectEditorRequests
    let theme: MintTheme
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.mintWorkspaceAccessibilityOptions) private var accessibilityOptions

    var body: some View {
        VStack(spacing: 10) {
            WorkspaceActionButton(identifier: "mint.workspace.navigator-toggle",
                label: navigatorVisible ? "파일 목록 숨기기" : "파일 목록 보이기",
                symbol: "sidebar.left", theme: theme, selected: navigatorVisible) {
                    withAnimation(systemReduceMotion || accessibilityOptions.reduceMotion ? nil : WorkspaceMotion.navigator) {
                        navigatorVisible.toggle()
                    }
                    if !navigatorVisible { requests.focusEditor() }
                }
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: MintRadius.sm)
                    .fill(navigatorVisible ? theme.activeBgC : .clear))
            SourceSearchToolbarButton(session: session, requests: requests, compact: true)
                .frame(width: 32, height: 32)
            WriterCompatibilityMenu(section: $section).frame(width: 32, height: 32)
            Spacer(minLength: 12)
            WorkspaceActionButton(identifier: "mint.workspace.settings", label: "설정",
                symbol: "gearshape", theme: theme, action: openSettings).frame(width: 32, height: 32)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspacePaperSurface(theme: theme, identifier: "mint.workspace.rail"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mint.workspace.rail")
        .accessibilityLabel("작업 공간 내비게이션")
    }
}
