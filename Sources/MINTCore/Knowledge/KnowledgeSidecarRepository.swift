import Foundation

/// The only persistence selector for derived story memory.
public actor KnowledgeSidecarRepository {
    public enum Error: Swift.Error, Equatable {
        case scopeMismatch
    }

    private let projectStore: ProjectStore
    private let legacyDirectory: URL

    public init(projectStore: ProjectStore, legacyDirectory: URL? = nil) {
        self.projectStore = projectStore
        self.legacyDirectory = legacyDirectory ?? KnowledgeSidecar.directory()
    }

    public func load(scope: StoryMemoryScope) async -> KnowledgeSidecar {
        let data: Data?
        switch scope {
        case .project(let projectID, let documentID):
            data = try? await projectStore.readIntelligence(
                projectID: projectID, documentID: documentID)
        case .legacy(let documentID):
            data = try? Data(contentsOf: legacyURL(documentID))
        }
        guard let data else { return KnowledgeSidecar(scope: scope) }
        return KnowledgeSidecar.decoded(data, for: scope)
    }

    public func save(
        _ sidecar: KnowledgeSidecar,
        pruningTo liveHashes: Set<String>? = nil,
        scope: StoryMemoryScope
    ) async throws {
        guard sidecar.scope == scope else { throw Error.scopeMismatch }
        let data = try sidecar.encoded(pruningTo: liveHashes)
        switch scope {
        case .project(let projectID, let documentID):
            try await projectStore.writeIntelligence(
                data, projectID: projectID, documentID: documentID)
        case .legacy(let documentID):
            try FileManager.default.createDirectory(
                at: legacyDirectory, withIntermediateDirectories: true)
            try data.write(to: legacyURL(documentID), options: .atomic)
        }
    }

    public func replaceWithFresh(
        scope: StoryMemoryScope,
        generation: Int
    ) async throws -> KnowledgeSidecar {
        var sidecar = KnowledgeSidecar(scope: scope)
        sidecar.generation = generation
        try await save(sidecar, scope: scope)
        return sidecar
    }

    public func remove(scope: StoryMemoryScope) async throws {
        switch scope {
        case .project(let projectID, let documentID):
            try await projectStore.removeIntelligence(
                projectID: projectID, documentID: documentID)
        case .legacy(let documentID):
            let url = legacyURL(documentID)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    private func legacyURL(_ documentID: WritingDocumentID) -> URL {
        legacyDirectory.appendingPathComponent("\(documentID.rawValue.uuidString).json")
    }
}
