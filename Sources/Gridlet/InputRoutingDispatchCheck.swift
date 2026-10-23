import AppKit

/// In-process sendEvent checks for `--ui-smoke-dispatch` (no AX, no user mouse).
@MainActor
enum InputRoutingDispatchCheck {
    struct Result: Equatable {
        var panelOriginStable: Bool
        var commitCount: Int
    }

    static func run(on panel: NSWindow, grid: GridView) -> Result {
        let originBefore = panel.frame.origin
        var commitCount = 0
        let prior = grid.delegate
        final class Counter: NSObject, GridViewDelegate {
            var count = 0
            func gridViewSelectionChanged(_ selection: GridSelection?, rows: Int, columns: Int) {}
            func gridViewCommitted(_ selection: GridSelection, rows: Int, columns: Int) { count += 1 }
            func gridViewCancelled() {}
        }
        let counter = Counter()
        grid.delegate = counter
        grid.prepareForPanelPresentation()

        let start = NSPoint(x: grid.bounds.midX - 40, y: grid.bounds.midY - 40)
        let end = NSPoint(x: grid.bounds.midX + 40, y: grid.bounds.midY + 40)
        for (pt, type) in zip([start, end, end], [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            let loc = grid.convert(pt, to: nil)
            let event = NSEvent.mouseEvent(
                with: type,
                location: loc,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
            NSApp.sendEvent(event)
        }
        commitCount = counter.count
        grid.delegate = prior
        let stable = panel.frame.origin == originBefore
        return Result(panelOriginStable: stable, commitCount: commitCount)
    }
}
