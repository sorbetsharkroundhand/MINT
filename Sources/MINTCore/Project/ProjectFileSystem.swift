import Darwin
import Foundation

public protocol ProjectFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    /// 실패하면 기존 목적 파일이 그대로 남아야 한다.
    func writeAtomically(_ data: Data, to url: URL) throws
    func read(_ url: URL) throws -> Data
    func fileExists(at url: URL) -> Bool
}

public struct LocalProjectFileSystem: ProjectFileSystem {
    public init() {}
    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    public func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    public func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

enum ProjectPaths {
    static func validateRelative(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
            path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw ProjectStoreError.unsafePath(path) }
    }

    static func checked(_ relative: String, under root: URL) throws -> URL {
        try validateRelative(relative)
        try rejectSymlink(root)
        var url = root
        for component in relative.split(separator: "/") {
            url.appendPathComponent(String(component))
            try rejectSymlink(url)
        }
        return url
    }

    static func rejectSymlink(_ url: URL) throws {
        // fileExists는 끊어진 링크를 놓치므로 lstat 기반 속성을 직접 확인한다.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw ProjectStoreError.unsafePath(url.path)
        }
    }
}
