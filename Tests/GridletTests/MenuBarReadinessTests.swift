import XCTest
@testable import Gridlet

final class MenuBarReadinessTests: XCTestCase {
    func testStatusTitles() {
        XCTAssertEqual(
            MenuBarReadiness.statusMenuTitle(for: .ready),
            "Gridlet — Ready"
        )
        XCTAssertEqual(
            MenuBarReadiness.statusMenuTitle(for: .accessibilityNeeded),
            "Accessibility needed"
        )
        XCTAssertEqual(
            MenuBarReadiness.statusMenuTitle(for: .shortcutUnavailable),
            "Shortcut unavailable"
        )
    }

    func testStatusFromInjectedReadiness() {
        XCTAssertEqual(
            MenuBarReadiness.status(accessibilityTrusted: false, hotKeyRegistered: true),
            .accessibilityNeeded
        )
        XCTAssertEqual(
            MenuBarReadiness.status(accessibilityTrusted: true, hotKeyRegistered: false),
            .shortcutUnavailable
        )
        XCTAssertEqual(
            MenuBarReadiness.status(accessibilityTrusted: true, hotKeyRegistered: true),
            .ready
        )
    }

}
