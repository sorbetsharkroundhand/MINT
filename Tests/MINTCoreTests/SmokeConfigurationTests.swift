import XCTest
@testable import MINTCore

final class SmokeConfigurationTests: XCTestCase {
    @MainActor
    func testBundleSmokeStartsOfflineAfterModelChoice() throws {
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

        // 실제 설정 로더로 검증해야 키 변경·문자열 Bool 때문에 시트가 다시 뜨지 않는다.
        let settings = CompletionSettings(defaults: defaults)
        XCTAssertTrue(settings.initialModelConfirmed)
        XCTAssertFalse(settings.autocompleteEnabled)
    }
}
