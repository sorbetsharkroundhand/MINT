import AppKit
import SwiftUI
import XCTest

@testable import MINTCore

@MainActor
final class ShortcutHintPresentationTests: XCTestCase {
    func testGhostTeachingAppearsOnlyWhileASuggestionIsAvailable() {
        let host = NSHostingView(rootView: ShortcutHintPill(active: false, theme: .light))
        XCTAssertEqual(host.fittingSize.height, 0, "Idle writing must not reserve space for teaching chrome")

        host.rootView = ShortcutHintPill(active: true, theme: .light)
        XCTAssertGreaterThan(host.fittingSize.height, 0)

        host.rootView = ShortcutHintPill(active: false, theme: .light)
        XCTAssertEqual(host.fittingSize.height, 0, "Accepting or rejecting a suggestion removes the hint")
    }
}
