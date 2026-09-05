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
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int = currentSchemaVersion
    public var id: WritingProjectID
    public var title: String
    public var mode: WritingMode
    public var documents: [ProjectDocumentRecord]
    public var assets: [ProjectAssetRecord] = []
    public var legacySource: ProjectFileRecord?
}

public enum ProjectStoreError: Error, LocalizedError, Sendable {
    case unsafePath(String)
    case invalidManifest
    case unsupportedSchema(Int)
    case damagedFile(String)
    case invalidLegacy

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let path): "프로젝트 밖 경로나 심볼릭 링크는 사용할 수 없습니다: \(path)"
        case .invalidManifest: "프로젝트 정보가 손상되었거나 문서 ID가 중복됩니다."
        case .unsupportedSchema(let version): "지원하지 않는 프로젝트 저장 버전입니다: \(version)"
        case .damagedFile(let path): "저장된 파일 검증에 실패했습니다: \(path)"
        case .invalidLegacy: "기존 원고를 읽을 수 없거나 문서 ID가 중복됩니다. 원본은 보존됩니다."
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
