import CoreGraphics
import Foundation

/// Exits 0 when a floating panel-sized window owned by `pid` is on screen (no Automation permission).
guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: check_panel_window.swift <pid>\n", stderr)
    exit(2)
}

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("check_panel_window: CGWindowListCopyWindowInfo failed\n", stderr)
    exit(1)
}

// NSPanel.level == .floating → layer 3
let floatingLayer = 3
let minWidth: CGFloat = 250
let minHeight: CGFloat = 300

var found = false
for win in list {
    guard let ownerPID = win[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else { continue }
    guard let layer = win[kCGWindowLayer as String] as? Int, layer == floatingLayer else { continue }
    guard let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
          let w = bounds["Width"], let h = bounds["Height"] else { continue }
    if w >= minWidth && h >= minHeight {
        found = true
        break
    }
}

if !found {
    fputs("check_panel_window: no floating panel window for pid \(pid)\n", stderr)
    exit(1)
}

exit(0)
