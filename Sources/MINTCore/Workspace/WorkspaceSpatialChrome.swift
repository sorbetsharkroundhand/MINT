import SwiftUI

struct WorkspaceSpatialChrome: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var model: SpatialWorkspaceController
    @ObservedObject var completion: CompletionController
    let theme: MintTheme
    let search: () -> Void
    let coauthor: () -> Void
    var body: some View {
        WorkspaceWindowChrome(projectTitle: (session.activeProject?.title ?? "프로젝트") + (session.selectedDocument.map { " · " + $0.title } ?? ""), theme: theme, trailingInset: 430, onTitlePress: search)
            .overlay(alignment: .trailing) {
                HStack(spacing: 8) {
                    ModelChip(completion: completion, settings: completion.settings, theme: theme, compact: true)
                    if let mode = session.activeProject?.mode {
                        Picker("작업 공간", selection: Binding(get: { session.workspaceMode }, set: { session.selectWorkspaceMode($0) })) {
                            ForEach(WorkspaceModePresentation.options(for: mode)) { option in Text(option.label).tag(option.mode) }
                        }.pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.mini)
                            .accessibilityIdentifier("mint.workspace-mode")
                    }
                    Text("\(model.layout.openDocuments.count)개 열림").font(MintFonts.monoUI(9)).foregroundStyle(theme.ink3C)
                    WorkspaceActionButton(identifier: "mint.workspace.open-all", label: "모든 문서 나란히 열기", symbol: "rectangle.split.3x1", theme: theme) { model.openAll() }.frame(width: 26, height: 30)
                    WorkspaceActionButton(identifier: "mint.commands.show", label: "빠른 검색 및 명령 (⌘K)", symbol: "magnifyingglass", theme: theme, action: search).frame(width: 26, height: 30)
                    WorkspaceActionButton(identifier: "mint.coauthor.show", label: "공동 집필", symbol: "sparkles", theme: theme, action: coauthor).frame(width: 26, height: 30)
                }.padding(.trailing, 10).background(theme.workspaceSurfaceC)
            }.opacity(model.whisperTyping ? 0.08 : 1).allowsHitTesting(!model.whisperTyping)
    }
}
