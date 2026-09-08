import Foundation

public enum WritingDiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case correctness
    case style
    case vocabulary
}

public enum WritingDiagnosticKind: String, Codable, CaseIterable, Sendable {
    case spelling
    case spacing
    case grammar

    case repeatedWord
    case repeatedParticle
    case repeatedEnding
    case repeatedConnector
    case redundantConnector
    case connectiveChain
    case repeatedSentenceStart
    case sentenceLength
    case sentenceRhythm

    case vagueWord
    case overusedWord
    case wordAlternative
}

public enum WritingDiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    /// Informational pattern; normally Review-only.
    case info
    /// Non-blocking writing suggestion; normally Living Margin / Review.
    case suggestion
    /// High-confidence correctness issue eligible for a subtle inline mark.
    case correctness
}

/// UTF-16 range used by NSTextView/NSRange without leaking AppKit into the core model.
public struct WritingDiagnosticRange: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

public struct WritingDiagnostic: Identifiable, Codable, Hashable, Sendable {
    /// Stable rule/provider-owned identity for this occurrence.
    public var id: String
    public var ruleID: String
    public var providerID: String
    public var category: WritingDiagnosticCategory
    public var kind: WritingDiagnosticKind
    public var severity: WritingDiagnosticSeverity
    public var range: WritingDiagnosticRange
    /// Other occurrences that explain a repetition/relationship.
    public var relatedRanges: [WritingDiagnosticRange]
    public var message: String
    public var reason: String?
    public var confidence: Double?
    public var alternatives: [String]
    /// BCP-47 style language tag such as "ko", "en", "ja".
    public var languageTag: String

    public init(
        id: String,
        ruleID: String,
        providerID: String,
        category: WritingDiagnosticCategory,
        kind: WritingDiagnosticKind,
        severity: WritingDiagnosticSeverity,
        range: WritingDiagnosticRange,
        relatedRanges: [WritingDiagnosticRange] = [],
        message: String,
        reason: String? = nil,
        confidence: Double? = nil,
        alternatives: [String] = [],
        languageTag: String
    ) {
        self.id = id
        self.ruleID = ruleID
        self.providerID = providerID
        self.category = category
        self.kind = kind
        self.severity = severity
        self.range = range
        self.relatedRanges = relatedRanges
        self.message = message
        self.reason = reason
        self.confidence = confidence
        self.alternatives = alternatives
        self.languageTag = languageTag
    }
}

public enum WritingQualitySensitivity: String, Codable, CaseIterable, Sendable {
    case off
    case low
    case standard
    case high
}

/// Durable proofreading preferences. This is intentionally separate from User Canon.
public struct WritingStyleProfile: Codable, Equatable, Sendable {
    public var ignoredRuleIDs: Set<String>
    public var learnedWords: Set<String>
    public var repetitionSensitivity: WritingQualitySensitivity
    public var dialogueSensitivity: WritingQualitySensitivity

    public init(
        ignoredRuleIDs: Set<String> = [],
        learnedWords: Set<String> = [],
        repetitionSensitivity: WritingQualitySensitivity = .standard,
        dialogueSensitivity: WritingQualitySensitivity = .standard
    ) {
        self.ignoredRuleIDs = ignoredRuleIDs
        self.learnedWords = learnedWords
        self.repetitionSensitivity = repetitionSensitivity
        self.dialogueSensitivity = dialogueSensitivity
    }
}

public enum WritingDiagnosticsScope: String, Codable, Sendable {
    /// Dirty sentence/paragraph window used during normal editing.
    case local
    /// Explicit full-document analysis used by Review/background work.
    case document
}

public struct WritingDiagnosticsRequest: Sendable {
    public var projectID: WritingProjectID
    public var documentID: WritingDocumentID
    public var text: String
    public var languageTag: String
    public var scope: WritingDiagnosticsScope
    public var dirtyRange: WritingDiagnosticRange?
    public var styleProfile: WritingStyleProfile

