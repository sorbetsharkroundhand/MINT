import Combine
import Foundation

/// Sole mutable in-memory owner for the active writing project.
///
/// ProjectStore owns durable serialization and verification. Consumers edit only through this
/// session and receive generation-bearing identities for stale-safe asynchronous work.
@MainActor
public final class ProjectSession: ObservableObject {
    @Published public private(set) var activeProject: WritingProject?
    @Published public private(set) var selectedDocumentID: WritingDocumentID?
    @Published public private(set) var workspaceMode: WorkspaceMode = .write
    @Published public private(set) var phase: ProjectSessionPhase = .loading
    @Published public private(set) var savePhase: ProjectSavePhase = .saved
    @Published public private(set) var runtimeIdentity: ProjectRuntimeIdentity?
    @Published public private(set) var recentProjects: [RecentProjectSummary] = []
    @Published public private(set) var lastErrorMessage: String?
    /// `false` means persistence scope is still unknown; callers must not assume legacy.
    @Published public private(set) var hasLoadedActiveProject = false

    public var willTransition: (() -> Void)?
    public var documentDidChange: ((ProjectDocumentSnapshot) -> Void)?

    private let store: ProjectStore
    private let defaults: UserDefaults
    private let autosaveDelay: Duration
    private var generation: UInt64 = 0
    private var dirtyGeneration: UInt64?
    private var saveTask: Task<Void, Never>?
    private var isTransitioning = false

    public init(
        store: ProjectStore,
        defaults: UserDefaults = .standard,
        autosaveDelay: Duration = .milliseconds(800)
    ) {
        self.store = store
        self.defaults = defaults
        self.autosaveDelay = autosaveDelay
    }

    public var availableWorkspaceModes: [WorkspaceMode] {
        guard let activeProject else { return [.write] }
        return WorkspaceRouting.availableModes(for: activeProject.mode)
    }

    public var selectedDocument: WritingDocument? {
        guard let activeProject, let selectedDocumentID else { return nil }
        return activeProject.documents.first { $0.id == selectedDocumentID }
    }

    public var selectedDocumentSnapshot: ProjectDocumentSnapshot? {
        guard let runtimeIdentity, let selectedDocument, let activeProject else { return nil }
        return ProjectDocumentSnapshot(
            identity: runtimeIdentity, title: selectedDocument.title,
            body: selectedDocument.body, kind: selectedDocument.kind, mode: activeProject.mode)
    }

    /// Derived memory stays unscoped until active-project lookup has completed. Once
    /// known, a nil active project represents an explicit legacy session.
    public func storyMemoryScope(for entryID: UUID) -> StoryMemoryScope? {
        guard hasLoadedActiveProject else { return nil }
        return StoryMemoryScopeResolver.resolve(
            activeProject: activeProject, entryID: entryID)
    }

    /// Load the verified active project without creating or migrating anything.
    public func loadActiveProject() async throws {
        try await bootstrap()
    }

