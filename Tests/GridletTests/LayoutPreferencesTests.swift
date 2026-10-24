import AppKit
import XCTest
@testable import Gridlet

@MainActor
final class LayoutPreferencesTests: XCTestCase {

    // MARK: - Edge gap geometry

    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    private func frame(_ selection: GridSelection, gap: CGFloat) -> CGRect {
        ScreenGeometry.cocoaFrame(
            for: selection, rows: 8, columns: 8, visibleFrame: screen, gap: gap
        )!
    }

    func testZeroGapLeavesTheFrameUntouched() {
        let sel = GridSelection(rowStart: 0, rowEnd: 3, colStart: 0, colEnd: 3)
        let plain = frame(sel, gap: 0)
        XCTAssertEqual(plain, CGRect(x: 0, y: 500, width: 800, height: 500))
    }

    func testGapInsetsEverySide() {
        let sel = GridSelection(rowStart: 0, rowEnd: 3, colStart: 0, colEnd: 3)
        let inset = frame(sel, gap: 10)
        XCTAssertEqual(inset.origin.x, 10, accuracy: 0.01)
        XCTAssertEqual(inset.origin.y, 510, accuracy: 0.01)
        XCTAssertEqual(inset.width, 780, accuracy: 0.01)
        XCTAssertEqual(inset.height, 480, accuracy: 0.01)
    }

    func testAdjacentSelectionsEndUpTwoGapsApart() {
        let left = frame(GridSelection(rowStart: 0, rowEnd: 7, colStart: 0, colEnd: 3), gap: 8)
        let right = frame(GridSelection(rowStart: 0, rowEnd: 7, colStart: 4, colEnd: 7), gap: 8)
        // Each gives up one gap on the shared edge, so the visible gap between windows is 16pt.
        XCTAssertEqual(right.minX - left.maxX, 16, accuracy: 0.01)
        // ...and the outer edges sit one gap from the screen edge.
        XCTAssertEqual(left.minX, 8, accuracy: 0.01)
        XCTAssertEqual(right.maxX, screen.maxX - 8, accuracy: 0.01)
    }

    func testGapNeverCollapsesASelection() {
        let tiny = frame(GridSelection(rowStart: 0, rowEnd: 0, colStart: 0, colEnd: 0), gap: 200)
        XCTAssertGreaterThan(tiny.width, 0)
        XCTAssertGreaterThan(tiny.height, 0)
    }

    func testGapSurvivesTheAXConversion() {
        let model = ScreenGeometryModel(visibleFrame: screen, primaryTopY: 1000)
        let cocoa = model.cocoaFrame(for: GridSelection(rowStart: 0, rowEnd: 3, colStart: 0, colEnd: 3), rows: 8, columns: 8)!
        let ax = model.axFrame(for: GridSelection(rowStart: 0, rowEnd: 3, colStart: 0, colEnd: 3), rows: 8, columns: 8)!
        XCTAssertEqual(ax.origin.y, 1000 - cocoa.maxY, accuracy: 0.01)
    }

    // MARK: - Settings

    private func snapshot() -> GridSettings.Snapshot {
        var snap = GridSettings.Snapshot()
        snap.rows = 8
        snap.columns = 8
        return snap
    }

    func testGapAndDisplayGridsRoundTripThroughDisk() {
        var snap = snapshot()
        snap.gap = 6
        snap.setGrid(GridSettings.DisplayGrid(rows: 4, columns: 12), for: "Main")
        let data = try! JSONEncoder().encode(snap)
        let restored = GridSettings.migrate(from: data)
        XCTAssertEqual(restored.gap, 6)
        XCTAssertEqual(restored.grid(for: "Main"), GridSettings.DisplayGrid(rows: 4, columns: 12))
        XCTAssertEqual(restored.grid(for: "OTHER"), GridSettings.DisplayGrid(rows: 8, columns: 8))
        XCTAssertTrue(restored.hasOverride(for: "Main"))
        XCTAssertFalse(restored.hasOverride(for: "OTHER"))
    }

    func testLegacyJSONWithoutGapOrOverridesStillLoads() {
        let legacy = Data("{\"rows\":5,\"columns\":7,\"keepPanelOpen\":true}".utf8)
        let snap = GridSettings.migrate(from: legacy)
        XCTAssertEqual(snap.rows, 5)
        XCTAssertEqual(snap.columns, 7)
        XCTAssertEqual(snap.gap, 0, "a missing gap must default to none, not fail the load")
        XCTAssertTrue(snap.displayGrids.isEmpty)
        XCTAssertTrue(snap.keepPanelOpen)
    }

    func testGapAndPerDisplayGridsAreClamped() {
        let json = Data("""
        {"rows":8,"columns":8,"gap":900,"displayGrids":{"Main":{"rows":99,"columns":0}}}
        """.utf8)
        let snap = GridSettings.migrate(from: json)
        XCTAssertEqual(snap.gap, GridSettings.maxGap)
        XCTAssertEqual(snap.grid(for: "Main"), GridSettings.DisplayGrid(rows: GridSettings.maxGrid, columns: GridSettings.minGrid))
    }

    func testOverrideCanBeCleared() {
        var snap = snapshot()
        snap.setGrid(GridSettings.DisplayGrid(rows: 3, columns: 3), for: "Main")
        snap.clearOverride(for: "Main")
        XCTAssertFalse(snap.hasOverride(for: "Main"))
        XCTAssertEqual(snap.grid(for: "Main").columns, 8)
    }

    func testDefaultGridIsUsedWhenNoOverride() {
        var snap = snapshot()
        snap.rows = 6
        snap.columns = 10
        XCTAssertEqual(snap.grid(for: "UNKNOWN"), GridSettings.DisplayGrid(rows: 6, columns: 10))
    }
}
