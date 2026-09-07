import Combine
import Foundation

/// Project-scoped selection/routing state.
///
/// ProjectStore remains the durable manuscript owner. This session owns only active-project
/// UI state and a small per-project workspace preference. It never derives Fiction knowledge
/// and it never uses DocumentOutline.Scene as identity.
@MainActor
public final class ProjectSession: ObservableObject {
    @Published public private(set) var activeProject: WritingProject?
    @Published public private(set) var selectedDocumentID: WritingDocumentID?
    @Published public private(set) var workspaceMode: WorkspaceMode = .write

    private let store: ProjectStore
    private let defaults: UserDefaults
    private var selectedDocumentByProject: [WritingProjectID: WritingDocumentID] = [:]

    public init(store: ProjectStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    public var availableWorkspaceModes: [WorkspaceMode] {
        guard let activeProject else { return [.write] }
        return WorkspaceRouting.availableModes(for: activeProject.mode)
    }

    public var selectedDocument: WritingDocument? {
        guard let activeProject, let selectedDocumentID else { return nil }
        return activeProject.documents.first { $0.id == selectedDocumentID }
    }

    /// Load the verified active project without creating or migrating anything.
    public func loadActiveProject() async throws {
        let project = try await store.activeProject()
        adopt(project)
    }

    /// Switch only after ProjectStore has verified and activated the target.
    public func activateProject(id: WritingProjectID) async throws {
        try await store.activate(id: id)
        let project = try await store.load(id: id)
        adopt(project)
    }

    /// Used by onboarding/import after a project has been explicitly created by the user.
    /// Save + verification complete before active UI state changes.
    public func saveAndActivate(_ project: WritingProject) async throws {
        try await store.save(project)
        try await store.activate(id: project.id)
        let verified = try await store.load(id: project.id)
        adopt(verified)
    }

    public func selectDocument(_ id: WritingDocumentID?) {
        guard let project = activeProject else {
            selectedDocumentID = nil
            return
        }
        guard let id else {
            selectedDocumentID = nil
            selectedDocumentByProject.removeValue(forKey: project.id)
            return
        }
        guard project.documents.contains(where: { $0.id == id }) else { return }
        selectedDocumentID = id
        selectedDocumentByProject[project.id] = id
    }

    public func selectWorkspaceMode(_ requested: WorkspaceMode) {
        guard let project = activeProject else {
            workspaceMode = .write
            return
        }
        let normalized = WorkspaceRouting.normalizedSelection(requested, for: project.mode)
        workspaceMode = normalized
        defaults.set(normalized.rawValue, forKey: workspacePreferenceKey(project.id))
    }

    private func adopt(_ project: WritingProject?) {
        activeProject = project

        guard let project else {
            selectedDocumentID = nil
            workspaceMode = .write
            return
        }

        if let remembered = selectedDocumentByProject[project.id],
            project.documents.contains(where: { $0.id == remembered })
        {
            selectedDocumentID = remembered
        } else {
            selectedDocumentID = project.documents.first?.id
            if let selectedDocumentID {
                selectedDocumentByProject[project.id] = selectedDocumentID
            }
        }

        let saved = defaults.string(forKey: workspacePreferenceKey(project.id))
            .flatMap(WorkspaceMode.init(rawValue:))
        let normalized = WorkspaceRouting.normalizedSelection(saved, for: project.mode)
        workspaceMode = normalized

        // Normalize stale preferences immediately so General never keeps an old Fiction Map.
        if saved != normalized {
            defaults.set(normalized.rawValue, forKey: workspacePreferenceKey(project.id))
        }
    }

    private func workspacePreferenceKey(_ id: WritingProjectID) -> String {
        "mint.workspaceMode.\(id.rawValue.uuidString)"
    }
}
