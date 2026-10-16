import Foundation

public struct WritingProviderOutcome: Sendable, Equatable {
    public enum Status: String, Sendable { case success, failed, unavailable }
    public enum Reason: String, Sendable { case provider, resource, unsupportedInput }
    public let providerID: String
    public let status: Status
    public let reason: Reason?
    public init(providerID: String, status: Status, reason: Reason? = nil) {
        self.providerID = providerID; self.status = status; self.reason = reason
    }
}

/// Optional provider-local error classification; no library error or manuscript excerpt crosses it.
protocol WritingDiagnosticsFailureClassifying: Sendable {
    func failureOutcome(_ error: any Error) -> WritingProviderOutcome
}

struct WritingDiagnosticsStamp: Hashable, Sendable {
    let runtime: ProjectRuntimeIdentity
    let nativeRevision: UInt64
    let profileRevision: UInt64
    let providerRevision: String
    let ruleRevision: Int
    let windowDigest: String
}

struct WritingDiagnosticsFinding: Identifiable, Sendable {
    let id: String
    var diagnostic: WritingDiagnostic
    var sourceRanges: [WritingDiagnosticRange]
    var relatedSourceRanges: [[WritingDiagnosticRange]]
    var evidence: EvidenceAnchor
    var relatedEvidence: [EvidenceAnchor] = []
    /// All input context can affect a pattern count, even outside representative evidence.
    var contextRange: WritingDiagnosticRange
    var stamp: WritingDiagnosticsStamp
}

struct WritingDiagnosticsCoverage: Sendable, Equatable {
    var assessed: [WritingDiagnosticRange] = []
    var dirty: [WritingDiagnosticRange] = []
    var pending: [WritingDiagnosticRange] = []
    var unsupported: [WritingDiagnosticRange] = []
    var isComplete = false
}

enum WritingDiagnosticsAvailability: String, Sendable {
    case available, unsupportedLanguage, unsupportedInput
    case unavailableResource, unavailableProvider, unavailableProfile, pausedPolicy
}

struct WritingDiagnosticsState: Sendable {
    enum Status: String, Sendable { case idle, checking, partial, unavailable, paused }
    var findings: [WritingDiagnosticsFinding] = []
    var coverage = WritingDiagnosticsCoverage()
    var availability = WritingDiagnosticsAvailability.available
    var status = Status.idle
}

protocol WritingDiagnosticsClock: Sendable { func sleep(for duration: Duration) async throws }
struct ContinuousWritingDiagnosticsClock: WritingDiagnosticsClock {
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
