import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// One Space on one display, in the display's own left-to-right order.
struct ManagedSpace: Equatable {
    let id: UInt64
    /// 1-based position on its display — this is the number the user sees.
    let index: Int
    let isCurrent: Bool
    /// Live window count; nil when the private call could not be made.
    let windowCount: Int?
}

struct ManagedDisplayInfo: Equatable {
    /// "Main" for the main display, otherwise the display UUID.
    let identifier: String
    let spaces: [ManagedSpace]
}

/// Reads and edits Spaces through SkyLight's private API.
///
/// Every private symbol is resolved with `dlsym` at runtime, so the module builds and
/// runs with no private headers and degrades to `isAvailable == false` rather than
/// failing to launch. Nothing here injects into another process.
enum SpaceBridge {
    private typealias DefaultConnectionFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias MoveWindowsFn = @convention(c) (Int32, CFArray, UInt64) -> Void
    private typealias SetCurrentSpaceFn = @convention(c) (Int32, CFString, UInt64) -> Void
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private struct Symbols {
        let connection: DefaultConnectionFn
        let copyDisplaySpaces: CopyDisplaySpacesFn
        let moveWindows: MoveWindowsFn
        let setCurrentSpace: SetCurrentSpaceFn
        let spacesForWindows: SpacesForWindowsFn
        let axGetWindow: AXGetWindowFn?
    }

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let symbols: Symbols? = {
        guard let handle = dlopen(skyLightPath, RTLD_NOW) else { return nil }
        func fn<T>(_ name: String, _ type: T.Type) -> T? {
            guard let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        guard let connection = fn("_CGSDefaultConnection", DefaultConnectionFn.self),
              let copyDisplaySpaces = fn("SLSCopyManagedDisplaySpaces", CopyDisplaySpacesFn.self),
              let moveWindows = fn("SLSMoveWindowsToManagedSpace", MoveWindowsFn.self),
              let setCurrentSpace = fn("SLSManagedDisplaySetCurrentSpace", SetCurrentSpaceFn.self),
              let spacesForWindows = fn("SLSCopySpacesForWindows", SpacesForWindowsFn.self)
        else { return nil }
        return Symbols(
            connection: connection,
            copyDisplaySpaces: copyDisplaySpaces,
            moveWindows: moveWindows,
            setCurrentSpace: setCurrentSpace,
            spacesForWindows: spacesForWindows,
            axGetWindow: {
                guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
                return unsafeBitCast(sym, to: AXGetWindowFn.self)
            }()
        )
    }()

    /// False means the private API isn't there (or a hardened future macOS removed it);
    /// callers must then hide the Space strip entirely and say so.
    static var isAvailable: Bool { symbols != nil }

    // MARK: - Reading

    static func displays() -> [ManagedDisplayInfo] {
        guard let symbols else { return [] }
        return displays(symbols: symbols)
    }

    static func spaces(for screen: NSScreen) -> [ManagedSpace] {
        guard let identifier = displayIdentifier(for: screen) else { return [] }
        let all = displays()
        if let match = all.first(where: { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }) {
            return match.spaces
        }
        // A display with no managed Spaces of its own reports as "Main" upstream.
        if CGDisplayIsMain(displayNumber(for: screen)) != 0,
           let main = all.first(where: { $0.identifier.caseInsensitiveCompare("Main") == .orderedSame }) {
            return main.spaces
        }
        return []
    }

    static func displayIdentifier(for screen: NSScreen) -> String? {
        let displayID = displayNumber(for: screen)
        if displayID != 0, CGDisplayIsMain(displayID) != 0 { return "Main" }
        guard displayID != 0,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return (CFUUIDCreateString(nil, uuid) as String?)?.uppercased()
    }

    static func displayNumber(for screen: NSScreen) -> CGDirectDisplayID {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 0 }
        return CGDirectDisplayID(number.uint32Value)
    }

    private static func displays(symbols: Symbols) -> [ManagedDisplayInfo] {
        guard let raw = symbols.copyDisplaySpaces(symbols.connection())?.takeRetainedValue() as? [NSDictionary] else {
            return []
        }
        // No window counts: SLSCopyWindowsWithOptionsAndTags returns shadow and helper
        // windows too (30-50 per Space on this machine), so a count on the chip would be
        // noise dressed up as information. `windowCounter` stays injectable for later.
        return parse(entries: raw, windowCounter: nil)
    }

    /// Pure parse step, split out so the ordering/current-space rules are testable
    /// without touching the window server.
    static func parse(entries: [NSDictionary], windowCounter: ((UInt64) -> Int?)?) -> [ManagedDisplayInfo] {
        entries.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String, !identifier.isEmpty else { return nil }
            let currentID = (entry["Current Space"] as? NSDictionary)?["ManagedSpaceID"] as? NSNumber
            let rawSpaces = entry["Spaces"] as? [NSDictionary] ?? []
            var spaces: [ManagedSpace] = []
            for rawSpace in rawSpaces {
                guard let id = (rawSpace["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
                // type 0 = a user Space; anything else (fullscreen, tiled) is not addressable here.
                let type = (rawSpace["type"] as? NSNumber)?.intValue ?? 0
                guard type == 0 else { continue }
                spaces.append(ManagedSpace(
                    id: id,
                    index: spaces.count + 1,
                    isCurrent: currentID?.uint64Value == id,
                    windowCount: windowCounter?(id)
                ))
            }
            guard !spaces.isEmpty else { return nil }
            return ManagedDisplayInfo(identifier: identifier, spaces: spaces)
        }
    }

    /// The Space a window currently lives on.
    static func spaceID(forWindow windowID: CGWindowID) -> UInt64? {
        guard let symbols else { return nil }
        let windows = [NSNumber(value: windowID)] as CFArray
        guard let spaces = symbols.spacesForWindows(symbols.connection(), 0x7, windows)?.takeRetainedValue() as? [NSNumber] else {
            return nil
        }
        return spaces.first?.uint64Value
    }

    // MARK: - Writing

    /// Moves a window to another Space, keeping its frame. Verified by reading the
    /// window's space membership back — a `void` private call is not proof it worked.
    @discardableResult
    static func move(window windowID: CGWindowID, to spaceID: UInt64) -> Bool {
        guard let symbols else { return false }
        if self.spaceID(forWindow: windowID) == spaceID { return true }
        let windows = [NSNumber(value: windowID)] as CFArray
        symbols.moveWindows(symbols.connection(), windows, spaceID)
        for _ in 0..<6 {
            if self.spaceID(forWindow: windowID) == spaceID { return true }
            Thread.sleep(forTimeInterval: 0.04)
        }
        return self.spaceID(forWindow: windowID) == spaceID
    }

    @discardableResult
    static func switchTo(spaceID: UInt64, displayIdentifier: String) -> Bool {
        guard let symbols else { return false }
        symbols.setCurrentSpace(symbols.connection(), displayIdentifier as CFString, spaceID)
        return true
    }

    // MARK: - Window identity

    /// AX elements carry no window ID, so ask the private accessor, then fall back to
    /// the private `AXWindowNumber` attribute.
    static func windowID(for target: WindowTarget) -> CGWindowID? {
        if let axGetWindow = symbols?.axGetWindow {
            var windowID: CGWindowID = 0
            if axGetWindow(target.axElement, &windowID) == .success, windowID != 0 {
                return windowID
            }
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(target.axElement, "AXWindowNumber" as CFString, &value) == .success,
           let number = value as? NSNumber, number.uint32Value != 0 {
            return number.uint32Value
        }
        return nil
    }
}
