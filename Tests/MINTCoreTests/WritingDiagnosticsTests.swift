import XCTest
@testable import MINTCore

private struct FixtureDiagnosticsProvider: WritingDiagnosticsProvider {
    let id: String
    let delayMilliseconds: Int
    let makeDiagnostics: @Sendable (WritingDiagnosticsRequest) -> [WritingDiagnostic]

    func analyze(_ request: WritingDiagnosticsRequest) async throws -> [WritingDiagnostic] {
        if delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        try Task.checkCancellation()
        return makeDiagnostics(request)
    }
}

final class WritingDiagnosticsTests: XCTestCase {
    private static func request(
        text: String = "문장",
        projectID: WritingProjectID = WritingProjectID(),
        documentID: WritingDocumentID = WritingDocumentID()
    ) -> WritingDiagnosticsRequest {
        WritingDiagnosticsRequest(
            projectID: projectID,
            documentID: documentID,
            text: text,
            languageTag: "ko",
            dirtyRange: WritingDiagnosticRange(location: 0, length: (text as NSString).length))
    }

    func testDiagnosticRangeUsesUTF16Coordinates() throws {
        let text = "한😀글"
        let swiftRange = try XCTUnwrap(text.range(of: "😀"))
        let nsRange = NSRange(swiftRange, in: text)
        XCTAssertEqual(nsRange.location, 1)
        XCTAssertEqual(nsRange.length, 2)

        let diagnosticRange = WritingDiagnosticRange(nsRange)
        XCTAssertEqual(diagnosticRange.nsRange, nsRange)
    }

    func testStyleProfileIsSeparateDurableValue() throws {
        let profile = WritingStyleProfile(
            ignoredRuleIDs: ["ko.style.repeated-ending"],
            learnedWords: ["MINT"],
            repetitionSensitivity: .high,
            dialogueSensitivity: .low)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WritingStyleProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertTrue(decoded.learnedWords.contains("MINT"))
    }

    func testEngineComposesProvidersFiltersIgnoredRulesAndDeduplicates() async {
        let duplicate = WritingDiagnostic(
            id: "same-occurrence",
            ruleID: "ko.style.repeated-ending",
            providerID: "p1",
            category: .style,
            kind: .repeatedEnding,
            severity: .suggestion,
            range: WritingDiagnosticRange(location: 8, length: 2),
            message: "Repeated ending",
            languageTag: "ko")

        let earlier = WritingDiagnostic(
            id: "earlier",
            ruleID: "ko.correctness.spacing",
            providerID: "p2",
            category: .correctness,
            kind: .spacing,
            severity: .correctness,
            range: WritingDiagnosticRange(location: 2, length: 1),
            message: "Spacing",
            languageTag: "ko")

        let ignored = WritingDiagnostic(
            id: "ignored",
            ruleID: "ko.style.ignored",
            providerID: "p2",
            category: .style,
            kind: .sentenceRhythm,
            severity: .suggestion,
            range: WritingDiagnosticRange(location: 1, length: 1),
            message: "Ignore me",
            languageTag: "ko")

        let engine = WritingDiagnosticsEngine(providers: [
            FixtureDiagnosticsProvider(id: "p1", delayMilliseconds: 0) { _ in [duplicate] },
            FixtureDiagnosticsProvider(id: "p2", delayMilliseconds: 0) { _ in
                [duplicate, earlier, ignored]
            },
        ])

        var req = Self.request()
        req.styleProfile.ignoredRuleIDs.insert("ko.style.ignored")
        let snapshot = await engine.analyze(req)

        XCTAssertEqual(snapshot?.diagnostics.map(\.id), ["earlier", "same-occurrence"])
    }

    func testNewerAnalysisCancelsAndSuppressesStaleGeneration() async {
        let projectID = WritingProjectID()
        let firstDocument = WritingDocumentID()
        let secondDocument = WritingDocumentID()

        let provider = FixtureDiagnosticsProvider(
            id: "delayed",
            delayMilliseconds: 120
        ) { request in
            [
                WritingDiagnostic(
                    id: request.documentID.rawValue.uuidString,
                    ruleID: "fixture",
                    providerID: "delayed",
                    category: .style,
                    kind: .sentenceRhythm,
                    severity: .suggestion,
                    range: WritingDiagnosticRange(location: 0, length: 1),
                    message: request.text,
                    languageTag: request.languageTag)
            ]
        }
        let engine = WritingDiagnosticsEngine(providers: [provider])

        let firstRequest = Self.request(
            text: "old", projectID: projectID, documentID: firstDocument)
        let secondRequest = Self.request(
            text: "new", projectID: projectID, documentID: secondDocument)

        async let first = engine.analyze(firstRequest)
        try? await Task.sleep(for: .milliseconds(20))
        let second = await engine.analyze(secondRequest)
        let stale = await first

        XCTAssertNil(stale)
        XCTAssertEqual(second?.documentID, secondDocument)
        XCTAssertEqual(second?.diagnostics.first?.message, "new")
    }

    func testExplicitCancelPreventsPublication() async {
        let provider = FixtureDiagnosticsProvider(id: "slow", delayMilliseconds: 150) { _ in [] }
        let engine = WritingDiagnosticsEngine(providers: [provider])
        let pendingRequest = Self.request()

        async let pending = engine.analyze(pendingRequest)
        try? await Task.sleep(for: .milliseconds(20))
        await engine.cancel()

        let cancelledResult = await pending
        XCTAssertNil(cancelledResult)
    }
}
