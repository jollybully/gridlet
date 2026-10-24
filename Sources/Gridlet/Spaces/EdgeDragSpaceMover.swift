import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Moves a window belonging to *another* application into a different Space.
///
/// SkyLight's `SLSMoveWindowsToManagedSpace` (and the remove/add primitives) only act on
/// windows owned by the calling process, and AX exposes no space attribute, so the only
/// public path is the gesture a human performs: grab the title bar, drag to the screen edge,
/// hold while macOS switches Spaces, release. That needs Accessibility (event posting) only —
/// no injection into Dock, no SIP changes.
///
/// `plan(...)` gathers everything on the main actor; `execute(plan)` blocks for a couple of
/// seconds while the drag runs, so callers dispatch it off the main thread.
enum EdgeDragSpaceMover {
    static let logPath = "/tmp/gridlet-space-send.log"

    struct Plan {
        let windowID: CGWindowID
        let element: AXUIElement
        let pid: pid_t
        let hops: Int
        let edgeX: CGFloat
        let grabPoint: CGPoint
        let destinationSpaceID: UInt64
        let currentSpaceID: UInt64
        let originalFrame: CGRect
        let holdTimeout: TimeInterval
    }

    static func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static var isSupported: Bool {
        SpaceBridge.isAvailable && AXIsProcessTrusted()
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

    @MainActor
    static func plan(
        target: WindowTarget,
        to space: ManagedSpace,
        on screen: NSScreen,
        holdTimeout: TimeInterval = 2.5
    ) -> Plan? {
        guard SpaceBridge.isAvailable else {
            log("spaces unavailable")
            return nil
        }
        let spaces = SpaceBridge.spaces(for: screen)
        guard let destination = spaces.first(where: { $0.id == space.id }),
              let current = spaces.first(where: \.isCurrent)
        else {
            log("cannot resolve spaces (target \(space.id))")
            return nil
        }
        let hops = destination.index - current.index
        guard hops != 0 else { return nil }
        guard let windowID = SpaceBridge.windowID(for: target),
              var originalFrame = WindowTargetResolver.readBackAXFrame(target),
              var bounds = WindowTargetResolver.screenAXBounds(nearest: originalFrame)
        else {
            log("cannot read window id, frame or screen bounds")
            return nil
        }

        // A window hanging off the screen gives no usable title bar and no travel; bring it
        // back on screen first, and treat that position as the frame to restore.
        if !bounds.contains(originalFrame) {
            var centre = CGPoint(
                x: bounds.midX - originalFrame.width / 2,
                y: bounds.midY - originalFrame.height / 2
            )
            if let value = AXValueCreate(.cgPoint, &centre) {
                AXUIElementSetAttributeValue(target.axElement, kAXPositionAttribute as CFString, value)
                usleep(120_000)
            }
            if let refreshed = WindowTargetResolver.readBackAXFrame(target) {
                originalFrame = refreshed
                if let refreshedBounds = WindowTargetResolver.screenAXBounds(nearest: refreshed) {
                    bounds = refreshedBounds
                }
                log("pulled off-screen window back to \(refreshed.origin)")
            }
        }
        // Park the pointer on the physical edge: the switch only arms within a pixel of it.
        let edgeX: CGFloat = hops > 0 ? bounds.maxX - 0.5 : bounds.minX + 0.5
        // Grab the window's own title bar (never a point outside it, or the drag takes hold
        // of nothing), inside the screen.
        var grabX = min(max(originalFrame.midX, originalFrame.minX + 80), originalFrame.maxX - 80)
        grabX = min(max(grabX, bounds.minX + 60), bounds.maxX - 60)
        // A window already flush against the target edge leaves no travel, so nudge it away
        // first; the original frame is restored after the move either way.
        if abs(grabX - edgeX) < 220, let element = Optional(target.axElement) {
            var nudged = originalFrame.origin
            nudged.x = hops > 0 ? max(bounds.minX, edgeX - 600) : min(bounds.maxX - originalFrame.width, edgeX + 600)
            if var point = Optional(nudged) {
                if let value = AXValueCreate(.cgPoint, &point) {
                    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
                    usleep(120_000)
                    if let moved = WindowTargetResolver.readBackAXFrame(target) {
                        log("nudged window to \(moved.origin) for travel")
                        grabX = min(max(moved.midX, moved.minX + 80), moved.maxX - 80)
                        grabX = min(max(grabX, bounds.minX + 60), bounds.maxX - 60)
                    }
                }
            }
        }
        let grabPoint = CGPoint(
            x: grabX,
            y: min(max(originalFrame.minY + 12, bounds.minY + 4), bounds.maxY - 4)
        )
        log("plan grab=\(grabPoint) edgeX=\(edgeX) hops=\(hops) destination=\(destination.index) frame=\(originalFrame)")
        return Plan(
            windowID: windowID,
            element: target.axElement,
            pid: target.pid,
            hops: hops,
            edgeX: edgeX,
            grabPoint: grabPoint,
            destinationSpaceID: destination.id,
            currentSpaceID: current.id,
            originalFrame: originalFrame,
            holdTimeout: holdTimeout
        )
    }

    struct Result {
        let landed: Bool
        let windowSpace: UInt64?
    }

    private static func postCtrlArrow(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.flags = .maskControl
            down.post(tap: .cghidEventTap)
        }
        usleep(40_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.flags = .maskControl
            up.post(tap: .cghidEventTap)
        }
    }

