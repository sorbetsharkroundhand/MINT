import AppKit

struct WritingCorrection: Sendable {
    let finding: WritingDiagnosticsFinding
    let expectedSource: String
    let expectedNative: String
    let replacement: String

    /// A word/phrase action cannot introduce native Markdown structure or controls.
    var hasPlainReplacement: Bool {
        let syntax = CharacterSet(charactersIn: #"`*_~$#<>[]\"#)
        guard replacement.utf16.count <= 4096,
              !replacement.unicodeScalars.contains(where: {
                  syntax.contains($0) || CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
              }) else { return false }
        return replacement.range(of: #"^\s*(?:[-+]|\d+\.)(?:\s|$)"#, options: .regularExpression) == nil
    }
}

enum WritingCorrectionRefusal: Sendable, Equatable { case stale, composing, unmapped, ambiguous, formatting }
enum WritingCorrectionResult: Sendable, Equatable {
    case applied
    case refused(reason: WritingCorrectionRefusal)
}


/// Explicit user actions resolve the current finding, alternative and native owner together.
@MainActor
final class WritingDiagnosticsActions {
    private let controller: WritingDiagnosticsController
    private let editor: () -> BlockTextView?
    private let currentSnapshot: () -> ProjectDocumentSnapshot?
    private let session: ProjectSession?
    init(controller: WritingDiagnosticsController, editor: @escaping () -> BlockTextView?,
         currentSnapshot: @escaping () -> ProjectDocumentSnapshot?, session: ProjectSession? = nil) {
        self.controller = controller; self.editor = editor; self.currentSnapshot = currentSnapshot; self.session = session
    }
    @discardableResult
    func perform(_ action: MarginAction, findingID: String) throws -> WritingCorrectionResult? {
        guard let finding = controller.currentFinding(id: findingID), let snapshot = currentSnapshot(),
              snapshot.identity == finding.stamp.runtime, editor()?.hasMarkedText() != true,
              let binding = WritingDiagnosticsPresentation.bindings(for: finding).first(where: { $0.action == action }) else {
            throw WritingDiagnosticsActionError.stale
        }
        if case .apply(let index) = binding.operation { return apply(findingID: findingID, alternativeIndex: index) }
        guard let session, session.runtimeIdentity == snapshot.identity,
              case .ready(var record) = WritingStyleRepository.read(snapshot) else { throw WritingDiagnosticsActionError.stale }
        switch binding.operation {
        case .apply: break
        case .disableRule: record.profile.ignoredRuleIDs.insert(finding.diagnostic.ruleID)
        case .learnWord(let word): record.profile.learnedWords.insert(word)
        case .intentional:
            guard let first = finding.sourceRanges.first, let last = finding.sourceRanges.last else { throw WritingDiagnosticsActionError.stale }
            let range = WritingDiagnosticRange(location: first.location, length: last.location + last.length - first.location)
            let occurrence = try WritingStyleRepository.captureIntentional(ruleID: finding.diagnostic.ruleID, range: range, in: snapshot)
            guard occurrence.evidence.quote.utf16.elementsEqual(finding.evidence.quote.utf16) else { throw WritingDiagnosticsActionError.stale }
            guard controller.rememberExplicitSourceRevision(occurrence.sourceRevision, stamp: finding.stamp) else {
                throw WritingDiagnosticsActionError.stale
            }
            if !record.intentionalOccurrences.contains(occurrence) { record.intentionalOccurrences.append(occurrence) }
        }
        try WritingStyleRepository.update(record, in: session, identity: snapshot.identity)
        return nil
    }
    func apply(findingID: String, alternativeIndex: Int) -> WritingCorrectionResult {
        func refuse(_ reason: WritingCorrectionRefusal) -> WritingCorrectionResult {
            controller.requestRecheck(findingID: findingID)
            return .refused(reason: reason)
        }
        guard let editor = editor() else { return refuse(.stale) }
        if editor.hasMarkedText() { return refuse(.composing) }
        guard let finding = controller.currentFinding(id: findingID), let snapshot = currentSnapshot(),
              snapshot.identity == finding.stamp.runtime, editor.writingRuntimeIdentityProvider?() == snapshot.identity,
              editor.writingNativeRevision == finding.stamp.nativeRevision,
              finding.diagnostic.alternatives.indices.contains(alternativeIndex) else { return refuse(.stale) }
        guard finding.sourceRanges.count == 1, let source = finding.sourceRanges.first else { return refuse(.ambiguous) }
        guard let native = editor.nativeRange(forSource: source, revision: finding.stamp.nativeRevision) else { return refuse(.unmapped) }
        let expectedNative = (editor.string as NSString).substring(with: native.nsRange)
        let correction = WritingCorrection(finding: finding, expectedSource: finding.evidence.quote, expectedNative: expectedNative,
            replacement: finding.diagnostic.alternatives[alternativeIndex])
        let result = editor.applyWritingCorrection(correction, identity: snapshot.identity)
        if case .refused = result { controller.requestRecheck(findingID: findingID) }
        return result
    }
}

enum WritingDiagnosticsActionError: Error { case stale }
