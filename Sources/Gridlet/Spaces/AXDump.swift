import AppKit
import ApplicationServices
import Foundation

/// `--ax-dump`: dumps every Accessibility attribute of the frontmost foreign window
/// (name, type, whether settable) to a log file. Used to find out whether a window's Space
/// can be set over AX, since the SkyLight move refuses windows owned by other processes.
@MainActor
enum AXDump {
    static let logPath = "/tmp/gridlet-ax-dump.log"

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
        guard WindowTargetResolver.isTrusted() else {
            log("ERROR Accessibility permission required")
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            log("ERROR no frontmost application")
            return
        }
        log("frontmost app: \(app.localizedName ?? "?") pid=\(app.processIdentifier)")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 3)

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else {
            log("ERROR no focused window")
            return
        }
        let window = windowValue as! AXUIElement

        var namesRef: CFArray?
        guard AXUIElementCopyAttributeNames(window, &namesRef) == .success,
              let names = namesRef as? [String]
        else {
            log("ERROR could not read attribute names")
            return
        }
        log("attribute count: \(names.count)")
        for name in names.sorted() {
            var value: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(window, name as CFString, &value)
            var settable = DarwinBoolean(false)
            _ = AXUIElementIsAttributeSettable(window, name as CFString, &settable)
            var printable = "<err \(err.rawValue)>"
            if err == .success, let value {
                let typeID = CFGetTypeID(value)
                if typeID == CFStringGetTypeID() {
                    printable = "\"\((value as! String).prefix(80))\""
                } else if typeID == CFNumberGetTypeID() || typeID == CFBooleanGetTypeID() {
                    printable = "\(value)"
                } else if typeID == AXValueGetTypeID() {
                    printable = "<AXValue>"
                } else {
                    printable = "<\(typeID)>"
                }
            }
            log("  \(settable.boolValue ? "SETTABLE " : "         ")\(name) = \(printable)")
        }
        log("DONE")
    }
}