    /// Blocks for a couple of seconds: dispatch this off the main thread.
    ///
    /// While a window is being dragged, ⌃←/⌃→ moves *that window* one Space, which is the only
    /// way to get single-Space granularity here: holding at the screen edge moves it two
    /// Spaces per hold on this machine (animations off), so odd offsets are unreachable.
    @discardableResult
    static func execute(_ plan: Plan) -> Result {
        // 1. Focus click. A press on an inactive window's title bar only activates the app,
        //    so a drag starting there gets swallowed.
        NSRunningApplication(processIdentifier: plan.pid)?.activate(options: [])
        usleep(320_000)
        CGWarpMouseCursorPosition(plan.grabPoint)
        CGAssociateMouseAndMouseCursorPosition(1)
        usleep(140_000)
        post(.leftMouseDown, at: plan.grabPoint)
        usleep(60_000)
        post(.leftMouseUp, at: plan.grabPoint)
        usleep(200_000)

        // 2. Start a real drag: press, then move a little so the window is "in hand".
        post(.leftMouseDown, at: plan.grabPoint)
        usleep(110_000)
        let direction: CGFloat = plan.hops > 0 ? 1 : -1
        for step in 1...8 {
            let point = CGPoint(x: plan.grabPoint.x + direction * CGFloat(step) * 12, y: plan.grabPoint.y)
            post(.leftMouseDragged, at: point)
            usleep(20_000)
        }
        let grabbed = SpaceBridge.spaceID(forWindow: plan.windowID)
        log("drag in hand: windowSpace=\(grabbed.map(String.init) ?? "nil")")

        // 3. Step one Space at a time with ⌃←/⌃→, checking after each press.
        let arrow: CGKeyCode = plan.hops > 0 ? 124 : 123 // right / left
        let maxPresses = abs(plan.hops) + 3
        var presses = 0
        var space = grabbed
        while presses < maxPresses, space != plan.destinationSpaceID {
            postCtrlArrow(arrow)
            presses += 1
            usleep(260_000)
            space = SpaceBridge.spaceID(forWindow: plan.windowID)
            log("press \(presses) -> windowSpace=\(space.map(String.init) ?? "nil")")
        }

        // 4. If the keyboard route did nothing, fall back to the edge hold.
        if space != plan.destinationSpaceID, presses > 0, space == grabbed {
            log("keyboard stepping had no effect, falling back to edge hold")
            let steps = 26
            for step in 1...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: plan.grabPoint.x + (plan.edgeX - plan.grabPoint.x) * progress, y: plan.grabPoint.y)
                post(.leftMouseDragged, at: point)
                usleep(20_000)
            }
            let dwell = 0.30
            usleep(useconds_t(dwell * 1_000_000))
            log("held at edge for \(String(format: "%.2f", dwell))s")
            space = SpaceBridge.spaceID(forWindow: plan.windowID)
        }

        post(.leftMouseUp, at: CGPoint(x: plan.grabPoint.x + direction * 96, y: plan.grabPoint.y))
        usleep(250_000)
        CGWarpMouseCursorPosition(CGPoint(x: plan.originalFrame.midX, y: plan.originalFrame.minY + 12))
        usleep(150_000)

        let landed = SpaceBridge.spaceID(forWindow: plan.windowID) == plan.destinationSpaceID
        log("landed=\(landed) windowSpace=\(SpaceBridge.spaceID(forWindow: plan.windowID).map(String.init) ?? "nil") presses=\(presses)")

        // The drag parks the window where the pointer released. Restore the frame whatever
        // happened: a failed attempt must not leave the window displaced.
        var origin = plan.originalFrame.origin
        var size = plan.originalFrame.size
        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(plan.element, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(plan.element, kAXSizeAttribute as CFString, value)
        }
        log("frame restored to \(plan.originalFrame)")
        return Result(landed: landed, windowSpace: SpaceBridge.spaceID(forWindow: plan.windowID))
    }
}

/// `--space-send <index>`: drives the real mover against the frontmost window and logs the
/// result, so the gesture path can be verified without clicking anything.
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
        guard let plan = EdgeDragSpaceMover.plan(target: target, to: destination, on: screen) else {
            EdgeDragSpaceMover.log("PROBE could not build a plan")
            return
        }
        let started = Date()
        var landed = false
        for attempt in 1...6 {
            guard let plan = EdgeDragSpaceMover.plan(target: target, to: destination, on: screen) else { break }
            let result = EdgeDragSpaceMover.execute(plan)
            EdgeDragSpaceMover.log("PROBE attempt \(attempt) landed=\(result.landed) space=\(result.windowSpace.map(String.init) ?? "nil")")
            if result.landed {
                landed = true
                break
            }
        }
        EdgeDragSpaceMover.log("PROBE result ok=\(landed) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    }
}
