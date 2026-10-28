import Foundation

/// Prepare copies before handing the verified project to the sole mutable session.
///
/// SwiftUI must not duplicate migration logic. The source file is read-only; ProjectStore
/// creates and verifies a separate WritingProject and activates it only after preservation
/// checks succeed.
@MainActor
public final class ImportProjectCoordinator {
    private let store: ProjectStore
    private let session: ProjectSession
    private let cancellationCheckpoint: () async throws -> Void

    public init(
        store: ProjectStore,
        session: ProjectSession,
        cancellationCheckpoint: @escaping () async throws -> Void = {
            try Task.checkCancellation()
        }
    ) {
        self.store = store
        self.session = session
        self.cancellationCheckpoint = cancellationCheckpoint
    }

    @discardableResult
    public func importProject(from sourceDirectory: URL) async throws -> WritingProjectID {
        let id = try await store.prepareProjectImport(from: sourceDirectory)
        try await cancellationCheckpoint()
        try await session.activateProject(id: id)
        return id
    }

    @discardableResult
    public func importFolder(from directory: URL, legacyMode: WritingMode) async throws -> WritingProjectID {
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        try ProjectPaths.rejectSymlink(directory)
        if Self.containsProjectManifest(in: directory) {
            return try await importProject(from: directory)
        }
        return try await importLegacy(from: directory.appendingPathComponent("entries.json"),
            mode: legacyMode, title: "Imported Project").projectID
    }

    static func containsProjectManifest(in directory: URL) -> Bool {
        // lstat-style attributes also recognize dangling links; never fall back past a bad manifest.
        (try? FileManager.default.attributesOfItem(atPath:
            directory.appendingPathComponent("project.json").path)) != nil
    }

    @discardableResult
    public func importLegacy(
        from sourceURL: URL,
        mode: WritingMode,
        title: String
    ) async throws -> LegacyMigrationResult {
        let result = try await store.prepareLegacyMigration(
            from: sourceURL,
            mode: mode,
            title: title)
        try await cancellationCheckpoint()
        try await session.activateProject(id: result.projectID)
        return result
    }
}
