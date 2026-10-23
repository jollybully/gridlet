import AppKit
import CoreGraphics
import Foundation

/// Inclusive grid cell selection (0-based indices).
struct GridSelection: Codable, Equatable, Sendable {
    var rowStart: Int
    var rowEnd: Int
    var colStart: Int
    var colEnd: Int

    var isValid: Bool {
        rowStart >= 0 && colStart >= 0 && rowEnd >= rowStart && colEnd >= colStart
    }

    func normalized(rows: Int, columns: Int) -> GridSelection? {
        guard rows >= 1, columns >= 1 else { return nil }
        let r0 = max(0, min(rowStart, rows - 1))
        let r1 = max(0, min(rowEnd, rows - 1))
        let c0 = max(0, min(colStart, columns - 1))
        let c1 = max(0, min(colEnd, columns - 1))
        return GridSelection(rowStart: min(r0, r1), rowEnd: max(r0, r1), colStart: min(c0, c1), colEnd: max(c0, c1))
    }

    static func fromDrag(
        startRow: Int, startCol: Int,
        endRow: Int, endCol: Int,
        rows: Int, columns: Int
    ) -> GridSelection? {
        guard rows >= 1, columns >= 1 else { return nil }
        let sel = GridSelection(
            rowStart: startRow, rowEnd: endRow,
            colStart: startCol, colEnd: endCol
        )
        return sel.normalized(rows: rows, columns: columns)
    }
}

enum ScreenGeometry {
    /// AX Y=0 is the top edge of the **primary** display (first entry in `NSScreen.screens`), not the union of all monitors.
    static func primaryTopY(screens: [NSScreen]) -> CGFloat {
        primaryTopY(screenFrames: screens.map(\.frame))
    }

    static func primaryTopY(screenFrames: [CGRect]) -> CGFloat {
        screenFrames.first?.maxY ?? 0
    }

    /// Convert a Cocoa screen-space rect (bottom-left origin, global) to AX top-left origin.
    static func cocoaRectToAX(_ rect: CGRect, primaryTopY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryTopY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Convert AX rect to Cocoa screen-space (bottom-left origin).
    static func axRectToCocoa(_ rect: CGRect, primaryTopY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryTopY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Frame for an inclusive grid selection within `visibleFrame` (Cocoa coords).
    /// Row 0 is the top row of the grid (nearest visible maxY).
    static func cocoaFrame(
        for selection: GridSelection,
        rows: Int,
        columns: Int,
        visibleFrame: CGRect
    ) -> CGRect? {
        guard let norm = selection.normalized(rows: rows, columns: columns) else { return nil }
        guard rows >= 1, columns >= 1 else { return nil }

        let cellW = visibleFrame.width / CGFloat(columns)
        let cellH = visibleFrame.height / CGFloat(rows)

        let x = visibleFrame.minX + CGFloat(norm.colStart) * cellW
        let width = CGFloat(norm.colEnd - norm.colStart + 1) * cellW

        let y = visibleFrame.minY + CGFloat(rows - norm.rowEnd - 1) * cellH
        let height = CGFloat(norm.rowEnd - norm.rowStart + 1) * cellH

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func cellAt(point: CGPoint, rows: Int, columns: Int, visibleFrame: CGRect) -> (row: Int, col: Int)? {
        guard rows >= 1, columns >= 1 else { return nil }
        guard visibleFrame.contains(point) else { return nil }

        let cellW = visibleFrame.width / CGFloat(columns)
        let cellH = visibleFrame.height / CGFloat(rows)

        let col = Int((point.x - visibleFrame.minX) / cellW)
        let rowFromBottom = Int((point.y - visibleFrame.minY) / cellH)
        let row = rows - 1 - rowFromBottom

        let c = min(max(col, 0), columns - 1)
        let r = min(max(row, 0), rows - 1)
        return (r, c)
    }
}

/// Pure geometry helpers for tests without NSScreen.
struct ScreenGeometryModel: Sendable {
    var visibleFrame: CGRect
    /// Primary display top in Cocoa global space (`screenFrames.first.maxY`).
    var primaryTopY: CGFloat

    func cocoaFrame(for selection: GridSelection, rows: Int, columns: Int) -> CGRect? {
        ScreenGeometry.cocoaFrame(for: selection, rows: rows, columns: columns, visibleFrame: visibleFrame)
    }

    func axFrame(for selection: GridSelection, rows: Int, columns: Int) -> CGRect? {
        guard let cocoa = cocoaFrame(for: selection, rows: rows, columns: columns) else { return nil }
        return ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTopY)
    }
}
