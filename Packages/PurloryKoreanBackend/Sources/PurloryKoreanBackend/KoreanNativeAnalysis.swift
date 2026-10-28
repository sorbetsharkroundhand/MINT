import Foundation

public enum KoreanNativeError: Error, Equatable, Sendable {
    case unavailable, invalidInput, cancelled
}

public struct KoreanNativeToken: Sendable, Equatable {
    public let form: String
    public let tag: String
    public let range: NSRange
    public init(form: String, tag: String, range: NSRange) {
        self.form = form; self.tag = tag; self.range = range
    }
}

public struct KoreanNativeCandidate: Sendable, Equatable {
    public let originalRange: NSRange
    public let replacement: String
    public let origin: String
    public init(originalRange: NSRange, replacement: String, origin: String) {
        self.originalRange = originalRange; self.replacement = replacement; self.origin = origin
    }
}

public struct KoreanNativeAnalysis: Sendable, Equatable {
    public let tokens: [KoreanNativeToken]
    public let sentences: [NSRange]
    /// Uncalibrated native candidates. A production rule must prove a safe local change.
    public let candidates: [KoreanNativeCandidate]
    public init(tokens: [KoreanNativeToken], sentences: [NSRange], candidates: [KoreanNativeCandidate]) {
        self.tokens = tokens; self.sentences = sentences; self.candidates = candidates
    }
}

protocol KoreanNativeFactory: Sendable {
    func open(resources: URL, admission: @Sendable () -> Bool) throws -> any KoreanNativeHandle
}

protocol KoreanNativeHandle: AnyObject {
    func analyze(_ text: String, admission: @Sendable () -> Bool) throws -> KoreanNativeAnalysis
    func close()
}
