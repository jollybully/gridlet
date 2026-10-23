import AppKit

@MainActor
protocol GridViewDelegate: AnyObject {
    func gridViewSelectionChanged(_ selection: GridSelection?, rows: Int, columns: Int)
    func gridViewCommitted(_ selection: GridSelection, rows: Int, columns: Int)
    func gridViewCancelled()
}

enum GridTileMetrics {
    static let gap: CGFloat = 3.5
    static let tileRadius: CGFloat = 5
}

final class GridView: NSView {
    weak var delegate: GridViewDelegate?

    var rows: Int = 8 {
        didSet {
            needsDisplay = true
            resetSelection()
            refreshAccessibilityMetadata()
        }
    }
    var columns: Int = 8 {
        didSet {
            needsDisplay = true
            resetSelection()
            refreshAccessibilityMetadata()
        }
    }

    private var dragStart: (row: Int, col: Int)?
    private var dragCurrent: (row: Int, col: Int)?
    private var hoverCell: (row: Int, col: Int)?
    private var selectionCancelled = false

    func prepareForPanelPresentation() {
        resetSelection()
        refreshAccessibilityMetadata()
    }

    func refreshAccessibilityMetadata() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("gridlet-grid")
        setAccessibilityLabel("Grid \(rows) by \(columns) cells")
    }

    override var isFlipped: Bool { true }

    private func tileSize() -> (width: CGFloat, height: CGFloat) {
        let gap = GridTileMetrics.gap
        let tw = (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let th = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return (tw, th)
    }

    private func tileRect(row: Int, col: Int) -> NSRect {
        let (tw, th) = tileSize()
        let gap = GridTileMetrics.gap
        return NSRect(
            x: CGFloat(col) * (tw + gap),
            y: CGFloat(row) * (th + gap),
            width: tw,
            height: th
        )
    }

    private struct TilePalette {
        let idleFill: NSColor
        let hoverFill: NSColor
        let tileEdge: NSColor
    }

    private func tilePalette() -> TilePalette {
        let appearance = effectiveAppearance
        var idle = NSColor.labelColor.withAlphaComponent(0.14)
        var hover = NSColor.labelColor.withAlphaComponent(0.22)
        var edge = NSColor.labelColor.withAlphaComponent(0.22)
        var accentHover = NSColor.controlAccentColor.withAlphaComponent(0.18)
        appearance.performAsCurrentDrawingAppearance {
            idle = NSColor.labelColor.withAlphaComponent(0.14)
            hover = NSColor.labelColor.withAlphaComponent(0.22)
            edge = NSColor.labelColor.withAlphaComponent(0.22)
            accentHover = NSColor.controlAccentColor.withAlphaComponent(0.18)
        }
        let blendedHover = hover.blended(withFraction: 0.35, of: accentHover) ?? hover
        return TilePalette(idleFill: idle, hoverFill: blendedHover, tileEdge: edge)
    }

    override func draw(_ dirtyRect: NSRect) {
        let (tw, th) = tileSize()
        let gap = GridTileMetrics.gap
        let palette = tilePalette()
        let accent = NSColor.controlAccentColor

        let sel = currentSelection()

        for row in 0..<rows {
            for col in 0..<columns {
                let rect = tileRect(row: row, col: col)
                let path = NSBezierPath(roundedRect: rect, xRadius: GridTileMetrics.tileRadius, yRadius: GridTileMetrics.tileRadius)

                if let sel, row >= sel.rowStart, row <= sel.rowEnd, col >= sel.colStart, col <= sel.colEnd {
                    accent.withAlphaComponent(0.28).setFill()
                    path.fill()
                } else if let hover = hoverCell, hover.row == row, hover.col == col {
                    palette.hoverFill.setFill()
                    path.fill()
                    palette.tileEdge.setStroke()
                    path.lineWidth = 0.75
                    path.stroke()
                } else {
                    palette.idleFill.setFill()
                    path.fill()
                    palette.tileEdge.setStroke()
                    path.lineWidth = 0.75
                    path.stroke()
                }
            }
        }

        if let sel {
            let outer = NSRect(
                x: CGFloat(sel.colStart) * (tw + gap),
                y: CGFloat(sel.rowStart) * (th + gap),
                width: CGFloat(sel.colEnd - sel.colStart + 1) * tw + CGFloat(sel.colEnd - sel.colStart) * gap,
                height: CGFloat(sel.rowEnd - sel.rowStart + 1) * th + CGFloat(sel.rowEnd - sel.rowStart) * gap
            )
            accent.setStroke()
            let outline = NSBezierPath(roundedRect: outer, xRadius: GridTileMetrics.tileRadius + 1, yRadius: GridTileMetrics.tileRadius + 1)
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    func resetSelection() {
        dragStart = nil
        dragCurrent = nil
        hoverCell = nil
        selectionCancelled = false
        needsDisplay = true
        delegate?.gridViewSelectionChanged(nil, rows: rows, columns: columns)
    }

    /// Slot-based mapping so gaps between tiles remain part of the drag surface.
    func cellAt(_ point: NSPoint) -> (row: Int, col: Int) {
        let slotW = bounds.width / CGFloat(columns)
        let slotH = bounds.height / CGFloat(rows)
        let col = min(max(Int(point.x / slotW), 0), columns - 1)
        let row = min(max(Int(point.y / slotH), 0), rows - 1)
        return (row, col)
    }

    private func currentSelection() -> GridSelection? {
        guard let start = dragStart, let end = dragCurrent else { return nil }
        return GridSelection.fromDrag(
            startRow: start.row, startCol: start.col,
            endRow: end.row, endCol: end.col,
            rows: rows, columns: columns
        )
    }

    private func notifyPreview() {
        delegate?.gridViewSelectionChanged(
            currentSelection() ?? hoverSelection(),
            rows: rows,
            columns: columns
        )
    }

    private func hoverSelection() -> GridSelection? {
        guard let h = hoverCell else { return nil }
        return GridSelection(rowStart: h.row, rowEnd: h.row, colStart: h.col, colEnd: h.col)
    }

    override func mouseMoved(with event: NSEvent) {
        let cell = cellAt(convert(event.locationInWindow, from: nil))
        hoverCell = cell
        needsDisplay = true
        notifyPreview()
    }

    override func mouseExited(with event: NSEvent) {
        hoverCell = nil
        needsDisplay = true
        delegate?.gridViewSelectionChanged(nil, rows: rows, columns: columns)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseDown(with event: NSEvent) {
        selectionCancelled = false
        let cell = cellAt(convert(event.locationInWindow, from: nil))
        dragStart = cell
        dragCurrent = cell
        needsDisplay = true
        notifyPreview()
    }

    override func mouseDragged(with event: NSEvent) {
        let cell = cellAt(convert(event.locationInWindow, from: nil))
        dragCurrent = cell
        needsDisplay = true
        notifyPreview()
    }

    override func mouseUp(with event: NSEvent) {
        if !selectionCancelled, let start = dragStart {
            let endCell = cellAt(convert(event.locationInWindow, from: nil))
            dragCurrent = endCell
            if let sel = GridSelection.fromDrag(
                startRow: start.row, startCol: start.col,
                endRow: endCell.row, endCol: endCell.col,
                rows: rows, columns: columns
            ) {
                delegate?.gridViewCommitted(sel, rows: rows, columns: columns)
            }
        }
        dragStart = nil
        dragCurrent = nil
        hoverCell = nil
        selectionCancelled = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            selectionCancelled = true
            dragStart = nil
            dragCurrent = nil
            hoverCell = nil
            needsDisplay = true
            delegate?.gridViewCancelled()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Snapshot helper — paints a selection without mouse events.
    func simulateSelectionForSnapshot(_ selection: GridSelection) {
        dragStart = (selection.rowStart, selection.colStart)
        dragCurrent = (selection.rowEnd, selection.colEnd)
        needsDisplay = true
    }
}
