import ApplicationServices
import Foundation

/// Walks another process's AX tree for AXIdentifier == gridlet-grid (caller needs Accessibility for that PID).
guard CommandLine.arguments.count >= 2, let pid = pid_t(CommandLine.arguments[1]) else {
    fputs("usage: verify_ax_grid.swift <gridlet-pid>\n", stderr)
    exit(2)
}

let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 3)

func axString(_ element: AXUIElement, _ attr: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
    return value as? String
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let arr = value as? [AXUIElement] else { return [] }
    return arr
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let posRef = posValue, let sizeRef = sizeValue else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
          AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}

func findGrid(_ element: AXUIElement) -> AXUIElement? {
    if axString(element, kAXIdentifierAttribute) == "gridlet-grid" {
        return element
    }
    for child in axChildren(element) {
        if let hit = findGrid(child) { return hit }
    }
    return nil
}

guard let grid = findGrid(app) else {
    fputs("verify_ax_grid: no AX element with identifier gridlet-grid\n", stderr)
    exit(1)
}

let label = axString(grid, kAXTitleAttribute) ?? axString(grid, kAXDescriptionAttribute) ?? ""
let role = axString(grid, kAXRoleAttribute) ?? ""
let frame = axFrame(grid)

print("gridlet-grid role=\(role) label=\(label) frame=\(frame?.debugDescription ?? "nil")")

guard role == "AXGroup" || role == "group" else {
    fputs("verify_ax_grid: unexpected role \(role)\n", stderr)
    exit(1)
}
guard label.contains("by"), let frame, frame.width > 50, frame.height > 50 else {
    fputs("verify_ax_grid: missing label or frame\n", stderr)
    exit(1)
}

exit(0)
