import Foundation

struct WorkspaceModeOption: Equatable, Identifiable {
    let mode: WorkspaceMode
    let label: String

    var id: WorkspaceMode { mode }
}

enum WorkspaceModePresentation {
    static func options(for projectMode: WritingMode) -> [WorkspaceModeOption] {
        WorkspaceRouting.availableModes(for: projectMode).map { mode in
            WorkspaceModeOption(mode: mode, label: label(for: mode))
        }
    }

    private static func label(for mode: WorkspaceMode) -> String {
        switch mode {
        case .write: "쓰기"
        case .outline: "개요"
        case .map: "지도"
        case .review: "검토"
        }
    }
}

@MainActor
enum WorkspaceModeSelection {
    static func select(
        _ mode: WorkspaceMode,
        session: ProjectSession,
        editorStore: EntryStore
    ) {
        session.selectWorkspaceMode(mode)
        editorStore.requestEditorFocus()
    }
}
