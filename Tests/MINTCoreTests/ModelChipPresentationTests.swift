import XCTest

@testable import MINTCore

final class ModelChipPresentationTests: XCTestCase {
    func testToolbarLabelDescribesAutocompleteInsteadOfModelIdentity() {
        XCTAssertEqual(
            ModelChipPresentation.toolbarLabel(
                modelID: "mlx-community/Some-Technical-Model-4bit",
                stateText: "대기"),
            "자동완성 · 대기")
    }

    func testToolbarLabelPreservesActionableFailureState() {
        XCTAssertEqual(
            ModelChipPresentation.toolbarLabel(
                modelID: "custom/private-model",
                stateText: "오류"),
            "자동완성 · 오류")
    }
}


final class SettingsModelPresentationTests: XCTestCase {
    func testKnownPresetUsesFriendlyProductName() {
        XCTAssertEqual(
            SettingsModelPresentation.displayName(for: ModelChoice.basil.id),
            "Basil")
    }

    func testCustomRepositoryIsLabeledWithoutExposingRawIDInSummary() {
        XCTAssertEqual(
            SettingsModelPresentation.displayName(for: "private/custom-model"),
            "사용자 모델")
    }
}
