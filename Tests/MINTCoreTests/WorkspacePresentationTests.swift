import XCTest
@testable import MINTCore

final class WorkspacePresentationTests: XCTestCase {
    func testSnapshotValidatesToolsAndDockWithoutMutatingInputs() {
        for (raw, expected) in [("bible", SidebarSection.bible), ("timeline", .narrative), ("context", .context)] {
            let state = snapshot(section: raw, dock: "left")
            XCTAssertEqual(state.toolSection, expected)
            XCTAssertEqual(state.toolDock, .left)
            XCTAssertEqual(state.rawToolSection, raw)
            XCTAssertEqual(state.rawToolDock, "left")
            XCTAssertFalse(state.navigatorVisible)
            XCTAssertEqual(state.navigatorWidth, -10)
            XCTAssertTrue(state.chromeHidden)
        }
        for raw in ["files", "margin", "unknown"] {
            let state = snapshot(section: raw, dock: "invalid")
            XCTAssertNil(state.toolSection)
            XCTAssertEqual(state.toolDock, .automatic)
            XCTAssertEqual(state.rawToolSection, raw)
            XCTAssertEqual(state.rawToolDock, "invalid")
        }
    }

    private func snapshot(section: String, dock: String) -> WorkspacePresentationState {
        WorkspacePresentationState(navigatorVisible: false, navigatorWidth: -10,
            rawToolSection: section, rawToolDock: dock, chromeHidden: true)
    }
}
