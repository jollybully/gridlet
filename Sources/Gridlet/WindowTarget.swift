import AppKit
import ApplicationServices
import Foundation

struct WindowTarget: Equatable {
    let pid: pid_t
    let axElement: AXUIElement

    static func == (lhs: WindowTarget, rhs: WindowTarget) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.axElement, rhs.axElement)
    }
}

enum WindowTargetError: LocalizedError, Equatable {
    case notTrusted
    case noTarget
    case notMovable
    case minimized
    case fullscreen
    case sheetOrDrawer
    case desktop
    case stale
    case belowMinimumSize(required: CGSize, attempted: CGSize)
    case constrainedSize(requested: CGRect, actual: CGRect)
    case axFailure(String)

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Accessibility permission is required."
        case .noTarget:
            return "No suitable window is focused."
        case .notMovable:
            return "This window cannot be moved or resized."
        case .minimized:
            return "Minimized windows cannot be resized."
        case .fullscreen:
            return "Fullscreen windows are not supported."
        case .sheetOrDrawer:
            return "Sheets and drawers are not supported."
        case .desktop:
            return "The desktop cannot be resized."
        case .stale:
            return "The target window is no longer available."
        case .belowMinimumSize(let required, let attempted):
            return String(
                format: "Window minimum size is %.0f×%.0f; selection would be %.0f×%.0f.",
                required.width, required.height, attempted.width, attempted.height
            )
        case .constrainedSize(let requested, let actual):
            return String(
                format: "Window could not be resized to %.0f×%.0f at (%.0f, %.0f); actual frame is %.0f×%.0f at (%.0f, %.0f).",
                requested.width, requested.height, requested.origin.x, requested.origin.y,
                actual.width, actual.height, actual.origin.x, actual.origin.y
            )
        case .axFailure(let msg):
            return "Accessibility error: \(msg)"
        }
    }
}

enum WindowTargetResolver {
    private static let axTimeoutSeconds: Float = 3
    private static let frameTolerance: CGFloat = 1.5

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptForTrust() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    static func captureFrontmostTarget(excludingGridlet: Bool = true) -> WindowTarget? {
        guard isTrusted() else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        if excludingGridlet, frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        if isFinderDesktop(app: frontApp) {
            return nil
        }
        return target(for: frontApp)
    }

