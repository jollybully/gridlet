import AppKit
import Foundation

enum UISnapshotOptions {
    static func parseAppearance(_ name: String?) -> NSAppearance? {
        switch name?.lowercased() {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    static func panelDisplayMode(state: String?) -> PanelDisplayMode {
        switch state?.lowercased() {
        case "selected": return .snapshotSelected
        case "no-target": return .snapshotNoTarget
        case "error": return .snapshotError
        default: return .snapshotIdle
        }
    }
}

enum UISnapshot {
    @MainActor
    private static func captureWindowPNG(
        window: NSWindow,
        to path: String,
        appearanceName: String?
    ) -> Int {
        let appearance = UISnapshotOptions.parseAppearance(appearanceName)
        if let appearance {
            NSApp.appearance = appearance
            window.appearance = appearance
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard let root = StandardWindowLayout.snapshotRoot(for: window) else {
            fputs("ui-snapshot: no snapshot root\n", stderr)
            return 3
        }

        let captureAppearance = appearance ?? NSApp.effectiveAppearance
        guard let png = ViewHierarchySnapshot.pngData(of: root, appearance: captureAppearance) else {
            fputs("ui-snapshot: render failed\n", stderr)
            return 4
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fputs("ui-snapshot: write failed: \(error)\n", stderr)
            return 6
        }

        return 0
    }

    @MainActor
    static func capturePanelPNG(
        to path: String,
        appearanceName: String? = nil,
        state: String? = nil
    ) -> Int {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appearance = UISnapshotOptions.parseAppearance(appearanceName)
        if let appearance {
            NSApp.appearance = appearance
        }

        let coord = PanelCoordinator.shared
        coord.uiSmokeMode = false
        coord.snapshotDisplayMode = UISnapshotOptions.panelDisplayMode(state: state)
        coord.presentPanels()

        guard let panel = coord.firstPanelWindow() else {
            fputs("ui-snapshot: no panel window\n", stderr)
            return 2
        }

        if let appearance {
            panel.appearance = appearance
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.layoutIfNeeded()
        panel.displayIfNeeded()
        coord.firstPanelController()?.gridView.displayIfNeeded()

        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        guard let content = panel.contentView else {
            fputs("ui-snapshot: no content view\n", stderr)
            return 3
        }

        let captureAppearance = appearance ?? NSApp.effectiveAppearance
        guard let png = ViewHierarchySnapshot.pngData(of: content, appearance: captureAppearance) else {
            fputs("ui-snapshot: render failed\n", stderr)
            return 4
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fputs("ui-snapshot: write failed: \(error)\n", stderr)
            return 6
        }

        coord.snapshotDisplayMode = nil
        coord.dismissAll(reason: .monitorChange)
        return 0
    }

    @MainActor
    static func captureSettingsPNG(to path: String, appearanceName: String? = nil) -> Int {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        SettingsWindowController.shared.show()
        guard let window = SettingsWindowController.shared.window else {
            fputs("ui-snapshot: no settings window\n", stderr)
            return 2
        }

        let code = captureWindowPNG(window: window, to: path, appearanceName: appearanceName)
        window.orderOut(nil)
        return code
    }

    @MainActor
    static func capturePermissionPNG(to path: String, appearanceName: String? = nil) -> Int {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        PermissionWindowController.shared.show()
        guard let window = PermissionWindowController.shared.window else {
            fputs("ui-snapshot: no permission window\n", stderr)
            return 2
        }

        let code = captureWindowPNG(window: window, to: path, appearanceName: appearanceName)
        window.orderOut(nil)
        return code
    }
}
