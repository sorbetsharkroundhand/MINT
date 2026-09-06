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

    func testEditorialSurfaceIsOpaqueInBothAppearancesAndCustomPalettes() {
        for theme in [MintTheme.light, .dark, MintTheme.light.tinted(with: .lightDefault, dark: false),
                      MintTheme.dark.tinted(with: .darkDefault, dark: true)] {
            XCTAssertEqual(theme.editorSurface.alphaComponent, 1)
            XCTAssertGreaterThan(theme.activeLine.alphaComponent, 0)
        }
    }
}
