import Foundation

/// Thin onboarding facade over the already-hardened non-destructive legacy migrator.
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
