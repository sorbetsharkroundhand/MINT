import Darwin
import Foundation

/// 디스크 작업은 actor 안에서 수행한다. 같은 루트의 다른 인스턴스/프로세스도 잠근다 (PLAN §5.2).
public actor ProjectStore {
    let root: URL
    let files: any ProjectFileSystem

    public init(root: URL, fileSystem: any ProjectFileSystem = LocalProjectFileSystem()) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.files = fileSystem
    }

    public func save(_ project: WritingProject) throws {
        try withStoreLock { try saveUnlocked(project) }
    }

    public func load(id: WritingProjectID) throws -> WritingProject {
        try withStoreLock { try loadUnlocked(id: id) }
    }

    public func previousProject(id: WritingProjectID) throws -> WritingProject {
        try withStoreLock {
            try materialize(readManifest(id: id, name: "previous-project.json"))
        }
    }

    public func activate(id: WritingProjectID) throws {
        try withStoreLock { try activateUnlocked(id: id) }
    }

    public func activeProject() throws -> WritingProject? {
        try withStoreLock {
            let url = try rootURL("active-project.json")
            guard files.fileExists(at: url) else { return nil }
            let id = try JSONDecoder().decode(WritingProjectID.self, from: files.read(url))
            return try loadUnlocked(id: id)
        }
    }

    public func legacySource(id: WritingProjectID) throws -> Data? {
        try withStoreLock {
            guard let record = try readManifest(id: id).legacySource else { return nil }
            return try verified(record, in: id)
        }
    }

    /// 기존 본문의 상대경로를 바꾸지 않고 이관된 사본을 읽는다.
    public func assetData(reference: String, in id: WritingProjectID) throws -> Data? {
        try withStoreLock {
            guard let record = try readManifest(id: id).assets.first(where: { $0.reference == reference })
            else { return nil }
            return try verified(record.file, in: id)
        }
    }

    func withStoreLock<T>(_ operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        try ProjectPaths.rejectSymlink(root)
        try files.createDirectory(at: root)
        let lockURL = try rootURL(".store.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try operation()
    }

    func rootURL(_ path: String) throws -> URL { try ProjectPaths.checked(path, under: root) }

    func projectURL(_ id: WritingProjectID, _ path: String) throws -> URL {
        try rootURL("\(id.rawValue.uuidString)/\(path)")
    }

    func readManifest(id: WritingProjectID, name: String = "project.json") throws -> ProjectManifest {
        let manifest = try JSONDecoder().decode(ProjectManifest.self, from: files.read(projectURL(id, name)))
        guard manifest.schemaVersion == ProjectManifest.currentSchemaVersion else {
            throw ProjectStoreError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.id == id,
            Set(manifest.documents.map(\.id)).count == manifest.documents.count,
            Set(manifest.assets.map(\.reference)).count == manifest.assets.count
        else { throw ProjectStoreError.invalidManifest }
        for record in manifest.documents {
            guard ProjectDigest.isValid(record.contentHash), record.relativePath == documentPath(
                id: record.id, kind: record.kind, hash: record.contentHash)
            else { throw ProjectStoreError.invalidManifest }
        }
        for asset in manifest.assets {
            try ProjectPaths.validateRelative(asset.reference)
            guard asset.file.relativePath == "Assets/\(asset.file.contentHash)" else {
                throw ProjectStoreError.invalidManifest
            }
        }
        if let source = manifest.legacySource,
            source.relativePath != "UserData/legacy-\(source.contentHash).json" {
            throw ProjectStoreError.invalidManifest
        }
        return manifest
    }

    func verified(_ record: ProjectFileRecord, in id: WritingProjectID) throws -> Data {
        guard ProjectDigest.isValid(record.contentHash) else { throw ProjectStoreError.invalidManifest }
        let data = try files.read(projectURL(id, record.relativePath))
        guard ProjectDigest.hash(data) == record.contentHash else {
            throw ProjectStoreError.damagedFile(record.relativePath)
        }
        return data
    }

    func materialize(_ manifest: ProjectManifest) throws -> WritingProject {
        var documents: [WritingDocument] = []
        for record in manifest.documents {
            try Task.checkCancellation()
            let data = try verified(ProjectFileRecord(
                relativePath: record.relativePath, contentHash: record.contentHash), in: manifest.id)
            guard let body = String(data: data, encoding: .utf8) else {
                throw ProjectStoreError.damagedFile(record.relativePath)
            }
            documents.append(WritingDocument(id: record.id, title: record.title, body: body, kind: record.kind))
        }
        for record in manifest.assets {
            try Task.checkCancellation()
            _ = try verified(record.file, in: manifest.id)
        }
        if let source = manifest.legacySource { _ = try verified(source, in: manifest.id) }
        return WritingProject(id: manifest.id, title: manifest.title, mode: manifest.mode, documents: documents)
    }

    func loadUnlocked(id: WritingProjectID) throws -> WritingProject { try materialize(readManifest(id: id)) }

    func documentPath(id: WritingDocumentID, kind: WritingDocument.Kind, hash: String) -> String {
        "\(kind == .note ? "Notes" : "Documents")/\(id.rawValue.uuidString)/\(hash).md"
    }

    func writeImmutable(_ data: Data, path: String, id: WritingProjectID) throws {
        try Task.checkCancellation()
        let url = try projectURL(id, path)
        if files.fileExists(at: url) {
            guard try files.read(url) == data else { throw ProjectStoreError.damagedFile(path) }
            return
        }
        try files.createDirectory(at: url.deletingLastPathComponent())
        try files.writeAtomically(data, to: url)
        guard try files.read(url) == data else { throw ProjectStoreError.damagedFile(path) }
    }

    func saveUnlocked(_ project: WritingProject, importedAssets: [String: Data] = [:], source: Data? = nil) throws {
        guard Set(project.documents.map(\.id)).count == project.documents.count else {
            throw ProjectStoreError.invalidManifest
        }
        let manifestURL = try projectURL(project.id, "project.json")
        let oldData = files.fileExists(at: manifestURL) ? try files.read(manifestURL) : nil
        let old = oldData == nil ? nil : try readManifest(id: project.id)
        if let old { _ = try materialize(old) }
        for directory in ["Documents", "Notes", "Assets", "Intelligence", "UserData"] {
            try files.createDirectory(at: projectURL(project.id, directory))
        }
        var manifest = ProjectManifest(id: project.id, title: project.title, mode: project.mode, documents: [])
        manifest.assets = old?.assets ?? []
        manifest.legacySource = old?.legacySource
        for document in project.documents {
            let data = Data(document.body.utf8)
            let hash = ProjectDigest.hash(data)
            let path = documentPath(id: document.id, kind: document.kind, hash: hash)
            try writeImmutable(data, path: path, id: project.id)
            manifest.documents.append(ProjectDocumentRecord(
                id: document.id, title: document.title, kind: document.kind, relativePath: path, contentHash: hash))
        }
        for (reference, data) in importedAssets.sorted(by: { $0.key < $1.key }) {
            try ProjectPaths.validateRelative(reference)
            let hash = ProjectDigest.hash(data)
            let record = ProjectFileRecord(relativePath: "Assets/\(hash)", contentHash: hash)
            try writeImmutable(data, path: record.relativePath, id: project.id)
            manifest.assets.append(ProjectAssetRecord(reference: reference, file: record))
        }
        if let source {
            let hash = ProjectDigest.hash(source)
            let record = ProjectFileRecord(relativePath: "UserData/legacy-\(hash).json", contentHash: hash)
            try writeImmutable(source, path: record.relativePath, id: project.id)
            manifest.legacySource = record
        }
        // 검증은 최종 커밋 전에 끝낸다. 그 뒤 실패 보고로 성공한 저장을 오인시키지 않는다.
        _ = try materialize(manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        if data == oldData { return }
        if let oldData {
            try files.writeAtomically(oldData, to: projectURL(project.id, "previous-project.json"))
        }
        try Task.checkCancellation()
        try files.writeAtomically(data, to: manifestURL)
    }

    func activateUnlocked(id: WritingProjectID) throws {
        _ = try loadUnlocked(id: id)
        let data = try JSONEncoder().encode(id)
        try Task.checkCancellation()
        try files.writeAtomically(data, to: rootURL("active-project.json"))
    }
}
