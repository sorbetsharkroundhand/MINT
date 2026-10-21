import SwiftUI

struct WorkspaceSpatialChrome: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var model: SpatialWorkspaceController
    @ObservedObject var completion: CompletionController
    let theme: MintTheme
    let coauthor: () -> Void
    var body: some View {
        WorkspaceWindowChrome(projectTitle: session.activeProject?.title ?? "프로젝트", theme: theme,
            trailingInset: 210, documentTitle: session.selectedDocument?.title,
            openCount: model.layout.openDocuments.count, glass: true)
            .overlay(alignment: .trailing) {
                HStack(spacing: 6) {
                    WorkspaceTextAction(title: "나란히 보기", symbol: "rectangle.split.3x1", identifier: "mint.workspace.open-all", theme: theme) { model.openAll() }
                        .frame(width: 89, height: 22)
                    WorkspaceTextAction(title: "공동 집필", symbol: "sparkles", identifier: "mint.coauthor.show", theme: theme, action: coauthor)
                        .frame(width: 78, height: 22)
                }.padding(.trailing, 14)
            }
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
