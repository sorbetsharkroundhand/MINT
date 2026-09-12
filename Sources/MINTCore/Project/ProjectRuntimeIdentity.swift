import Foundation

/// Stable editor, cursor, and undo identity for one document in one project.
public struct ProjectDocumentKey: Hashable, Codable, Sendable {
    public let projectID: WritingProjectID
    public let documentID: WritingDocumentID

    public init(projectID: WritingProjectID, documentID: WritingDocumentID) {
        self.projectID = projectID
        self.documentID = documentID
    }
}

/// Generation-bearing identity for asynchronous work tied to manuscript state.
public struct ProjectRuntimeIdentity: Hashable, Sendable {
    public let key: ProjectDocumentKey
    public let generation: UInt64

    public init(key: ProjectDocumentKey, generation: UInt64) {
        self.key = key
        self.generation = generation
    }
}

public enum ProjectSessionPhase: Equatable, Sendable {
    case loading
    case needsProject
    case ready
    case suspended
    case failed
}

public enum ProjectSavePhase: Equatable, Sendable {
    case saved
    case dirty
    case saving
    case failed
}

public struct RecentProjectSummary: Equatable, Sendable, Identifiable {
    public let id: WritingProjectID
    public let title: String
    public let mode: WritingMode

    public init(id: WritingProjectID, title: String, mode: WritingMode) {
        self.id = id
        self.title = title
        self.mode = mode
    }
}
