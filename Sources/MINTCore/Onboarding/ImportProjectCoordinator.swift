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

    public init(store: ProjectStore, session: ProjectSession) {
        self.store = store
        self.session = session
    }

    @discardableResult
    public func importLegacy(
        from sourceURL: URL,
        mode: WritingMode,
        title: String
    ) async throws -> LegacyMigrationResult {
        try Task.checkCancellation()
        let result = try await store.migrateLegacy(
            from: sourceURL,
            mode: mode,
            title: title)
        try Task.checkCancellation()

        // Migration already activated a verified target. Reflect it in UI session only
        // after the migration returned success.
        try await session.loadActiveProject()
        guard session.activeProject?.id == result.projectID else {
            throw ProjectStoreError.invalidManifest
        }
        return result
    }
}
