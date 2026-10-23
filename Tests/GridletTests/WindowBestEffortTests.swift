import AppKit
import XCTest
@testable import Gridlet

/// A window with a large minimum size must still be moved to the closest
/// reachable frame instead of being refused outright.
@MainActor
final class WindowBestEffortTests: XCTestCase {
    private func screenBounds() throws -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let primaryTop = ScreenGeometry.primaryTopY(screens: NSScreen.screens)
        return ScreenGeometry.cocoaRectToAX(screen.visibleFrame, primaryTopY: primaryTop)
    }

    func testKeepsRequestedOriginWhenMinSizeWindowStillFits() throws {
        let bounds = try screenBounds()
        let requested = CGRect(x: bounds.minX + 10, y: bounds.minY + 10, width: 60, height: 40)
        let achieved = CGSize(width: 420, height: 300)

        let result = WindowTargetResolver.bestEffortFrame(
            requested: requested,
            achieved: CGRect(origin: requested.origin, size: achieved)
        )

        XCTAssertEqual(result.origin.x, requested.origin.x, accuracy: 0.5)
        XCTAssertEqual(result.origin.y, requested.origin.y, accuracy: 0.5)
        XCTAssertEqual(result.width, achieved.width, accuracy: 0.5)
        XCTAssertEqual(result.height, achieved.height, accuracy: 0.5)
    }

    func testPullsOversizedMinimumWindowBackInsideTheScreen() throws {
        let bounds = try screenBounds()
        // Bottom-right cell: a min-size window would overflow the display.
        let requested = CGRect(x: bounds.maxX - 40, y: bounds.maxY - 40, width: 40, height: 40)
        let achieved = CGSize(width: 420, height: 300)

        let result = WindowTargetResolver.bestEffortFrame(
            requested: requested,
            achieved: CGRect(origin: requested.origin, size: achieved)
        )

        XCTAssertGreaterThanOrEqual(result.minX, bounds.minX - 0.5)
        XCTAssertGreaterThanOrEqual(result.minY, bounds.minY - 0.5)
        XCTAssertLessThanOrEqual(result.maxX, bounds.maxX + 0.5)
        XCTAssertLessThanOrEqual(result.maxY, bounds.maxY + 0.5)
        XCTAssertEqual(result.width, achieved.width, accuracy: 0.5)
        XCTAssertEqual(result.height, achieved.height, accuracy: 0.5)
    }

    func testClampsWindowLargerThanTheDisplay() throws {
        let bounds = try screenBounds()
        let requested = CGRect(x: bounds.minX + 100, y: bounds.minY + 100, width: 50, height: 50)
        let achieved = CGSize(width: bounds.width + 600, height: bounds.height + 400)

        let result = WindowTargetResolver.bestEffortFrame(
            requested: requested,
            achieved: CGRect(origin: requested.origin, size: achieved)
        )

        XCTAssertLessThanOrEqual(result.width, bounds.width + 0.5)
        XCTAssertLessThanOrEqual(result.height, bounds.height + 0.5)
        XCTAssertGreaterThanOrEqual(result.minX, bounds.minX - 0.5)
        XCTAssertGreaterThanOrEqual(result.minY, bounds.minY - 0.5)
        XCTAssertLessThanOrEqual(result.maxX, bounds.maxX + 0.5)
        XCTAssertLessThanOrEqual(result.maxY, bounds.maxY + 0.5)
    }

    func testScreenBoundsAreAvailableAndNonEmpty() {
        XCTAssertNotNil(WindowTargetResolver.screenAXBounds(nearest: CGRect(x: 0, y: 0, width: 10, height: 10)))
    }
}
