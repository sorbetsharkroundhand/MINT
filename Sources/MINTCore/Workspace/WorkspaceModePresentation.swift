import Foundation

struct WorkspaceModeOption: Equatable, Identifiable {
    let mode: WorkspaceMode
    let label: String

    var id: WorkspaceMode { mode }
}

enum WorkspaceModePresentation {
    /// Primary release navigation deliberately exposes only surfaces that are ready
    /// to be part of the writing loop. Routing keeps the deferred modes intact so
    /// existing project preferences/data are not destroyed and post-release work can
    /// re-expose them without a migration.
    static func options(for projectMode: WritingMode) -> [WorkspaceModeOption] {
        let visibleModes: [WorkspaceMode]
        switch projectMode {
        case .fiction:
            visibleModes = [.write]
        case .general:
            visibleModes = [.write, .outline]
        }
        return visibleModes.map { mode in
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
