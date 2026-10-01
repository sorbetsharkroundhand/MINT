import Foundation

/// Stable TextKit identity. Runtime generations are deliberately excluded so ordinary body
/// edits do not look like document transitions and cannot discard native undo state.
public enum EditorDocumentIdentity: Hashable, Sendable {
    case project(ProjectDocumentKey)
    case legacy(UUID)

    public var documentID: WritingDocumentID {
        switch self {
        case .project(let key): key.documentID
        case .legacy(let id): WritingDocumentID(rawValue: id)
        }
    }

}

/// Editor-owned search intent shared by project and explicit legacy workspaces.
public struct EditorSearchJump: Equatable, Sendable {
    public let documentID: WritingDocumentID
    public let query: String
    public let sequence: Int

    public init(documentID: WritingDocumentID, query: String, sequence: Int) {
        self.documentID = documentID
        self.query = query
        self.sequence = sequence
    }

    public init(documentID: UUID, query: String, sequence: Int) {
        self.init(
            documentID: WritingDocumentID(rawValue: documentID), query: query,
            sequence: sequence)
    }
}
