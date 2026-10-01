import Foundation

/// Path ownership only: constructing a location never creates or moves user data.
public struct MintStorageLocation: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// Preserve the existing Documents/MINT layout, including the home fallback.
    public static let standard: MintStorageLocation = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return MintStorageLocation(rootDirectory: base.appendingPathComponent("MINT", isDirectory: true))
    }()

    public var projectsDirectory: URL { rootDirectory.appendingPathComponent("Projects", isDirectory: true) }
    var knowledgeDirectory: URL { rootDirectory.appendingPathComponent("knowledge", isDirectory: true) }
    var metricsFileURL: URL { rootDirectory.appendingPathComponent("metrics.jsonl") }
    var stopwordsFileURL: URL { rootDirectory.appendingPathComponent("character-stopwords.txt") }
}