    public init(
        projectID: WritingProjectID,
        documentID: WritingDocumentID,
        text: String,
        languageTag: String,
        scope: WritingDiagnosticsScope = .local,
        dirtyRange: WritingDiagnosticRange? = nil,
        styleProfile: WritingStyleProfile = WritingStyleProfile()
    ) {
        self.projectID = projectID
        self.documentID = documentID
        self.text = text
        self.languageTag = languageTag
        self.scope = scope
        self.dirtyRange = dirtyRange
        self.styleProfile = styleProfile
    }
}

/// Language/NLP libraries live behind this boundary. Core diagnostics never expose Kiwi
/// or any other provider-specific token/POS type.
public protocol WritingDiagnosticsProvider: Sendable {
    var id: String { get }
    func analyze(_ request: WritingDiagnosticsRequest) async throws -> [WritingDiagnostic]
}

public struct WritingDiagnosticsSnapshot: Sendable {
    public var generation: UInt64
    public var projectID: WritingProjectID
    public var documentID: WritingDocumentID
    public var diagnostics: [WritingDiagnostic]

    public init(
        generation: UInt64,
        projectID: WritingProjectID,
        documentID: WritingDocumentID,
        diagnostics: [WritingDiagnostic]
    ) {
        self.generation = generation
        self.projectID = projectID
        self.documentID = documentID
        self.diagnostics = diagnostics
    }
}

/// Cancellable, generation-scoped provider coordinator.
///
/// This actor does not know about NSTextView, Fiction, disk storage, or MLX. A newer edit
/// cancels the previous analysis; even an uncooperative provider cannot publish a stale
/// snapshot because generation ownership is checked after the awaited work completes.
public actor WritingDiagnosticsEngine {
    private let providers: [any WritingDiagnosticsProvider]
    private var generation: UInt64 = 0
    private var activeTask: Task<WritingDiagnosticsSnapshot?, Never>?

    public init(providers: [any WritingDiagnosticsProvider]) {
        self.providers = providers
    }

    public func analyze(_ request: WritingDiagnosticsRequest) async
        -> WritingDiagnosticsSnapshot?
    {
        generation &+= 1
        let ownedGeneration = generation

        activeTask?.cancel()
        let providers = self.providers

        let task = Task<WritingDiagnosticsSnapshot?, Never> {
            let diagnostics = await withTaskGroup(
                of: [WritingDiagnostic].self,
                returning: [WritingDiagnostic].self
            ) { group in
                for provider in providers {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let result = try await provider.analyze(request)
                            try Task.checkCancellation()
                            return result
                        } catch {
                            // Provider failure is isolated. Cancellation is still observed
                            // by the parent task and by generation ownership below.
                            return []
                        }
                    }
                }

                var merged: [WritingDiagnostic] = []
                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        return []
                    }
                    merged.append(contentsOf: result)
                }
                return merged
            }

            guard !Task.isCancelled else { return nil }
            return WritingDiagnosticsSnapshot(
                generation: ownedGeneration,
                projectID: request.projectID,
                documentID: request.documentID,
                diagnostics: Self.normalized(diagnostics, profile: request.styleProfile))
        }

        activeTask = task
        let snapshot = await task.value

        guard generation == ownedGeneration else { return nil }
        activeTask = nil
        return snapshot
    }

    public func cancel() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    nonisolated private static func normalized(
        _ diagnostics: [WritingDiagnostic],
        profile: WritingStyleProfile
    ) -> [WritingDiagnostic] {
        var seen = Set<String>()
        return diagnostics
            .filter { !profile.ignoredRuleIDs.contains($0.ruleID) }
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.range.location != $1.range.location {
                    return $0.range.location < $1.range.location
                }
                if $0.range.length != $1.range.length {
                    return $0.range.length < $1.range.length
                }
                return $0.id < $1.id
            }
    }
}
