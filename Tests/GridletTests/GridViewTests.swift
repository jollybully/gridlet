import AppKit
import XCTest
@testable import Gridlet

@MainActor
private final class GridViewDelegateSpy: GridViewDelegate {
    var selectionChanges: [(GridSelection?, Int, Int)] = []
    var commits: [(GridSelection, Int, Int)] = []
    var cancelCount = 0

    func gridViewSelectionChanged(_ selection: GridSelection?, rows: Int, columns: Int) {
        selectionChanges.append((selection, rows, columns))
    }

    func gridViewCommitted(_ selection: GridSelection, rows: Int, columns: Int) {
        commits.append((selection, rows, columns))
    }

    func gridViewCancelled() {
        cancelCount += 1
    }
}

@MainActor
final class GridViewTests: XCTestCase {
    private func makeGridView(size: CGFloat = 800) -> (GridView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let grid = GridView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        window.contentView = grid
        return (grid, window)
    }

    private func viewPoint(_ grid: GridView, x: CGFloat, y: CGFloat) -> NSPoint {
        grid.convert(NSPoint(x: x, y: y), to: nil)
    }

    private func mouseEvent(type: NSEvent.EventType, location: NSPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }

    func testGapBetweenTilesStillMapsToCell() {
        let (grid, window) = makeGridView()
        let spy = GridViewDelegateSpy()
        grid.delegate = spy
        grid.rows = 8
        grid.columns = 8
        grid.prepareForPanelPresentation()

        let slot = 800.0 / 8.0
        let gapPoint = viewPoint(grid, x: slot * 1 + 1, y: slot * 2 + slot * 0.95)
        grid.mouseDown(with: mouseEvent(type: .leftMouseDown, location: gapPoint, window: window))
        grid.mouseUp(with: mouseEvent(type: .leftMouseUp, location: gapPoint, window: window))

        XCTAssertEqual(spy.commits.count, 1)
        XCTAssertEqual(spy.commits[0].0.colStart, 1)
        XCTAssertEqual(spy.commits[0].0.rowStart, 2)
    }

    func testMouseUpWithoutDragUsesEndpointFullGrid() {
        let (grid, window) = makeGridView()
        let spy = GridViewDelegateSpy()
        grid.delegate = spy
        grid.prepareForPanelPresentation()

        let cell = 800.0 / 8.0
        let start = viewPoint(grid, x: cell * 0 + 2, y: cell * 0 + 2)
        let end = viewPoint(grid, x: cell * 7 + 2, y: cell * 7 + 2)
        grid.mouseDown(with: mouseEvent(type: .leftMouseDown, location: start, window: window))
        grid.mouseUp(with: mouseEvent(type: .leftMouseUp, location: end, window: window))

        XCTAssertEqual(spy.commits.count, 1)
        let sel = spy.commits[0].0
        XCTAssertEqual(sel.rowStart, 0)
        XCTAssertEqual(sel.rowEnd, 7)
        XCTAssertEqual(sel.colStart, 0)
        XCTAssertEqual(sel.colEnd, 7)
    }

    func testReverseDragMouseUpWithoutIntermediateDragged() {
        let (grid, window) = makeGridView()
        let spy = GridViewDelegateSpy()
        grid.delegate = spy
        grid.prepareForPanelPresentation()

        let cell = 800.0 / 8.0
        let start = viewPoint(grid, x: cell * 6 + 2, y: cell * 5 + 2)
        let end = viewPoint(grid, x: cell * 1 + 2, y: cell * 2 + 2)
        grid.mouseDown(with: mouseEvent(type: .leftMouseDown, location: start, window: window))
        grid.mouseUp(with: mouseEvent(type: .leftMouseUp, location: end, window: window))

        XCTAssertEqual(spy.commits.count, 1)
        let sel = spy.commits[0].0
        XCTAssertEqual(sel.rowStart, 2)
        XCTAssertEqual(sel.rowEnd, 5)
        XCTAssertEqual(sel.colStart, 1)
        XCTAssertEqual(sel.colEnd, 6)
    }

    func testEscapeDuringDragThenMouseUpCommitsNothing() {
        let (grid, window) = makeGridView()
        let spy = GridViewDelegateSpy()
        grid.delegate = spy
        grid.prepareForPanelPresentation()

        let cell = 800.0 / 8.0
        let start = viewPoint(grid, x: cell * 0 + 2, y: cell * 0 + 2)
        let end = viewPoint(grid, x: cell * 7 + 2, y: cell * 7 + 2)
        grid.mouseDown(with: mouseEvent(type: .leftMouseDown, location: start, window: window))
        let esc = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 53
        )!
        grid.keyDown(with: esc)
        grid.mouseUp(with: mouseEvent(type: .leftMouseUp, location: end, window: window))

