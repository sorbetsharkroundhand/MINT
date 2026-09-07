import XCTest
@testable import MINTCore

final class WindowChromeGeometryTests: XCTestCase {
    func testMissingWindowGeometryUsesDesignPadding() {
        XCTAssertEqual(
            WindowChromeGeometry.leadingContentInset(trafficLightMaxX: nil),
            WindowChromeGeometry.navigatorBaseLeadingPadding)
        XCTAssertEqual(
            WindowChromeGeometry.leadingContentInset(trafficLightMaxX: 0),
            WindowChromeGeometry.navigatorBaseLeadingPadding)
    }

    func testMeasuredTrafficLightsDefineLeadingSafeRegion() {
        XCTAssertEqual(
            WindowChromeGeometry.leadingContentInset(trafficLightMaxX: 68),
            80)
    }

    func testTinyMeasuredValueNeverShrinksDesignPadding() {
        XCTAssertEqual(
            WindowChromeGeometry.leadingContentInset(trafficLightMaxX: 2),
            WindowChromeGeometry.navigatorBaseLeadingPadding)
    }
}
