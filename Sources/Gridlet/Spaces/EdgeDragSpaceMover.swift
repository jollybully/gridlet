import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Moves a window belonging to *another* application into a different Space.
///
/// SkyLight's `SLSMoveWindowsToManagedSpace` (and the remove/add primitives) only act on
/// windows owned by the calling process — verified: Gridlet's own window moves, a TextEdit
/// window stays put, and AX exposes no space attribute. The remaining public path is the
/// gesture a human performs: grab the title bar, drag to the screen edge, hold while macOS
/// switches Spaces, release. That needs only Accessibility (event posting), no injection
/// into Dock and no SIP changes.
@MainActor
enum EdgeDragSpaceMover {
    static let logPath = "/tmp/gridlet-space-send.log"

    static func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func post(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }


    private static func postCtrlArrow(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.flags = .maskControl
            down.post(tap: .cghidEventTap)
        }
        usleep(30_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.flags = .maskControl
            up.post(tap: .cghidEventTap)
        }
    }

    private static func currentSpaceID(for screen: NSScreen) -> UInt64? {
        SpaceBridge.spaces(for: screen).first(where: \.isCurrent)?.id
    }

    /// Returns true when the window's Space membership actually changed.
    static func send(target: WindowTarget, to spaceID: UInt64, on screen: NSScreen, hopsTimeout: TimeInterval = 3.0) -> Bool {
        guard SpaceBridge.isAvailable else {
            log("spaces unavailable")
            return false
        }
        let spaces = SpaceBridge.spaces(for: screen)
        guard let destination = spaces.first(where: { $0.id == spaceID }),
              let current = spaces.first(where: \.isCurrent)
        else {
            log("cannot resolve spaces (target \(spaceID))")
            return false
        }
        let hops = destination.index - current.index
        guard hops != 0 else { return true }

        guard let windowID = SpaceBridge.windowID(for: target) else {
            log("no CGWindowID")
            return false
        }
        guard let originalFrame = WindowTargetResolver.readBackAXFrame(target) else {
            log("cannot read window frame")
            return false
        }
        guard let bounds = WindowTargetResolver.screenAXBounds(nearest: originalFrame) else {
            log("cannot resolve screen bounds")
            return false
        }

        // Grab the title bar far enough from the target edge that the drag is a real drag,
        // not a click: a window already hanging off the screen edge gives no travel at all.
        let edgeX: CGFloat = hops > 0 ? bounds.maxX - 2 : bounds.minX + 2
        let inset: CGFloat = 420
        let grabX: CGFloat = hops > 0
            ? min(max(originalFrame.midX, bounds.minX + 80), edgeX - inset)
            : max(min(originalFrame.midX, bounds.maxX - 80), bounds.minX + inset)
        let grab = CGPoint(x: grabX, y: originalFrame.minY + 12)
        let edge = CGPoint(x: edgeX, y: grab.y)
        // If the title bar is off-screen at that x, fall back to the top edge of the window.
        let grabPoint = CGPoint(
            x: min(max(grab.x, bounds.minX + 40), bounds.maxX - 40),
            y: min(max(grab.y, bounds.minY + 6), bounds.maxY - 6)
        )
        log("drag start grab=\(grabPoint) edge=\(edge) hops=\(hops) target=\(destination.index) frame=\(originalFrame)")

        // A background app's first click only activates the target; do that explicitly
        // first so the drag itself is not swallowed by the activation click.
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
        usleep(300_000)

        CGWarpMouseCursorPosition(grabPoint)
        CGAssociateMouseAndMouseCursorPosition(1)
        usleep(100_000)
        post(.leftMouseDown, at: grabPoint)
        usleep(110_000)
        // Two tiny moves first: some apps ignore a drag that starts already moving fast.
        post(.leftMouseDragged, at: CGPoint(x: grabPoint.x + 3, y: grabPoint.y))
        usleep(40_000)
        post(.leftMouseDragged, at: CGPoint(x: grabPoint.x + 9, y: grabPoint.y))
        usleep(40_000)

        // Walk to the edge in small steps so the drag is registered as a real drag.
        let steps = 18
        let startX = grabPoint.x
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: startX + (edgeX - startX) * progress, y: grab.y)
            post(.leftMouseDragged, at: point)
            usleep(22_000)
        }

        let frameMidDrag = WindowTargetResolver.readBackAXFrame(target)
        log("frame before=\(originalFrame) mid=\(frameMidDrag.map { "\($0)" } ?? "nil")")

        // While a window is being dragged, ⌃←/⌃→ carries it to the neighbouring Space.
        // That is far more reliable than holding at the screen edge, which this Mac does
        // not act on at all (verified: 3s of holding at 2px from the edge, no switch).
        var switches = 0
        var tick = 0
        let hopDeadline = Date().addingTimeInterval(hopsTimeout)
        var lastSwitch = Date()
        var currentNow = currentSpaceID(for: screen)
        let arrowKey: CGKeyCode = hops > 0 ? 124 : 123 // right / left
        while Date() < hopDeadline {
            // Tiny jitter keeps the drag alive between key presses.
            post(.leftMouseDragged, at: CGPoint(x: edgeX, y: grabPoint.y + (tick % 2 == 0 ? 1 : -1)))
            usleep(70_000)
            if Date().timeIntervalSince(lastSwitch) > 0.45 {
                lastSwitch = Date()
                postCtrlArrow(arrowKey)
            }
            currentNow = currentSpaceID(for: screen)
            tick += 1
            if tick % 8 == 0 {
                let f = WindowTargetResolver.readBackAXFrame(target)
                log("tick \(tick) cursor=(\(edgeX),\(grab.y)) frame=\(f.map { "\($0.origin)" } ?? "nil") space=\(currentNow.map(String.init) ?? "nil")")
            }
            if let currentNow, currentNow != current.id, currentNow == spaceID {
                break
            }
            if let currentNow, currentNow != current.id, Date().timeIntervalSince(lastSwitch) > 0.4 {
                switches += 1
                lastSwitch = Date()
                log("intermediate space \(currentNow)")
                if switches >= hops + 2 { break }
            }
        }

        post(.leftMouseUp, at: CGPoint(x: edgeX, y: grabPoint.y))
        CGWarpMouseCursorPosition(CGPoint(x: originalFrame.midX, y: originalFrame.minY + 12))
        usleep(120_000)

        let landed = SpaceBridge.spaceID(forWindow: windowID) == spaceID
        log("landed=\(landed) windowSpace=\(SpaceBridge.spaceID(forWindow: windowID).map(String.init) ?? "nil")")

        if landed {
            // The drag leaves the window wherever the pointer released; put it back.
            _ = try? WindowTargetResolver.applyFrame(target, axFrame: originalFrame)
            log("frame restored to \(originalFrame)")
        }
        return landed
    }
}

/// `--space-send <index>`: drives the real edge-drag mover against the frontmost window and
/// logs the result, so the gesture path can be verified without clicking anything.
@MainActor
enum SpaceSendProbe {
    static func run(spaceIndex: Int) {
        try? FileManager.default.removeItem(atPath: EdgeDragSpaceMover.logPath)
        guard WindowTargetResolver.isTrusted() else {
            print("ERROR accessibility permission required")
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let spaces = SpaceBridge.spaces(for: screen)
        guard let destination = spaces.first(where: { $0.index == spaceIndex }) else {
            print("ERROR no space \(spaceIndex)")
            return
        }
        guard let target = WindowTargetResolver.captureFrontmostTarget(excludingGridlet: true) else {
            print("ERROR no focused foreign window")
            return
        }
        let name = WindowTargetResolver.appDisplayName(for: target)
        EdgeDragSpaceMover.log("PROBE sending \(name) to space \(destination.index) (id \(destination.id))")
        let started = Date()
        let ok = EdgeDragSpaceMover.send(target: target, to: destination.id, on: screen)
        EdgeDragSpaceMover.log("PROBE result ok=\(ok) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    }
}
