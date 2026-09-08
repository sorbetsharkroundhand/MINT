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

    func testNavigatorWidthRubberBandsBelowMinimumDuringCollapseDrag() {
        let atMinimum = WorkspaceLayoutState(navigatorWidth: 200)
            .navigatorWidth(in: 1180)
        let midway = WorkspaceLayoutState(navigatorWidth: 175)
            .navigatorWidth(in: 1180)
        let atThreshold = WorkspaceLayoutState(navigatorWidth: 150)
            .navigatorWidth(in: 1180)
        let beyondThreshold = WorkspaceLayoutState(navigatorWidth: 100)
            .navigatorWidth(in: 1180)

        XCTAssertLessThan(midway, atMinimum)
        XCTAssertGreaterThan(midway, 175)
        XCTAssertLessThan(atThreshold, midway)
        XCTAssertGreaterThan(atThreshold, 150)
        XCTAssertLessThan(beyondThreshold, atThreshold)
        XCTAssertGreaterThan(beyondThreshold, 100)
    }

    func testToolDockAutomaticAndSideFallbackPreservePreferenceSemantics() {
        let navWidth: CGFloat = 250

        XCTAssertEqual(
            WorkspaceLayoutState.effectiveToolDock(
                preferred: .automatic,
                availableWidth: 1180,
                navigatorVisible: true,
                navigatorWidth: navWidth),
            .right)

        XCTAssertEqual(
            WorkspaceLayoutState.effectiveToolDock(
                preferred: .automatic,
                availableWidth: 900,
                navigatorVisible: true,
                navigatorWidth: navWidth),
            .bottom)

        // A narrow-window fallback is computed only; the caller's persisted .left
        // preference is not mutated and will become effective again when width returns.
        XCTAssertEqual(
            WorkspaceLayoutState.effectiveToolDock(
                preferred: .left,
                availableWidth: 900,
                navigatorVisible: true,
                navigatorWidth: navWidth),
            .bottom)
        XCTAssertEqual(
            WorkspaceLayoutState.effectiveToolDock(
                preferred: .left,
                availableWidth: 1200,
                navigatorVisible: true,
                navigatorWidth: navWidth),
            .left)

        XCTAssertEqual(
            WorkspaceLayoutState.effectiveToolDock(
                preferred: .floating,
                availableWidth: 860,
                navigatorVisible: true,
                navigatorWidth: navWidth),
            .floating)
    }

    func testEditorialSurfaceIsOpaqueInBothAppearancesAndCustomPalettes() {
        for theme in [MintTheme.light, .dark, MintTheme.light.tinted(with: .lightDefault, dark: false),
                      MintTheme.dark.tinted(with: .darkDefault, dark: true)] {
            XCTAssertEqual(theme.editorSurface.alphaComponent, 1)
            XCTAssertGreaterThan(theme.activeLine.alphaComponent, 0)
        }
    }
}
