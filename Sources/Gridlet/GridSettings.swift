import AppKit
import Carbon
import Carbon.HIToolbox
import Foundation

struct HotKeyBinding: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShowPanel = HotKeyBinding(keyCode: 49, modifiers: UInt32(controlKey | optionKey)) // Space

    var displayString: String {
        HotKeyDisplay.string(keyCode: keyCode, modifiers: modifiers)
    }

    var isValidGlobal: Bool {
        (modifiers & UInt32(controlKey | optionKey | cmdKey)) != 0
    }
}

enum GridSettings {
    static let minGrid = 1
    static let maxGrid = 12

    static let defaultsKey = "org.gridlet.Gridlet.settings"

    struct Snapshot: Codable, Equatable, Sendable {
        var rows: Int = 8
        var columns: Int = 8
        var keepPanelOpen: Bool = false
        var showPreview: Bool = true
        var showPanelHotKey: HotKeyBinding = .defaultShowPanel
        var launchAtLogin: Bool = false
    }

    /// Legacy on-disk shape (presets / extra fields ignored on load).
    private struct LegacySnapshot: Decodable {
        var rows: Int?
        var columns: Int?
        var keepPanelOpen: Bool?
        var showPreview: Bool?
        var showPanelHotKey: HotKeyBinding?
        var launchAtLogin: Bool?
    }

    static func clampGrid(_ value: Int) -> Int {
        min(max(value, minGrid), maxGrid)
    }

    static func load(from defaults: UserDefaults = .standard) -> Snapshot {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return Snapshot()
        }
        return migrate(from: data)
    }

    /// Decodes complete legacy JSON, sparse partial objects, or current format.
    static func migrate(from data: Data) -> Snapshot {
        if let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return normalized(snap)
        }
        if let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            var snap = Snapshot()
            if let rows = legacy.rows { snap.rows = rows }
            if let columns = legacy.columns { snap.columns = columns }
            if let keep = legacy.keepPanelOpen { snap.keepPanelOpen = keep }
            if let preview = legacy.showPreview { snap.showPreview = preview }
            if let hotKey = legacy.showPanelHotKey { snap.showPanelHotKey = hotKey }
            if let login = legacy.launchAtLogin { snap.launchAtLogin = login }
            return normalized(snap)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var snap = Snapshot()
            if let rows = object["rows"] as? Int { snap.rows = rows }
            if let columns = object["columns"] as? Int { snap.columns = columns }
            if let keep = object["keepPanelOpen"] as? Bool { snap.keepPanelOpen = keep }
            if let preview = object["showPreview"] as? Bool { snap.showPreview = preview }
            if let login = object["launchAtLogin"] as? Bool { snap.launchAtLogin = login }
            return normalized(snap)
        }
        return Snapshot()
    }

    private static func normalized(_ snap: Snapshot) -> Snapshot {
        var s = snap
        s.rows = clampGrid(s.rows)
        s.columns = clampGrid(s.columns)
        return s
    }

    static func save(_ snapshot: Snapshot, to defaults: UserDefaults = .standard) {
        let s = normalized(snapshot)
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}

enum HotKeyDisplay {
    static func string(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode, carbonModifiers: modifiers))
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt32, carbonModifiers: UInt32 = 0) -> String {
        if let fixed = fixedKeyNames[keyCode] {
            return fixed
        }
        if let translated = translatedCharacter(keyCode: keyCode, carbonModifiers: carbonModifiers) {
            return translated
        }
        if let fallback = carbonVirtualKeyFallback(keyCode: keyCode, carbonModifiers: carbonModifiers) {
            return fallback
        }
        return "Key\(keyCode)"
    }

    private static let fixedKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_KeypadPlus): "+",
        UInt32(kVK_ANSI_KeypadMinus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_LeftBracket): "[",
    ]

    private static func translatedCharacter(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutProperty = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = unsafeBitCast(layoutProperty, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var realLength: Int = 0
        let modifierKeyState = UInt32((carbonModifiers >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())

        let status = layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyLayoutPtr in
            UCKeyTranslate(
                keyLayoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                modifierKeyState,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &realLength,
                &chars
            )
        }
        guard status == noErr, realLength > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: realLength)
        return s.isEmpty ? nil : s
    }

    private static func carbonVirtualKeyFallback(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        let shifted = (carbonModifiers & UInt32(shiftKey)) != 0
        switch Int(keyCode) {
        case kVK_ANSI_1: return shifted ? "!" : "1"
        case kVK_ANSI_2: return shifted ? "@" : "2"
        case kVK_ANSI_3: return shifted ? "#" : "3"
        case kVK_ANSI_4: return shifted ? "$" : "4"
        case kVK_ANSI_5: return shifted ? "%" : "5"
        case kVK_ANSI_6: return shifted ? "^" : "6"
        case kVK_ANSI_7: return shifted ? "&" : "7"
        case kVK_ANSI_8: return shifted ? "*" : "8"
        case kVK_ANSI_9: return shifted ? "(" : "9"
        case kVK_ANSI_0: return shifted ? ")" : "0"
        default:
            break
        }
        let letters: [UInt32: Character] = [
            UInt32(kVK_ANSI_A): "a", UInt32(kVK_ANSI_S): "s", UInt32(kVK_ANSI_D): "d",
            UInt32(kVK_ANSI_F): "f", UInt32(kVK_ANSI_H): "h", UInt32(kVK_ANSI_G): "g",
            UInt32(kVK_ANSI_Z): "z", UInt32(kVK_ANSI_X): "x", UInt32(kVK_ANSI_C): "c",
            UInt32(kVK_ANSI_V): "v", UInt32(kVK_ANSI_B): "b", UInt32(kVK_ANSI_Q): "q",
            UInt32(kVK_ANSI_W): "w", UInt32(kVK_ANSI_E): "e", UInt32(kVK_ANSI_R): "r",
            UInt32(kVK_ANSI_Y): "y", UInt32(kVK_ANSI_T): "t",
        ]
        if let ch = letters[keyCode] {
            return String(shifted ? Character(ch.uppercased()) : ch)
        }
        return nil
    }
}

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var m: UInt32 = 0
        if contains(.control) { m |= UInt32(controlKey) }
        if contains(.option) { m |= UInt32(optionKey) }
        if contains(.shift) { m |= UInt32(shiftKey) }
        if contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}

let controlKey: UInt32 = UInt32(Carbon.controlKey)
let shiftKey: UInt32 = UInt32(Carbon.shiftKey)
let optionKey: UInt32 = UInt32(Carbon.optionKey)
let cmdKey: UInt32 = UInt32(Carbon.cmdKey)
