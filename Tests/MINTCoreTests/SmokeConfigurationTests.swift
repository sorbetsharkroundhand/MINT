import XCTest
@testable import MINTCore

final class SmokeConfigurationTests: XCTestCase {
    @MainActor
    func testBundleSmokeStartsOfflineWithoutModelSetup() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(
            "scripts/fixtures/smoke-preferences.plist"))
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])
        let suiteName = "MINT-smoke-settings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.setPersistentDomain(values, forName: suiteName)

        // The legacy smoke fixture remains offline and migrates without presenting a model gate.
        let settings = CompletionSettings(defaults: defaults)
        XCTAssertEqual(settings.authorization, .disabled)
        XCTAssertFalse(settings.autocompleteEnabled)
    }
}
