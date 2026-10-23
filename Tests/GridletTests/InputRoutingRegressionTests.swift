import AppKit
import XCTest
@testable import Gridlet

@MainActor
private final class InputRoutingDelegateSpy: GridViewDelegate {
    var commits: [(GridSelection, Int, Int)] = []

    func gridViewSelectionChanged(_ selection: GridSelection?, rows: Int, columns: Int) {}
    func gridViewCommitted(_ selection: GridSelection, rows: Int, columns: Int) {
        commits.append((selection, rows, columns))
    }
    func gridViewCancelled() {}
}

/// Shared sendEvent drag used by XCTest and optional `--ui-smoke-dispatch`.
@MainActor
enum InputRoutingDispatchHarness {
    static func gridCenterInWindow(_ grid: GridView) -> NSPoint {
        NSPoint(x: grid.bounds.midX, y: grid.bounds.midY)
    }

    static func sendMouseSequence(
        app: NSApplication,
        window: NSWindow,
        view: NSView,
        points: [NSPoint],
        types: [NSEvent.EventType]
    ) {
        precondition(points.count == types.count)
        for (pt, type) in zip(points, types) {
            let loc = view.convert(pt, to: nil)
            let event = NSEvent.mouseEvent(
                with: type,
                location: loc,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
            app.sendEvent(event)
        }
    }

    /// Drag within `grid`; returns whether `panel.frame.origin` stayed fixed.
    static func sendKeyDown(
        app: NSApplication,
        window: NSWindow,
        keyCode: UInt16,
        characters: String = ""
    ) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
        app.sendEvent(event)
    }

    static func panelOriginStableAfterGridDrag(
        panel: NSWindow,
        grid: GridView,
        app: NSApplication = .shared
    ) -> (originStable: Bool, commitCount: Int, originBefore: NSPoint, originAfter: NSPoint) {
        let spy = InputRoutingDelegateSpy()
        grid.delegate = spy
        grid.prepareForPanelPresentation()

        let originBefore = panel.frame.origin
        let start = NSPoint(x: grid.bounds.midX - 40, y: grid.bounds.midY - 40)
        let end = NSPoint(x: grid.bounds.midX + 40, y: grid.bounds.midY + 40)
        sendMouseSequence(
            app: app,
            window: panel,
            view: grid,
            points: [start, end, end],
            types: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        )
        let originAfter = panel.frame.origin
        let stable = originBefore == originAfter
        return (stable, spy.commits.count, originBefore, originAfter)
    }
}

@MainActor
final class InputRoutingRegressionTests: XCTestCase {
    func testGridPanelWindowDisablesBackgroundAndWindowDrag() {
        let win = GridPanelWindow()
        XCTAssertTrue(
            win.canBecomeKey,
            "borderless NSPanel defaults canBecomeKey=false; Escape/focus routing requires key window"
        )
        XCTAssertFalse(win.canBecomeMain, "panel must not become main — keeps target app frontmost semantics")
        XCTAssertFalse(
            win.isMovableByWindowBackground,
            "background drag steals grid drags (INPUT ROUTING defect)"
        )
        XCTAssertFalse(win.isMovable, "panel is a centered tool surface, not a movable document window")
    }

    func testGridViewMouseDownDoesNotMoveWindowAndAcceptsFirstMouse() {
        let grid = GridView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertFalse(
            grid.mouseDownCanMoveWindow,
            "NSView default is true; grid drags must not move the panel"
        )
        XCTAssertTrue(
            grid.acceptsFirstMouse(for: nil),
            "nonactivating panel needs first-click delivery without activation swallowing"
        )
    }

    func testSendEventGridDragDoesNotMovePanelOrigin() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let controller = GridPanelController(screen: screen)
        guard let panel = controller.window else {
            XCTFail("missing panel window")
            return
        }
        panel.setFrame(NSRect(x: 200, y: 200, width: PanelMetrics.width, height: PanelMetrics.height), display: true)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(controller.gridView)

        let result = InputRoutingDispatchHarness.panelOriginStableAfterGridDrag(
            panel: panel,
            grid: controller.gridView
        )
        XCTAssertTrue(result.originStable, "origin moved from \(result.originBefore) to \(result.originAfter)")
        XCTAssertGreaterThanOrEqual(result.commitCount, 1, "drag should commit a selection via real dispatch")
    }

    func testSendEventFirstClickCommitsWhenPanelNotKey() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let controller = GridPanelController(screen: screen)
        guard let panel = controller.window else {
            XCTFail("missing panel window")
            return
        }
        let grid = controller.gridView
        let spy = InputRoutingDelegateSpy()
        grid.delegate = spy
        grid.prepareForPanelPresentation()

        panel.setFrame(NSRect(x: 220, y: 220, width: PanelMetrics.width, height: PanelMetrics.height), display: true)
        panel.orderFrontRegardless()

        let blocker = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        blocker.makeKeyAndOrderFront(nil)
        XCTAssertFalse(panel.isKeyWindow, "panel should stay non-key for inactive first-click scenario")

        let cell = grid.bounds.width / 8
        let pt = NSPoint(x: cell * 2 + 2, y: cell * 3 + 2)
        InputRoutingDispatchHarness.sendMouseSequence(
            app: .shared,
            window: panel,
            view: grid,
            points: [pt, pt],
            types: [.leftMouseDown, .leftMouseUp]
        )

        XCTAssertEqual(spy.commits.count, 1, "first click on inactive nonactivating panel must commit selection")
        blocker.orderOut(nil)
        panel.orderOut(nil)
    }

    func testSendEventEscapeOnKeyPanelDismissesViaCoordinator() {
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
            XCTFail("missing panel window")
            return
        }
        guard let grid = coord.firstPanelController()?.gridView else {
            XCTFail("missing grid view")
            return
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(grid)
        XCTAssertTrue(panel.isKeyWindow, "panel must accept key events after canBecomeKey override")

        InputRoutingDispatchHarness.sendKeyDown(app: .shared, window: panel, keyCode: 53)

        XCTAssertFalse(coord.panelsAreVisible, "Escape via sendEvent should dismiss through coordinator")
        XCTAssertFalse(panel.isVisible)
    }
}
