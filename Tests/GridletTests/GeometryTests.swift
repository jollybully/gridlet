import CoreGraphics
import XCTest
@testable import Gridlet

final class GeometryTests: XCTestCase {
    func testInclusiveSingleCell() {
        let sel = GridSelection.fromDrag(startRow: 2, startCol: 3, endRow: 2, endCol: 3, rows: 8, columns: 8)!
        XCTAssertEqual(sel.rowStart, 2)
        XCTAssertEqual(sel.rowEnd, 2)
        XCTAssertEqual(sel.colStart, 3)
        XCTAssertEqual(sel.colEnd, 3)
    }

    func testReverseDragNormalizes() {
        let sel = GridSelection.fromDrag(startRow: 5, startCol: 6, endRow: 1, endCol: 2, rows: 8, columns: 8)!
        XCTAssertEqual(sel.rowStart, 1)
        XCTAssertEqual(sel.rowEnd, 5)
        XCTAssertEqual(sel.colStart, 2)
        XCTAssertEqual(sel.colEnd, 6)
    }

    func testSubdividedReverseDragNormalizes() {
        let sel = GridSelection.fromDrag(startRow: 7, startCol: 5, endRow: 2, endCol: 1, rows: 16, columns: 16)!
        XCTAssertEqual(sel.rowStart, 2)
        XCTAssertEqual(sel.rowEnd, 7)
        XCTAssertEqual(sel.colStart, 1)
        XCTAssertEqual(sel.colEnd, 5)
    }

    func testSubcellIsSixteenthOfBaseCell() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 800)
        let baseSel = GridSelection(rowStart: 0, rowEnd: 0, colStart: 0, colEnd: 0)
        let base = ScreenGeometry.cocoaFrame(for: baseSel, rows: 8, columns: 8, visibleFrame: visible)!
        let sub = ScreenGeometry.cocoaFrame(for: baseSel, rows: 16, columns: 16, visibleFrame: visible)!
        XCTAssertEqual(sub.width, base.width / 2, accuracy: 0.01)
        XCTAssertEqual(sub.height, base.height / 2, accuracy: 0.01)
    }

    func testClampAtEdges() {
        let sel = GridSelection.fromDrag(startRow: -3, startCol: 20, endRow: 99, endCol: -5, rows: 8, columns: 8)!
        XCTAssertEqual(sel.rowStart, 0)
        XCTAssertEqual(sel.rowEnd, 7)
        XCTAssertEqual(sel.colStart, 0)
        XCTAssertEqual(sel.colEnd, 7)
    }

    func testCocoaFramePrimaryScreen() {
        let visible = CGRect(x: 0, y: 64, width: 1920, height: 1016)
        let model = ScreenGeometryModel(visibleFrame: visible, primaryTopY: 1080)
        let sel = GridSelection(rowStart: 0, rowEnd: 0, colStart: 0, colEnd: 0)
        let frame = model.cocoaFrame(for: sel, rows: 8, columns: 8)!
        XCTAssertEqual(frame.width, 240, accuracy: 0.01)
        XCTAssertEqual(frame.height, 127, accuracy: 0.01)
        XCTAssertEqual(frame.minX, 0, accuracy: 0.01)
        XCTAssertEqual(frame.maxY, visible.maxY, accuracy: 0.01)
    }

    func testCocoaToAXConversionUsesPrimaryTop() {
        let primaryTopY: CGFloat = 1080
        let cocoa = CGRect(x: 100, y: 200, width: 400, height: 300)
        let ax = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTopY)
        XCTAssertEqual(ax.origin.x, 100)
        XCTAssertEqual(ax.origin.y, primaryTopY - cocoa.maxY)
        let back = ScreenGeometry.axRectToCocoa(ax, primaryTopY: primaryTopY)
        XCTAssertEqual(back.minX, cocoa.minX, accuracy: 0.001)
        XCTAssertEqual(back.minY, cocoa.minY, accuracy: 0.001)
    }

    func testPrimaryTopYFromFramesArray() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 1080, width: 1920, height: 1080),
        ]
        XCTAssertEqual(ScreenGeometry.primaryTopY(screenFrames: frames), 1080)
    }

    func testNegativeMonitorOffsetLeft() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let primaryTopY: CGFloat = 1080
        let sel = GridSelection(rowStart: 0, rowEnd: 7, colStart: 0, colEnd: 7)
        let cocoa = ScreenGeometry.cocoaFrame(for: sel, rows: 8, columns: 8, visibleFrame: visible)!
        let ax = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTopY)
        XCTAssertEqual(ax.origin.x, -1920, accuracy: 0.01)
    }

    func testMonitorAbovePrimaryAXNegativeY() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let above = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let primaryTopY = ScreenGeometry.primaryTopY(screenFrames: [primary, above])
        XCTAssertEqual(primaryTopY, 1080)

        let visible = above
        let sel = GridSelection(rowStart: 0, rowEnd: 7, colStart: 0, colEnd: 7)
        let cocoa = ScreenGeometry.cocoaFrame(for: sel, rows: 8, columns: 8, visibleFrame: visible)!
        let ax = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTopY)
        XCTAssertEqual(ax.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(ax.origin.y, -1080, accuracy: 0.01)
        XCTAssertEqual(ax.width, 1920, accuracy: 0.01)
        XCTAssertEqual(ax.height, 1080, accuracy: 0.01)
    }

    func testMonitorBelowPrimaryAXPositiveY() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let primaryTopY = ScreenGeometry.primaryTopY(screenFrames: [primary, below])
        let visible = below
        let sel = GridSelection(rowStart: 0, rowEnd: 7, colStart: 0, colEnd: 7)
        let cocoa = ScreenGeometry.cocoaFrame(for: sel, rows: 8, columns: 8, visibleFrame: visible)!
        let ax = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTopY)
        XCTAssertEqual(ax.origin.y, 1080, accuracy: 0.01)
    }
}