    /// Resolve the durable active marker into the sole mutable in-memory project value.
    public func bootstrap() async throws {
        phase = .loading
        lastErrorMessage = nil
        do {
            let project = try await store.activeProject()
            adopt(project)
            hasLoadedActiveProject = true
            phase = project == nil ? .needsProject : .ready
            if let project { recordRecent(project) }
            await resolveRecentProjects(activeProject: project)
        } catch {
            phase = .failed
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Switch only after ProjectStore has verified and activated the target.
    public func activateProject(id: WritingProjectID) async throws {
        try beginTransition()
        defer { finishTransition() }
        cancelAutosave()
        do {
            try await flush()
            phase = .loading
            let project = try await store.activateAndLoad(id: id)
            // Activation has committed. Adoption intentionally has no cancellation point.
            adopt(project)
            hasLoadedActiveProject = true
            phase = .ready
            savePhase = .saved
            lastErrorMessage = nil
            recordRecent(project)
            mergeRecentSummary(project)
        } catch {
            phase = activeProject == nil ? .failed : .ready
            lastErrorMessage = error.localizedDescription
            // The barrier detached readers, but persistence kept the previous owner.
            // Reconnect only that surviving snapshot; do not advance its generation.
            if let snapshot = selectedDocumentSnapshot { documentDidChange?(snapshot) }
            throw error
        }
    }

    /// Used by onboarding/import after a project has been explicitly created by the user.
    /// Save + verification complete before active UI state changes.
    public func saveAndActivate(_ project: WritingProject) async throws {
        try beginTransition()
        defer { finishTransition() }
        cancelAutosave()
        do {
            try await flush()
            try await store.save(project)
            let verified = try await store.activateAndLoad(id: project.id)
            // Activation has committed. Adoption intentionally has no cancellation point.
            adopt(verified)
            hasLoadedActiveProject = true
            phase = .ready
            savePhase = .saved
            lastErrorMessage = nil
            recordRecent(verified)
            mergeRecentSummary(verified)
        } catch {
            phase = activeProject == nil ? .failed : .ready
            lastErrorMessage = error.localizedDescription
            if let snapshot = selectedDocumentSnapshot { documentDidChange?(snapshot) }
            throw error
        }
    }

    public func selectDocument(_ id: WritingDocumentID?) {
        guard !isTransitioning else { return }
        guard let project = activeProject else {
            selectedDocumentID = nil
            runtimeIdentity = nil
            return
        }
        guard let id else {
            guard selectedDocumentID != nil else { return }
            willTransition?()
            selectedDocumentID = nil
            defaults.removeObject(forKey: selectionPreferenceKey(project.id))
            noteDocumentChange()
            return
        }
        guard id != selectedDocumentID,
            !project.trashedDocumentIDs.contains(id),
            project.documents.contains(where: { $0.id == id })
        else { return }
        willTransition?()
        selectedDocumentID = id
        persistSelection(id, for: project.id)
        noteDocumentChange()
    }

    public func selectWorkspaceMode(_ requested: WorkspaceMode) {
        guard !isTransitioning else { return }
        guard let project = activeProject else {
            workspaceMode = .write
            return
        }
        let normalized = WorkspaceRouting.normalizedSelection(requested, for: project.mode)
        workspaceMode = normalized
        defaults.set(normalized.rawValue, forKey: workspacePreferenceKey(project.id))
    }

    public func updateSelectedDocumentBody(_ body: String) {
        guard !isTransitioning else { return }
        guard var project = activeProject,
            let selectedDocumentID,
            let index = project.documents.firstIndex(where: { $0.id == selectedDocumentID }),
            project.documents[index].body != body
        else { return }

        project.documents[index].body = body
        activeProject = project
        noteDocumentChange()
        markDirty()
    }

    public func renameSelectedDocument(to title: String) {
        guard let projectID = activeProject?.id, let selectedDocumentID else { return }
        renameDocument(
            ProjectDocumentKey(projectID: projectID, documentID: selectedDocumentID),
            to: title)
    }

    /// Renames a captured project/document identity without changing a newer editor selection.
    /// Deferred UI commits must not retarget a title edit after navigation or trashing.
    public func renameDocument(_ key: ProjectDocumentKey, to title: String) {
        guard !isTransitioning else { return }
        guard var project = activeProject,
            project.id == key.projectID,
            !project.trashedDocumentIDs.contains(key.documentID),
            let index = project.documents.firstIndex(where: { $0.id == key.documentID }),
            project.documents[index].title != title
        else { return }

        project.documents[index].title = title
        activeProject = project
        noteDocumentChange()
        markDirty()
    }

    @discardableResult
    public func createDocument(
        title: String = "Untitled",
        kind: WritingDocument.Kind = .manuscript
    ) -> WritingDocumentID? {
        guard !isTransitioning else { return nil }
        guard activeProject != nil else { return nil }
        willTransition?()
        guard var project = activeProject else { return nil }
        let document = WritingDocument(
            id: WritingDocumentID(),
            title: title.isEmpty ? "Untitled" : title,
            body: "",
            kind: kind)
        project.documents.append(document)
        activeProject = project
        selectedDocumentID = document.id
        persistSelection(document.id, for: project.id)
        noteDocumentChange()
        markDirty()
        return document.id
    }

    public func trashSelectedDocument() {
        guard !isTransitioning else { return }
        guard let project = activeProject,
            let removedID = selectedDocumentID,
            let removed = project.documents.first(where: { $0.id == removedID }),
            !project.trashedDocumentIDs.contains(removedID)
        else { return }

        willTransition?()
        guard var project = activeProject else { return }

        project.trashedDocumentIDs.insert(removedID)
        var replacementID = project.documents.first {
            !project.trashedDocumentIDs.contains($0.id)
        }?.id
        if replacementID == nil {
            let replacement = WritingDocument(
                id: WritingDocumentID(),
                title: "Untitled",
                body: "",
                kind: removed.kind)
            project.documents.append(replacement)
            replacementID = replacement.id
        }

        activeProject = project
        selectedDocumentID = replacementID
        if let replacementID { persistSelection(replacementID, for: project.id) }
        noteDocumentChange()
        markDirty()
    }

    public func restoreDocument(_ id: WritingDocumentID) {
        guard !isTransitioning else { return }
        guard let project = activeProject,
            project.trashedDocumentIDs.contains(id),
            project.documents.contains(where: { $0.id == id })
        else { return }

        if selectedDocumentID == nil { willTransition?() }
        guard var project = activeProject else { return }

        project.trashedDocumentIDs.remove(id)
        activeProject = project
        if selectedDocumentID == nil {
            selectedDocumentID = id
            persistSelection(id, for: project.id)
        }
        noteDocumentChange()
        markDirty()
    }

    /// Persist every generation observed while the store actor hop is in flight. A save
    /// only clears dirty state when its captured generation is still current.
    public func flush() async throws {
        cancelAutosave()
        while let targetGeneration = dirtyGeneration, let snapshot = activeProject {
            cancelAutosave()
            savePhase = .saving
            do {
                try await store.save(snapshot)
            } catch {
                savePhase = .failed
                lastErrorMessage = error.localizedDescription
                throw error
            }

            if dirtyGeneration == targetGeneration {
                dirtyGeneration = nil
                savePhase = .saved
                lastErrorMessage = nil
                return
            }
        }
    }

    /// Transition participants may synchronously commit marked text before the gate closes.
    /// Once closed, stale UI callbacks cannot mutate either side of the ownership handoff.
    private func beginTransition() throws {
        guard !isTransitioning else { throw ProjectSessionError.transitionInProgress }
        willTransition?()
        isTransitioning = true
    }

    private func finishTransition() {
        isTransitioning = false
    }

    private func adopt(_ project: WritingProject?) {
        cancelAutosave()
        dirtyGeneration = nil
        activeProject = project

        guard let project else {
            selectedDocumentID = nil
            workspaceMode = .write
            runtimeIdentity = nil
            savePhase = .saved
            return
        }

        let remembered = defaults.string(forKey: selectionPreferenceKey(project.id))
            .flatMap(UUID.init(uuidString:))
            .map { WritingDocumentID(rawValue: $0) }
        if let remembered,
            !project.trashedDocumentIDs.contains(remembered),
            project.documents.contains(where: { $0.id == remembered })
        {
            selectedDocumentID = remembered
        } else {
            selectedDocumentID = project.documents.first {
                !project.trashedDocumentIDs.contains($0.id)
            }?.id
        }
        if let selectedDocumentID {
            persistSelection(selectedDocumentID, for: project.id)
        } else {
            defaults.removeObject(forKey: selectionPreferenceKey(project.id))
        }

        let saved = defaults.string(forKey: workspacePreferenceKey(project.id))
            .flatMap(WorkspaceMode.init(rawValue:))
        let normalized = WorkspaceRouting.normalizedSelection(saved, for: project.mode)
        workspaceMode = normalized

        // Normalize stale preferences immediately so General never keeps an old Fiction Map.
        if saved != normalized {
            defaults.set(normalized.rawValue, forKey: workspacePreferenceKey(project.id))
        }

        savePhase = .saved
        noteDocumentChange()
    }

    private func noteDocumentChange() {
        generation += 1
        guard let projectID = activeProject?.id, let selectedDocumentID else {
            runtimeIdentity = nil
            return
        }
        let identity = ProjectRuntimeIdentity(
            key: ProjectDocumentKey(projectID: projectID, documentID: selectedDocumentID),
            generation: generation)
        runtimeIdentity = identity
        if let snapshot = selectedDocumentSnapshot { documentDidChange?(snapshot) }
    }

    private func markDirty() {
        dirtyGeneration = generation
        savePhase = .dirty
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self, autosaveDelay] in
            do {
                try await Task.sleep(for: autosaveDelay)
                guard !Task.isCancelled, let self else { return }
                try await self.flushFromAutosave()
            } catch is CancellationError {
                // Replaced debounce timers are expected and are not save failures.
            } catch {
                guard let self else { return }
                self.savePhase = .failed
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func flushFromAutosave() async throws {
        saveTask = nil
        try await flush()
    }

    private func cancelAutosave() {
        saveTask?.cancel()
        saveTask = nil
    }

    private func persistSelection(_ id: WritingDocumentID, for projectID: WritingProjectID) {
        defaults.set(id.rawValue.uuidString, forKey: selectionPreferenceKey(projectID))
    }

    private func recordRecent(_ project: WritingProject) {
        let value = project.id.rawValue.uuidString
        var stored = defaults.stringArray(forKey: Self.recentProjectsPreferenceKey) ?? []
        stored.removeAll { UUID(uuidString: $0) == project.id.rawValue }
        stored.insert(value, at: 0)
        defaults.set(stored, forKey: Self.recentProjectsPreferenceKey)
    }

    private func mergeRecentSummary(_ project: WritingProject) {
        let summary = RecentProjectSummary(id: project.id, title: project.title, mode: project.mode)
        recentProjects.removeAll { $0.id == project.id }
        recentProjects.insert(summary, at: 0)
    }

    private func resolveRecentProjects(activeProject: WritingProject?) async {
        let stored = defaults.stringArray(forKey: Self.recentProjectsPreferenceKey) ?? []
        var resolved: [RecentProjectSummary] = []
        var firstFailure: String?

        for value in stored {
            guard let rawID = UUID(uuidString: value) else {
                firstFailure = firstFailure ?? "Recent project identifier is invalid: \(value)"
                continue
            }
            let id = WritingProjectID(rawValue: rawID)
            do {
                let project: WritingProject
                if activeProject?.id == id, let activeProject {
                    project = activeProject
                } else {
                    project = try await store.load(id: id)
                }
                guard !resolved.contains(where: { $0.id == id }) else { continue }
                resolved.append(RecentProjectSummary(
                    id: project.id,
                    title: project.title,
                    mode: project.mode))
            } catch {
                firstFailure = firstFailure ?? error.localizedDescription
            }
        }

        recentProjects = resolved
        if let firstFailure { lastErrorMessage = firstFailure }
    }

    private func workspacePreferenceKey(_ id: WritingProjectID) -> String {
        "mint.workspaceMode.\(id.rawValue.uuidString)"
    }

    private func selectionPreferenceKey(_ id: WritingProjectID) -> String {
        "mint.selectedDocument.\(id.rawValue.uuidString)"
    }

    private static let recentProjectsPreferenceKey = "mint.recentProjects"
}
