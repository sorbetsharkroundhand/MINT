import Foundation

public struct LegacyMigrationResult: Equatable, Sendable {
    public var projectID: WritingProjectID
    public var migratedDocumentCount: Int
    public var sourceFingerprint: String
    public var reusedExistingProject: Bool
}

struct MigrationReceipt: Codable {
    var requestFingerprint: String
    var projectID: WritingProjectID
}

/// EntryStore를 생성하면 복구·저장 부수효과가 생기므로 파일 값만 읽는다 (PLAN §5.2).
enum LegacyProjectMigrator {
    struct Snapshot {
        var sourceData: Data
        var entries: [JournalEntry]
        var assets: [String: Data]
    }

    private struct LegacyArchive: Decodable {
        var entries: [JournalEntry]
        var activeID: UUID?
        var folders: [JournalFolder]?
        var expandedFolderIDs: [UUID]?
    }

    static func read(from sourceURL: URL) throws -> Snapshot {
        try Task.checkCancellation()
        try ProjectPaths.rejectSymlink(sourceURL)
        let source = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LegacyArchive.self, from: source)
        guard Set(archive.entries.map(\.id)).count == archive.entries.count else {
            throw ProjectStoreError.invalidLegacy
        }
        let base = sourceURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let images = try ProjectPaths.checked("images", under: base)
        var assets: [String: Data] = [:]
        if FileManager.default.fileExists(atPath: images.path) {
            try collectAssets(relative: "images", under: base, into: &assets)
        }
        return Snapshot(sourceData: source, entries: archive.entries, assets: assets)
    }

    private static func collectAssets(relative: String, under base: URL, into assets: inout [String: Data]) throws {
        try Task.checkCancellation()
        let folder = try ProjectPaths.checked(relative, under: base)
        for child in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) {
            try Task.checkCancellation()
            let path = relative + "/" + child.lastPathComponent
            let url = try ProjectPaths.checked(path, under: base)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                try collectAssets(relative: path, under: base, into: &assets)
            } else if values.isRegularFile == true {
                assets[path] = try Data(contentsOf: url)
            } else {
                throw ProjectStoreError.unsafePath(path)
            }
        }
    }

    static func fingerprint(_ snapshot: Snapshot, mode: WritingMode, title: String) throws -> String {
        struct Request: Encodable {
            var version = 1
            var source: String
            var mode: WritingMode
            var title: String
            var assets: [ProjectAssetRecord]
        }
        let assets = snapshot.assets.sorted(by: { $0.key < $1.key }).map {
            ProjectAssetRecord(reference: $0.key, file: ProjectFileRecord(relativePath: "", contentHash: ProjectDigest.hash($0.value)))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return ProjectDigest.hash(try encoder.encode(Request(
            source: ProjectDigest.hash(snapshot.sourceData), mode: mode, title: title, assets: assets)))
    }
}

extension ProjectStore {
    /// 명시적으로 가져온 원고만 다루며 기존 앱의 activeID는 변경하지 않는다.
    public func migrateLegacy(from sourceURL: URL, mode: WritingMode, title: String) throws -> LegacyMigrationResult {
        try withStoreLock {
            let snapshot = try LegacyProjectMigrator.read(from: sourceURL)
            let sourceHash = ProjectDigest.hash(snapshot.sourceData)
            let requestHash = try LegacyProjectMigrator.fingerprint(snapshot, mode: mode, title: title)
            let receiptURL = try rootURL("Migrations/\(requestHash).json")
            var reusedID: WritingProjectID?
            if files.fileExists(at: receiptURL) {
                do {
                    let receipt = try JSONDecoder().decode(MigrationReceipt.self, from: files.read(receiptURL))
                    let manifest = try readManifest(id: receipt.projectID)
                    _ = try materialize(manifest)
                    if receipt.requestFingerprint == requestHash,
                        manifest.legacySource?.contentHash == sourceHash,
                        manifest.assets.count == snapshot.assets.count,
                        manifest.assets.allSatisfy({ asset in
                            snapshot.assets[asset.reference].map { ProjectDigest.hash($0) == asset.file.contentHash } == true
                        }) {
                        reusedID = receipt.projectID
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // 손상된 receipt/target을 덮지 않고 별도 프로젝트로 복구한다.
                }
            }
            let id = reusedID ?? WritingProjectID()
            if reusedID == nil {
                let project = WritingProject(id: id, title: title, mode: mode,
                    documents: snapshot.entries.map(LegacyEntryAdapter.document(from:)))
                try saveUnlocked(project, importedAssets: snapshot.assets, source: snapshot.sourceData)
                let verifiedProject = try loadUnlocked(id: id)
                guard verifiedProject == project,
                    zip(verifiedProject.documents, project.documents).allSatisfy({
                        Data($0.body.utf8) == Data($1.body.utf8) && Data($0.title.utf8) == Data($1.title.utf8)
                    }) else { throw ProjectStoreError.damagedFile("project.json") }
            }
            // 이관 도중 기존 앱이 저장했으면 오래된 스냅샷으로 활성화하지 않는다.
            let latest = try LegacyProjectMigrator.read(from: sourceURL)
            guard latest.sourceData == snapshot.sourceData, latest.assets == snapshot.assets else {
                throw ProjectStoreError.damagedFile("entries.json 또는 images/")
            }
            try files.createDirectory(at: rootURL("Migrations"))
            let receipt = MigrationReceipt(requestFingerprint: requestHash, projectID: id)
            try Task.checkCancellation()
            try files.writeAtomically(JSONEncoder().encode(receipt), to: receiptURL)
            // receipt 이후 활성화가 실패해도 다음 호출이 검증된 target을 재사용한다.
            try activateUnlocked(id: id)
            return LegacyMigrationResult(projectID: id, migratedDocumentCount: snapshot.entries.count,
                sourceFingerprint: sourceHash, reusedExistingProject: reusedID != nil)
        }
    }
}
