import CryptoKit
import Foundation

public struct ProjectDocumentRecord: Codable, Equatable, Sendable {
    public var id: WritingDocumentID
    public var title: String
    public var kind: WritingDocument.Kind
    public var relativePath: String
    public var contentHash: String
}

public struct ProjectFileRecord: Codable, Equatable, Sendable {
    public var relativePath: String
    public var contentHash: String
}

public struct ProjectAssetRecord: Codable, Equatable, Sendable {
    public var reference: String
    public var file: ProjectFileRecord
}

/// 원문은 별도 파일에 두어 manifest 교체 전까지 이전 세대를 보존한다 (PLAN §5.2).
public struct ProjectManifest: Codable, Equatable, Sendable {
    /// Older schema-1 apps must refuse writes rather than discard durable UserData references.
    public static let currentSchemaVersion = 2
    static func supportsSchema(_ version: Int) -> Bool { version == 1 || version == currentSchemaVersion }
    public var schemaVersion: Int = currentSchemaVersion
    public var id: WritingProjectID
    public var title: String
    public var mode: WritingMode
    public var documents: [ProjectDocumentRecord]
    public var trashedDocumentIDs: Set<WritingDocumentID> = []
    public var assets: [ProjectAssetRecord] = []
    public var legacySource: ProjectFileRecord?
    public var userData: [String: ProjectFileRecord] = [:]

    init(
        schemaVersion: Int = currentSchemaVersion,
        id: WritingProjectID,
        title: String,
        mode: WritingMode,
        documents: [ProjectDocumentRecord],
        trashedDocumentIDs: Set<WritingDocumentID> = [],
        assets: [ProjectAssetRecord] = [],
        legacySource: ProjectFileRecord? = nil,
        userData: [String: ProjectFileRecord] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.mode = mode
        self.documents = documents
        self.trashedDocumentIDs = trashedDocumentIDs
        self.assets = assets
        self.legacySource = legacySource
        self.userData = userData
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case title
        case mode
        case documents
        case trashedDocumentIDs
        case assets
        case legacySource
        case userData
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(WritingProjectID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        mode = try container.decode(WritingMode.self, forKey: .mode)
        documents = try container.decode([ProjectDocumentRecord].self, forKey: .documents)
        trashedDocumentIDs = try container.decodeIfPresent(
            Set<WritingDocumentID>.self, forKey: .trashedDocumentIDs) ?? []
        assets = try container.decodeIfPresent([ProjectAssetRecord].self, forKey: .assets) ?? []
        legacySource = try container.decodeIfPresent(ProjectFileRecord.self, forKey: .legacySource)
        userData = try container.decodeIfPresent([String: ProjectFileRecord].self, forKey: .userData) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(mode, forKey: .mode)
        try container.encode(documents, forKey: .documents)
        try container.encode(
            trashedDocumentIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
            forKey: .trashedDocumentIDs)
        try container.encode(assets, forKey: .assets)
        try container.encodeIfPresent(legacySource, forKey: .legacySource)
        try container.encode(userData, forKey: .userData)
    }
}

public enum ProjectStoreError: Error, LocalizedError, Sendable {
    case unsafePath(String)
    case invalidManifest
    case unsupportedSchema(Int)
    case damagedFile(String)
    case invalidLegacy
    case projectAlreadyExists
    case changedDuringSave

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path): "프로젝트 밖 경로나 심볼릭 링크는 사용할 수 없습니다: \(path)"
        case .invalidManifest: "프로젝트 정보가 손상되었거나 문서 ID가 중복됩니다."
        case .unsupportedSchema(let version): "지원하지 않는 프로젝트 저장 버전입니다: \(version)"
        case .damagedFile(let path): "저장된 파일 검증에 실패했습니다: \(path)"
        case .invalidLegacy: "기존 원고를 읽을 수 없거나 문서 ID가 중복됩니다. 원본은 보존됩니다."
        case .projectAlreadyExists: "같은 프로젝트가 이미 저장되어 있습니다. 원본과 기존 프로젝트는 보존됩니다."
        case .changedDuringSave: "프로젝트가 변경되어 작가 설정을 적용하지 않았습니다. 다시 열어 주세요."
        }
    }
}

enum ProjectDigest {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(_ hash: String) -> Bool {
        hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
