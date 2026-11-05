import AppKit
import CoreGraphics

/// How much of each grid cell is already covered by windows that are on screen.
/// Coverage is a 0…1 fraction per cell in row-major order, row 0 being the top row.
struct GridOccupancy: Equatable, Sendable {
    /// The cells one window occupies, so neighbouring apps can be told apart by an outline
    /// instead of merging into one tinted area.
    struct WindowBlock: Equatable, Sendable {
        var firstRow: Int
        var lastRow: Int
        var firstColumn: Int
        var lastColumn: Int
        var isTarget: Bool
    }

    var rows: Int
    var columns: Int
    var coverage: [Double]
    /// Coverage belonging to the window about to be moved, drawn in a stronger tone.
    var target: [Double]
    var blocks: [WindowBlock]

    static let none = GridOccupancy(rows: 0, columns: 0, coverage: [], target: [], blocks: [])

    var isEmpty: Bool {
        coverage.allSatisfy { $0 < 0.02 } && target.allSatisfy { $0 < 0.02 }
    }

    func coverage(row: Int, column: Int) -> Double {
        value(in: coverage, row: row, column: column)
    }

    func targetCoverage(row: Int, column: Int) -> Double {
        value(in: target, row: row, column: column)
    }

    private func value(in values: [Double], row: Int, column: Int) -> Double {
        guard rows > 0, columns > 0,
              row >= 0, row < rows,
              column >= 0, column < columns else { return 0 }
        let index = row * columns + column
        return index < values.count ? values[index] : 0
    }
}

enum WindowOccupancy {
    /// A window frame in Accessibility coordinates: top-left origin, y down from the
    /// top of the primary display. The window server reports bounds in the same space.
    struct Window: Equatable {
        var frame: CGRect
        var isTarget: Bool
    }

    /// Alpha for a covered cell. The idle tile is already label colour at 0.14, so hints
    /// stay under that: enough to read as "something is here", not enough to compete with
    /// the selection highlight drawn on top.
    static func hintAlpha(coverage: Double, isTarget: Bool) -> Double {
        let clamped = max(0, min(1, coverage))
        guard clamped > 0.02 else { return 0 }
        return isTarget ? 0.06 + 0.10 * clamped : 0.04 + 0.06 * clamped
    }

    /// Map window frames onto grid cells for one display.
    ///
    /// - Parameters:
    ///   - visibleFrame: the display's usable area in Cocoa coordinates (bottom-left origin).
    ///   - primaryTopY: `ScreenGeometry.primaryTopY` for the current screens.
    static func cells(
        rows: Int,
        columns: Int,
        visibleFrame: CGRect,
        primaryTopY: CGFloat,
        windows: [Window]
    ) -> GridOccupancy {
        guard rows >= 1, columns >= 1, visibleFrame.width > 1, visibleFrame.height > 1 else {
            return .none
        }
        let axVisible = ScreenGeometry.cocoaRectToAX(visibleFrame, primaryTopY: primaryTopY)
        let cellWidth = axVisible.width / CGFloat(columns)
        let cellHeight = axVisible.height / CGFloat(rows)
        guard cellWidth > 0, cellHeight > 0 else { return .none }

        var coverage = [Double](repeating: 0, count: rows * columns)
        var target = [Double](repeating: 0, count: rows * columns)
        var blocks: [GridOccupancy.WindowBlock] = []

        for window in windows {
            let clipped = window.frame.intersection(axVisible)
            guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { continue }

            let firstColumn = max(0, Int(((clipped.minX - axVisible.minX) / cellWidth).rounded(.down)))
            let lastColumn = min(
                columns - 1,
                Int(((clipped.maxX - axVisible.minX - 0.001) / cellWidth).rounded(.down))
            )
            let firstRow = max(0, Int(((clipped.minY - axVisible.minY) / cellHeight).rounded(.down)))
            let lastRow = min(
                rows - 1,
                Int(((clipped.maxY - axVisible.minY - 0.001) / cellHeight).rounded(.down))
            )
            guard firstColumn <= lastColumn, firstRow <= lastRow else { continue }

            var widestCellFraction = 0.0
            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    let cell = CGRect(
                        x: axVisible.minX + CGFloat(column) * cellWidth,
                        y: axVisible.minY + CGFloat(row) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    let overlap = cell.intersection(clipped)
                    guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
                    let fraction = Double((overlap.width * overlap.height) / (cellWidth * cellHeight))
                    guard fraction > 0 else { continue }
                    let index = row * columns + column
                    // Two windows overlapping the same cell cap at one.
                    coverage[index] = min(1, coverage[index] + fraction)
                    widestCellFraction = max(widestCellFraction, fraction)
                    if window.isTarget {
                        target[index] = min(1, target[index] + fraction)
                    }
                }
            }

            // A window that only clips the edge of the grid is not worth an outline: an
            // outline is about telling whole windows apart, so require one cell it really
            // occupies rather than a sliver of many.
            if widestCellFraction >= 0.10 {
                blocks.append(GridOccupancy.WindowBlock(
                    firstRow: firstRow,
                    lastRow: lastRow,
                    firstColumn: firstColumn,
                    lastColumn: lastColumn,
                    isTarget: window.isTarget
                ))
            }
        }

        return GridOccupancy(
            rows: rows,
            columns: columns,
            coverage: coverage,
            target: target,
            blocks: blocks
        )
    }

    /// Ordinary windows currently on screen, in window-server (AX-style) coordinates.
    /// Bounds need no Screen Recording grant — only window names do — so this stays free
    /// of extra permissions.
    static func onScreenWindows(
        excludingPIDs: Set<pid_t>,
        minimumSize: CGFloat = 40
    ) -> [(id: Int, pid: pid_t, frame: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var found: [(id: Int, pid: pid_t, frame: CGRect)] = []
        for info in raw {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let idNumber = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
            let pid = pid_t(pidNumber.int32Value)
            guard !excludingPIDs.contains(pid) else { continue }
            guard width >= Double(minimumSize), height >= Double(minimumSize) else { continue }
            found.append((id: idNumber, pid: pid, frame: CGRect(x: x, y: y, width: width, height: height)))
        }
        return found
    }
}
