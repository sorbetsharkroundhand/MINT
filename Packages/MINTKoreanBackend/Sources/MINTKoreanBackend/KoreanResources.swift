import CryptoKit
import Foundation

enum KoreanResources {
    private static let expectedIndex = "26452c83698db31b3778c8ddf4fa77c851aa35bbe6559341944fb2c6dc270a38"
    private struct Index: Decodable {
        let schemaVersion: Int
        let backendVersion: String
        let sourceRevision: String
        let modelDirectory: String
        let files: [File]
        struct File: Decodable { let path: String; let sha256: String; let bytes: Int }
    }

    static func validate(_ resources: URL, admission: @Sendable () -> Bool) throws -> URL {
        do {
            guard admission() else { throw KoreanNativeError.cancelled }
            guard try resources.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw KoreanNativeError.unavailable
            }
            let root = resources.resolvingSymlinksInPath()
            let indexURL = try checkedURL(root: root, relative: "index.json")
            let data = try Data(contentsOf: indexURL)
            guard hex(SHA256.hash(data: data)) == expectedIndex else { throw KoreanNativeError.unavailable }
            let index = try JSONDecoder().decode(Index.self, from: data)
            guard index.schemaVersion == 1, index.backendVersion == "0.24.0",
                index.sourceRevision == "6e16bbcfc0940fabccbdde574abb4ea3a659588e" else {
                throw KoreanNativeError.unavailable
            }
            for file in index.files {
                guard admission() else { throw KoreanNativeError.cancelled }
                let url = try checkedURL(root: root, relative: file.path)
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard size == file.bytes, try hashFile(url, admission: admission) == file.sha256 else {
                    throw KoreanNativeError.unavailable
                }
            }
            return try checkedURL(root: root, relative: index.modelDirectory)
        } catch let error as KoreanNativeError { throw error }
        catch { throw KoreanNativeError.unavailable }
    }

    private static func checkedURL(root: URL, relative: String) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            !relative.contains("\\"), !relative.contains("\0") else { throw KoreanNativeError.unavailable }
        var next = root
        for part in parts {
            next.appendPathComponent(String(part))
            guard try next.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw KoreanNativeError.unavailable
            }
        }
        return next
    }

    private static func hashFile(_ url: URL, admission: @Sendable () -> Bool) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            guard admission() else { throw KoreanNativeError.cancelled }
            guard let block = try file.read(upToCount: 1_048_576), !block.isEmpty else { break }
            hash.update(data: block)
        }
        return hex(hash.finalize())
    }
    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
