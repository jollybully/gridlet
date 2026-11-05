import XCTest
@testable import Gridlet

final class WindowOccupancyTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let primaryTop = CGFloat(600)

    private func cells(rows: Int = 8, columns: Int = 8, windows: [WindowOccupancy.Window]) -> GridOccupancy {
        WindowOccupancy.cells(
            rows: rows,
            columns: columns,
            visibleFrame: visibleFrame,
            primaryTopY: primaryTop,
            windows: windows
        )
    }

    func testNoWindowsMeansNoCoverage() {
        let occupancy = cells(windows: [])
        XCTAssertTrue(occupancy.isEmpty)
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 0)
    }

    func testFullScreenWindowCoversEveryCell() {
        let occupancy = cells(windows: [.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600), isTarget: false)])
        for row in 0..<8 {
            for column in 0..<8 {
                XCTAssertEqual(occupancy.coverage(row: row, column: column), 1, accuracy: 0.001)
            }
        }
    }

    func testLeftHalfWindowCoversTheLeftColumnsOnly() {
        let occupancy = cells(windows: [.init(frame: CGRect(x: 0, y: 0, width: 400, height: 600), isTarget: false)])
        for row in 0..<8 {
            for column in 0..<8 {
                let expected = column < 4 ? 1.0 : 0.0
                XCTAssertEqual(occupancy.coverage(row: row, column: column), expected, accuracy: 0.001,
                               "row \(row) column \(column)")
            }
        }
    }

    /// A window straddling a cell boundary contributes the fraction of each cell it covers,
    /// which is what keeps a half-cell offset from reading as a whole cell.
    func testStraddlingWindowIsFractional() {
        let occupancy = cells(windows: [.init(frame: CGRect(x: 50, y: 0, width: 100, height: 600), isTarget: false)])
        for row in 0..<8 {
            XCTAssertEqual(occupancy.coverage(row: row, column: 0), 0.5, accuracy: 0.001)
            XCTAssertEqual(occupancy.coverage(row: row, column: 1), 0.5, accuracy: 0.001)
            XCTAssertEqual(occupancy.coverage(row: row, column: 2), 0, accuracy: 0.001)
        }
    }

    func testTopRowIsTheTopOfTheDisplay() {
        // A short window at the top of the screen must light the first row, not the last.
        let occupancy = cells(windows: [.init(frame: CGRect(x: 0, y: 0, width: 800, height: 75), isTarget: false)])
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 1, accuracy: 0.001)
        XCTAssertEqual(occupancy.coverage(row: 7, column: 0), 0, accuracy: 0.001)
    }

    func testMenuBarOffsetIsAccountedFor() {
        // visibleFrame starts below a 25pt menu bar: row 0 must still be the top usable band.
        let inset = CGRect(x: 0, y: 0, width: 800, height: 575)
        let occupancy = WindowOccupancy.cells(
            rows: 5,
            columns: 4,
            visibleFrame: inset,
            primaryTopY: primaryTop,
            windows: [.init(frame: CGRect(x: 0, y: 25, width: 800, height: 115), isTarget: false)]
        )
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 1, accuracy: 0.001)
        XCTAssertEqual(occupancy.coverage(row: 1, column: 0), 0, accuracy: 0.001)
    }

    func testWindowsOffTheDisplayAreIgnored() {
        let occupancy = cells(windows: [.init(frame: CGRect(x: 900, y: 0, width: 400, height: 600), isTarget: false)])
        XCTAssertTrue(occupancy.isEmpty)
    }

    func testPartiallyOffScreenWindowIsClipped() {
        // 100pt of a 200pt-wide window sits off the left edge: only the visible half counts.
        let occupancy = cells(windows: [.init(frame: CGRect(x: -100, y: 0, width: 200, height: 600), isTarget: false)])
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 1, accuracy: 0.001)
        XCTAssertEqual(occupancy.coverage(row: 0, column: 1), 0, accuracy: 0.001)
    }

    func testOverlappingWindowsCapAtOne() {
        let occupancy = cells(windows: [
            .init(frame: CGRect(x: 0, y: 0, width: 400, height: 600), isTarget: false),
            .init(frame: CGRect(x: 0, y: 0, width: 400, height: 600), isTarget: false),
        ])
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 1, accuracy: 0.001)
    }

    func testTargetCoverageIsTrackedSeparately() {
        let occupancy = cells(windows: [
            .init(frame: CGRect(x: 0, y: 0, width: 400, height: 600), isTarget: false),
            .init(frame: CGRect(x: 100, y: 0, width: 200, height: 600), isTarget: true),
        ])
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 1, accuracy: 0.001)
        XCTAssertEqual(occupancy.coverage(row: 0, column: 1), 1, accuracy: 0.001)
        XCTAssertEqual(occupancy.targetCoverage(row: 0, column: 1), 1, accuracy: 0.001)
        XCTAssertEqual(occupancy.targetCoverage(row: 0, column: 0), 0, accuracy: 0.001)
    }

    func testHintAlphaStaysSubtleAndStrongerForTheTarget() {
        XCTAssertEqual(WindowOccupancy.hintAlpha(coverage: 0, isTarget: false), 0)
        XCTAssertEqual(WindowOccupancy.hintAlpha(coverage: 0.01, isTarget: true), 0)
        let plain = WindowOccupancy.hintAlpha(coverage: 1, isTarget: false)
        let target = WindowOccupancy.hintAlpha(coverage: 1, isTarget: true)
        XCTAssertLessThan(plain, 0.14, "hint must stay quieter than an idle tile (0.14)")
        XCTAssertGreaterThan(target, plain)
        XCTAssertLessThan(target, 0.22, "target hint must stay quieter than a hovered tile (0.22)")
        XCTAssertGreaterThan(
            WindowOccupancy.hintAlpha(coverage: 0.8, isTarget: false),
            WindowOccupancy.hintAlpha(coverage: 0.3, isTarget: false)
        )
    }

    func testDegenerateGridReturnsNoCoverage() {
        let occupancy = WindowOccupancy.cells(
            rows: 0,
            columns: 0,
            visibleFrame: visibleFrame,
            primaryTopY: primaryTop,
            windows: [.init(frame: visibleFrame, isTarget: false)]
        )
        XCTAssertTrue(occupancy.isEmpty)
        XCTAssertEqual(occupancy.coverage(row: 0, column: 0), 0)
    }
}
