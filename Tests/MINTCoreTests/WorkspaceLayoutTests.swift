import XCTest
@testable import MINTCore

final class WorkspaceLayoutTests: XCTestCase {
    func testNavigatorWidthLeavesRoomForEditorAndSurvivesCollapse() {
        let layout = WorkspaceLayoutState(navigatorWidth: 340)
        XCTAssertEqual(layout.navigatorWidth(in: 860), 300)
        XCTAssertEqual(layout.navigatorWidth(in: 1180), 340)
        XCTAssertEqual(WorkspaceLayoutState(navigatorWidth: -10).navigatorWidth(in: 1180), 200)
        XCTAssertEqual(WorkspaceLayoutState(navigatorWidth: .infinity).navigatorWidth(in: 1180), 250)
    }

    func testNavigatorCollapseUsesHysteresis() {
        XCTAssertFalse(
            WorkspaceLayoutState.navigatorCollapseArmed(
                projectedWidth: 170, wasArmed: false))
        XCTAssertTrue(
            WorkspaceLayoutState.navigatorCollapseArmed(
                projectedWidth: 150, wasArmed: false))

        // Once armed, a small reverse movement does not flicker the state off.
        XCTAssertTrue(
            WorkspaceLayoutState.navigatorCollapseArmed(
                projectedWidth: 170, wasArmed: true))
        XCTAssertFalse(
            WorkspaceLayoutState.navigatorCollapseArmed(
                projectedWidth: 176, wasArmed: true))
    }

    func testEditorialSurfaceIsOpaqueInBothAppearancesAndCustomPalettes() {
        for theme in [MintTheme.light, .dark, MintTheme.light.tinted(with: .lightDefault, dark: false),
                      MintTheme.dark.tinted(with: .darkDefault, dark: true)] {
            XCTAssertEqual(theme.editorSurface.alphaComponent, 1)
            XCTAssertGreaterThan(theme.activeLine.alphaComponent, 0)
        }
    }
}
