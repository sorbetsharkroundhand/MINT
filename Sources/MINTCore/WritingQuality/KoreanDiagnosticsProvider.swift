import Foundation

actor KoreanDiagnosticsProvider: WritingDiagnosticsProvider {
    nonisolated let id = KoreanCorrectnessRules.providerID
    nonisolated static let ruleRevision = KoreanCorrectnessRules.revision
    private let morphology: KoreanMorphology

    init(morphology: KoreanMorphology) { self.morphology = morphology }

    func analyze(_ request: WritingDiagnosticsRequest) async throws -> [WritingDiagnostic] {
        try Task.checkCancellation()
        guard request.languageTag.lowercased().split(separator: "-").first == "ko" else { return [] }
        let analysis = try await morphology.analyze(request.text)
        try Task.checkCancellation()
        guard analysis.unsupportedRanges.isEmpty else { throw KoreanMorphologyError.unsupportedInput }
        let diagnostics = KoreanCorrectnessRules.evaluate(analysis, profile: request.styleProfile)
        try Task.checkCancellation()
        return diagnostics
    }
}
