/// A read-only view of persisted presentation choices. Invalid or deferred IDs
/// remain intact while only supported tools participate in visible layout.
struct WorkspacePresentationState {
    let navigatorVisible: Bool
    let navigatorWidth: Double
    let rawToolSection: String
    let rawToolDock: String
    let chromeHidden: Bool
    var outlineVisible = false
    var marginVisible = false

    var contextVisible: Bool { outlineVisible || marginVisible || toolSection != nil }

    var toolSection: SidebarSection? {
        switch SidebarSection(rawValue: rawToolSection) {
        case .bible: .bible
        case .narrative: .narrative
        case .context: .context
        default: nil
        }
    }

    var toolDock: ToolDockPosition {
        ToolDockPosition(rawValue: rawToolDock) ?? .automatic
    }
}
