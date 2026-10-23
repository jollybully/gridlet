import Foundation

enum MenuBarReadiness {
    enum Status: Equatable {
        case ready
        case accessibilityNeeded
        case shortcutUnavailable
    }

    static func status(
        accessibilityTrusted: Bool,
        hotKeyRegistered: Bool
    ) -> Status {
        if !accessibilityTrusted {
            return .accessibilityNeeded
        }
        if !hotKeyRegistered {
            return .shortcutUnavailable
        }
        return .ready
    }

    static func statusMenuTitle(for status: Status) -> String {
        switch status {
        case .ready:
            return "Gridlet — Ready"
        case .accessibilityNeeded:
            return "Accessibility needed"
        case .shortcutUnavailable:
            return "Shortcut unavailable"
        }
    }

    static func tooltip(accessibilityTrusted: Bool, hotKeyRegistered: Bool) -> String {
        let binding = GridSettings.load().showPanelHotKey.displayString
        switch status(accessibilityTrusted: accessibilityTrusted, hotKeyRegistered: hotKeyRegistered) {
        case .ready:
            return "Gridlet — press \(binding) to open the grid"
        case .accessibilityNeeded:
            return "Gridlet — enable Accessibility to resize windows"
        case .shortcutUnavailable:
            return "Gridlet — shortcut not registered; use Show Grid"
        }
    }
}
