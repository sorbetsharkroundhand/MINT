import Foundation

public struct WritingProject: Codable, Equatable, Sendable, Identifiable {
    public var id: WritingProjectID
    public var title: String
    public var mode: WritingMode
    public var documents: [WritingDocument]

    public init(id: WritingProjectID, title: String, mode: WritingMode, documents: [WritingDocument]) {
        self.id = id
        self.title = title
        self.mode = mode
        self.documents = documents
    }
}
