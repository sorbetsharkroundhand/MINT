import SwiftUI

struct WorkspaceSpatialChrome: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var model: SpatialWorkspaceController
    let theme: MintTheme
    var body: some View {
        WorkspaceWindowChrome(projectTitle: session.activeProject?.title ?? "프로젝트", theme: theme,
            trailingInset: 16, documentTitle: session.selectedDocument?.title,
            openCount: model.layout.openDocuments.count, glass: true)
            .contextMenu {
                if let mode = session.activeProject?.mode {
                    ForEach(WorkspaceModePresentation.options(for: mode)) { option in
                        Button(option.label) { session.selectWorkspaceMode(option.mode) }
                    }
                }
            }
            .opacity(model.whisperTyping ? 0.08 : 1).allowsHitTesting(!model.whisperTyping)
            .animation(WorkspaceHTMLStyle.animation(0.32), value: model.whisperTyping)
    }
}
