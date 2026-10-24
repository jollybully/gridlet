import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// `--event-probe`: answers one question — can this app actually post synthetic input?
/// Warps the cursor, then types a character into the frontmost app and reads the focused
/// text value back over AX.
@MainActor
enum EventProbe {
    static let logPath = "/tmp/gridlet-event-probe.log"

    private static func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func run() {
        try? FileManager.default.removeItem(atPath: logPath)
        log("trusted=\(WindowTargetResolver.isTrusted())")

        // 1. Cursor warp
        let before = CGEvent(source: nil)?.location ?? .zero
        CGWarpMouseCursorPosition(CGPoint(x: 400, y: 400))
        usleep(120_000)
        let after = CGEvent(source: nil)?.location ?? .zero
        log("cursor before=\(before) after=\(after) warped=\(abs(after.x - 400) < 3 && abs(after.y - 400) < 3)")

        guard let front = NSWorkspace.shared.frontmostApplication else {
            log("no frontmost app")
            return
        }
        log("frontmost=\(front.localizedName ?? "?")")
        let appElement = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 3)

        // 2. Read the focused text value before/after typing
        func focusedValue() -> String? {
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                  let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value) == .success else { return nil }
            return value as? String
        }

        let valueBefore = focusedValue()
        log("focused value length before=\(valueBefore?.count ?? -1)")

        // 3. Type a '7' with an explicit HID event source
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey7: CGKeyCode = 26 // '7' on a US layout
        if let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey7, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        usleep(30_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey7, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
        usleep(250_000)

        let valueAfter = focusedValue()
        log("focused value length after=\(valueAfter?.count ?? -1) typed=\((valueAfter?.count ?? 0) > (valueBefore?.count ?? 0))")
        log("tail after=\(String((valueAfter ?? "").suffix(20)))")
        log("DONE")
    }
}
