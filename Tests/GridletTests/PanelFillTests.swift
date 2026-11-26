import AppKit
import XCTest
@testable import Gridlet

/// The one-click "fill the grid" control: the whole display, via the same apply path as a
/// full drag (so the edge gap and the minimum-size handling come along for free).
final class PanelFillTests: XCTestCase {
    func testFullSelectionCoversEveryCell() {
        let full = GridSelection.full(rows: 8, columns: 6)
        XCTAssertEqual(full?.rowStart, 0)
        XCTAssertEqual(full?.rowEnd, 7)
        XCTAssertEqual(full?.colStart, 0)
        XCTAssertEqual(full?.colEnd, 5)
        XCTAssertNil(GridSelection.full(rows: 0, columns: 8))
        XCTAssertNil(GridSelection.full(rows: 8, columns: 0))
    }

    func testFullSelectionMapsToTheWholeVisibleFrame() {
        let visible = CGRect(x: 0, y: 25, width: 3360, height: 1865)
        let full = try? XCTUnwrap(GridSelection.full(rows: 8, columns: 8))
        guard let full else { return XCTFail("no full selection") }

        let raw = ScreenGeometry.cocoaFrame(for: full, rows: 8, columns: 8, visibleFrame: visible)
        XCTAssertEqual(raw, visible)

        // With a gap the whole display shrinks by the gap on every side, exactly as a
        // full-grid drag does.
        let inset = ScreenGeometry.cocoaFrame(
            for: full, rows: 8, columns: 8, visibleFrame: visible, gap: 8
        )
        XCTAssertEqual(inset, visible.insetBy(dx: 8, dy: 8))
    }

    @MainActor
    func testFillButtonIsWiredAndFollowsTheTarget() {
        guard let screen = NSScreen.main else {
            XCTFail("no main screen")
            return
        }
        let panel = GridPanelController(screen: screen)
        let button = panel.fillButtonForTests

        XCTAssertEqual(button.accessibilityIdentifier(), "gridlet-fill-grid")
        XCTAssertNotNil(button.image, "the control needs an SF Symbol")
        XCTAssertNotNil(button.target, "the button must be wired to the panel")
        XCTAssertNotNil(button.action)
        XCTAssertEqual(button.toolTip, "Fill the grid")
        XCTAssertFalse(button.isBordered, "chrome buttons are borderless icons")

        panel.configure(settings: GridSettings.Snapshot(), target: nil, displayMode: .snapshotIdle)
        XCTAssertTrue(button.isEnabled, "a released snapshot shows the control available")

        panel.configure(settings: GridSettings.Snapshot(), target: nil, displayMode: .snapshotNoTarget)
        XCTAssertFalse(button.isEnabled, "with no target there is nothing to fill")
    }
}