    private static func isFinderDesktop(app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier == "com.apple.finder" else { return false }
        guard isTrusted() else { return true }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, axTimeoutSeconds)
        guard let window = focusedWindow(of: appElement) else { return true }
        let role = stringAttribute(window, kAXRoleAttribute) ?? ""
        return role == AXRoles.desktop
    }

    static func target(for app: NSRunningApplication) -> WindowTarget? {
        target(pid: app.processIdentifier)
    }

    static func target(pid: pid_t, allowGridlet: Bool = false) -> WindowTarget? {
        guard isTrusted() else { return nil }
        if !allowGridlet, pid == ProcessInfo.processInfo.processIdentifier { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeoutSeconds)
        guard let window = focusedWindow(of: appElement) else { return nil }
        AXUIElementSetMessagingTimeout(window, axTimeoutSeconds)
        guard validateWindow(window, pid: pid) else { return nil }
        return WindowTarget(pid: pid, axElement: window)
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard err == .success, let ref = value, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func validateWindow(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard canReadFrame(window) else { return false }

        let role = stringAttribute(window, kAXRoleAttribute) ?? ""
        guard role == kAXWindowRole as String else { return false }

        if role == AXRoles.systemWide || role == AXRoles.sheet || role == AXRoles.drawer || role == AXRoles.desktop {
            return false
        }
        if boolAttribute(window, kAXMinimizedAttribute) == true {
            return false
        }
        if isFullscreen(window) {
            return false
        }
        if boolAttribute(window, kAXModalAttribute) == true {
            return false
        }
        let subrole = stringAttribute(window, kAXSubroleAttribute) ?? ""
        if !subrole.isEmpty {
            let standard = kAXStandardWindowSubrole as String
            if subrole == standard {
                // ok
            } else if subrole.contains("Fullscreen") || subrole == AXRoles.sheet {
                return false
            } else {
                return false
            }
        }
        guard boolAttribute(window, "AXResizable") != false else { return false }
        guard boolAttribute(window, "AXMovable") != false else { return false }
        guard isAttributeSettable(window, kAXPositionAttribute) else { return false }
        guard isAttributeSettable(window, kAXSizeAttribute) else { return false }
        return true
    }

    private static func canReadFrame(_ window: AXUIElement) -> Bool {
        pointAttribute(window, kAXPositionAttribute) != nil && sizeAttribute(window, kAXSizeAttribute) != nil
    }

    private static func isFullscreen(_ window: AXUIElement) -> Bool {
        if let full = boolAttribute(window, "AXFullScreen") {
            return full
        }
        return false
    }

    static func appDisplayName(for target: WindowTarget) -> String {
        if let app = NSRunningApplication(processIdentifier: target.pid) {
            return app.localizedName ?? "Application"
        }
        return "Application"
    }

    static func appIcon(for target: WindowTarget) -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: target.pid) {
            return app.icon
        }
        return nil
    }

    static func isStillValid(_ target: WindowTarget) -> Bool {
        guard isTrusted() else { return false }
        var pid: pid_t = 0
        if AXUIElementGetPid(target.axElement, &pid) != .success || pid != target.pid {
            return false
        }
        AXUIElementSetMessagingTimeout(target.axElement, axTimeoutSeconds)
        return validateWindow(target.axElement, pid: pid)
    }

    /// Result of asking a window to take a frame. A window that cannot honour the
    /// requested size (e.g. its minimum size is larger) is still moved to the
    /// closest reachable position/size instead of being left untouched.
    struct FrameApplicationOutcome {
        let requested: CGRect
        let applied: CGRect

        var wasAdjusted: Bool {
            abs(requested.width - applied.width) > 1.5
                || abs(requested.height - applied.height) > 1.5
                || abs(requested.origin.x - applied.origin.x) > 1.5
                || abs(requested.origin.y - applied.origin.y) > 1.5
        }
    }

    @discardableResult
    static func applyFrame(_ target: WindowTarget, axFrame: CGRect) throws -> FrameApplicationOutcome {
        guard isTrusted() else { throw WindowTargetError.notTrusted }
        guard isStillValid(target) else { throw WindowTargetError.stale }

        AXUIElementSetMessagingTimeout(target.axElement, axTimeoutSeconds)

        let original = readBackAXFrame(target)
        var didRestore = false
        func restoreOnce() {
            guard !didRestore, let original else { return }
            didRestore = true
            restoreFrame(target, axFrame: original)
        }

        // Deliberately no early bail-out for AXMinSize: AX clamps the size for us,
        // and a window slightly larger than the requested cell is much more useful
        // than refusing to move it at all.
        for pass in 0..<3 {
            if !setAXSize(target.axElement, kAXSizeAttribute, axFrame.size) {
                restoreOnce()
                throw WindowTargetError.axFailure("size")
            }
            if !setAXPoint(target.axElement, kAXPositionAttribute, axFrame.origin) {
                restoreOnce()
                throw WindowTargetError.axFailure("position")
            }
            if !setAXSize(target.axElement, kAXSizeAttribute, axFrame.size) {
                restoreOnce()
                throw WindowTargetError.axFailure("size retry")
            }
            if !setAXPoint(target.axElement, kAXPositionAttribute, axFrame.origin) {
                restoreOnce()
                throw WindowTargetError.axFailure("position retry")
            }

            if let actual = readBackAXFrame(target), framesMatch(requested: axFrame, actual: actual) {
                return FrameApplicationOutcome(requested: axFrame, applied: actual)
            }
            if pass < 2 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        guard let clamped = readBackAXFrame(target) else {
            restoreOnce()
            throw WindowTargetError.axFailure("readback failed")
        }

        // Best effort: keep the size the window gave us, anchor it at the requested
        // origin, and pull it back inside the target display so a min-size window in
        // a corner stays fully visible.
        let bestEffort = bestEffortFrame(requested: axFrame, achieved: clamped)
        _ = setAXSize(target.axElement, kAXSizeAttribute, bestEffort.size)
        _ = setAXPoint(target.axElement, kAXPositionAttribute, bestEffort.origin)

        guard let final = readBackAXFrame(target) else {
            restoreOnce()
            throw WindowTargetError.axFailure("readback failed after adjustment")
        }

        if final.size.width < 1 || final.size.height < 1 {
            restoreOnce()
            throw WindowTargetError.axFailure("window reported an empty size")
        }

        NSLog(
            "Gridlet adjusted constrained window: requested \(axFrame) applied \(final)"
        )
        return FrameApplicationOutcome(requested: axFrame, applied: final)
    }

    /// Anchors the achieved size where the user asked for the window, then clamps it
    /// into the nearest display so nothing is pushed off-screen.
    static func bestEffortFrame(requested: CGRect, achieved: CGRect) -> CGRect {
        var frame = CGRect(origin: requested.origin, size: achieved.size)
        guard let bounds = screenAXBounds(nearest: frame) else { return frame }

        if frame.width > bounds.width {
            frame.size.width = bounds.width
        }
        if frame.height > bounds.height {
            frame.size.height = bounds.height
        }
        frame.origin.x = min(max(frame.origin.x, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, bounds.minY), bounds.maxY - frame.height)
        return frame
    }

    /// Visible screen regions expressed in Accessibility (top-left origin) space.
    static func screenAXBounds(nearest rect: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let primaryTop = ScreenGeometry.primaryTopY(screens: screens)
        let candidates = screens.map { ScreenGeometry.cocoaRectToAX($0.visibleFrame, primaryTopY: primaryTop) }

        let best = candidates.max { lhs, rhs in
            lhs.intersection(rect).area < rhs.intersection(rect).area
        }
        if let best, !best.intersection(rect).isNull, best.intersection(rect).area > 0 {
            return best
        }
        // No overlap: pick the display whose centre is closest to the requested rect.
        return candidates.min { lhs, rhs in
            let dl = hypot(lhs.midX - rect.midX, lhs.midY - rect.midY)
            let dr = hypot(rhs.midX - rect.midX, rhs.midY - rect.midY)
            return dl < dr
        }
    }

    private static func restoreFrame(_ target: WindowTarget, axFrame: CGRect) {
        _ = setAXSize(target.axElement, kAXSizeAttribute, axFrame.size)
        _ = setAXPoint(target.axElement, kAXPositionAttribute, axFrame.origin)
    }

    private static func framesMatch(requested: CGRect, actual: CGRect) -> Bool {
        abs(requested.origin.x - actual.origin.x) <= frameTolerance
            && abs(requested.origin.y - actual.origin.y) <= frameTolerance
            && abs(requested.width - actual.width) <= frameTolerance
            && abs(requested.height - actual.height) <= frameTolerance
    }

    static func readBackAXFrame(_ target: WindowTarget) -> CGRect? {
        guard let pos = pointAttribute(target.axElement, kAXPositionAttribute),
              let size = sizeAttribute(target.axElement, kAXSizeAttribute) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private static func setAXPoint(_ element: AXUIElement, _ attr: String, _ point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, attr as CFString, value) == .success
    }

    private static func setAXSize(_ element: AXUIElement, _ attr: String, _ size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, attr as CFString, value) == .success
    }

    private static func isAttributeSettable(_ element: AXUIElement, _ attr: String) -> Bool {
        var settable = DarwinBoolean(false)
        let err = AXUIElementIsAttributeSettable(element, attr as CFString, &settable)
        return err == .success && settable.boolValue
    }

    private static func stringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return value as? Bool
        }
        return nil
    }

    private static func pointAttribute(_ element: AXUIElement, _ attr: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        guard let axVal = value, CFGetTypeID(axVal) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axVal as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attr: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        guard let axVal = value, CFGetTypeID(axVal) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axVal as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}

private enum AXRoles {
    static let systemWide = "AXSystemWide"
    static let sheet = "AXSheet"
    static let drawer = "AXDrawer"
    static let desktop = "AXDesktop"
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}