        XCTAssertEqual(spy.commits.count, 0)
        XCTAssertEqual(spy.cancelCount, 1)
    }

    private func rgbMaxDelta(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let ca = a.usingColorSpace(.deviceRGB), let cb = b.usingColorSpace(.deviceRGB) else { return 0 }
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return max(abs(ar - br), abs(ag - bg), abs(ab - bb)) * 255
    }

    func testIdleTileContrastInLightAndDarkAppearances() {
        let size = NSSize(width: 286, height: 248)
        let fixtures: [(String, NSAppearance, NSColor)] = [
            ("light", NSAppearance(named: .aqua)!, NSColor(calibratedWhite: 234 / 255, alpha: 1)),
            ("dark", NSAppearance(named: .darkAqua)!, NSColor(calibratedWhite: 44 / 255, alpha: 1)),
        ]
        for (name, appearance, panelBacking) in fixtures {
            let grid = GridView(frame: NSRect(origin: .zero, size: size))
            grid.rows = 8
            grid.columns = 8
            grid.appearance = appearance

            let pixelsWide = Int(size.width)
            let pixelsHigh = Int(size.height)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                XCTFail("bitmap (\(name))")
                continue
            }

            appearance.performAsCurrentDrawingAppearance {
                NSGraphicsContext.saveGraphicsState()
                guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
                ctx.imageInterpolation = .high
                NSGraphicsContext.current = ctx
                let cg = ctx.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                panelBacking.setFill()
                NSRect(origin: .zero, size: size).fill()
                grid.draw(grid.bounds)
                NSGraphicsContext.restoreGraphicsState()
            }

            let gap = GridTileMetrics.gap
            let tw = (size.width - gap * 7) / 8
            let th = (size.height - gap * 7) / 8
            let tileX = Int(tw / 2)
            let gapX = Int(tw + gap / 2)
            let sampleY = Int(th / 2)

            guard let tileColor = rep.colorAt(x: tileX, y: sampleY),
                  let gapColor = rep.colorAt(x: gapX, y: sampleY) else {
                XCTFail("sample (\(name))")
                continue
            }
            let delta = rgbMaxDelta(tileColor, gapColor)
            XCTAssertGreaterThanOrEqual(
                delta, 12,
                "\(name) tile vs gap max RGB delta \(delta) (tile \(tileColor), gap \(gapColor))"
            )
        }
    }

    func testAccessibilityMetadata() {
        let (grid, _) = makeGridView()
        grid.rows = 10
        grid.columns = 6
        grid.prepareForPanelPresentation()
        XCTAssertEqual(grid.accessibilityIdentifier(), "gridlet-grid")
        XCTAssertEqual(grid.accessibilityRole(), .group)
        XCTAssertTrue(grid.accessibilityLabel()?.contains("10") == true)
        XCTAssertTrue(grid.accessibilityLabel()?.contains("6") == true)
    }

    func testTileSelectionBoundsClamped() {
        let (grid, _) = makeGridView(size: 400)
        grid.rows = 4
        grid.columns = 4
        let sel = GridSelection.fromDrag(startRow: -1, startCol: 0, endRow: 9, endCol: 9, rows: 4, columns: 4)
        XCTAssertNotNil(sel)
        XCTAssertEqual(sel?.rowStart, 0)
        XCTAssertEqual(sel?.rowEnd, 3)
        XCTAssertEqual(sel?.colEnd, 3)
    }
}

@MainActor
final class PanelCoordinatorSmokeEscapeTests: XCTestCase {
    func testEscapeDismissesPanelsInSmokeModeWithoutMovingWindows() {
        let coord = PanelCoordinator.shared
        coord.uiSmokeMode = true
        defer {
            if coord.panelsAreVisible {
                coord.dismissAll(reason: .monitorChange)
            }
            coord.uiSmokeMode = false
        }

        coord.presentPanels()
        XCTAssertTrue(coord.panelsAreVisible)
        guard let panel = coord.firstPanelWindow() else {
            XCTFail("expected panel window")
            return
        }
        let frameBefore = panel.frame
        XCTAssertNil(coord.capturedTarget)

        coord.cancelActiveSelection()

        XCTAssertFalse(coord.panelsAreVisible)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame, frameBefore)
    }
}

@MainActor
final class LiveGridDimensionsTests: XCTestCase {
    func testSyncRowsColumnsToMultipleGridViews() {
        let a = GridView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let b = GridView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        a.rows = 8
        b.rows = 8
        PanelCoordinator.syncGridDimensions(rows: 5, columns: 7, gridViews: [a, b])
        XCTAssertEqual(a.rows, 5)
        XCTAssertEqual(a.columns, 7)
        XCTAssertEqual(b.rows, 5)
        XCTAssertEqual(b.columns, 7)
    }
}
