import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        _ = PreviousAppTracker.shared
        NSApp.setActivationPolicy(.accessory)
        let previewRun = CommandLine.arguments.contains("--ui-smoke")
            || CommandLine.arguments.contains("--ui-smoke-dispatch")
        if !previewRun {
            let bar = MenuBarController()
            menuBar = bar
            bar.install()
            registerShowPanelHotKeyQuietly()
        }

        for arg in CommandLine.arguments {
            if arg == "--ui-smoke" {
                PanelCoordinator.shared.uiSmokeMode = true
                PanelCoordinator.shared.presentPanels()
            }
            if arg == "--ui-smoke-dispatch" {
                PanelCoordinator.shared.uiSmokeMode = true
                PanelCoordinator.shared.presentPanels()
                Task { @MainActor in
                    guard let panel = PanelCoordinator.shared.firstPanelWindow(),
                          let controller = PanelCoordinator.shared.firstPanelController() else {
                        fputs("ui-smoke-dispatch: no panel\n", stderr)
                        exit(1)
                    }
                    panel.makeFirstResponder(controller.gridView)
                    let result = InputRoutingDispatchCheck.run(on: panel, grid: controller.gridView)
                    PanelCoordinator.shared.dismissAll(reason: .monitorChange)
                    if result.panelOriginStable && result.commitCount >= 1 {
                        exit(0)
                    }
                    fputs(
                        "ui-smoke-dispatch: stable=\(result.panelOriginStable) commits=\(result.commitCount)\n",
                        stderr
                    )
                    exit(1)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelCoordinator.shared.togglePanels()
        return false
    }

    func registerShowPanelHotKey() throws {
        let binding = GridSettings.load().showPanelHotKey
        try HotKeyManager.shared.register(binding: binding) {
            Task { @MainActor in PanelCoordinator.shared.togglePanels() }
        }
    }

    private func registerShowPanelHotKeyQuietly() {
        do {
            try registerShowPanelHotKey()
        } catch {
            let binding = GridSettings.load().showPanelHotKey
            NSLog("Gridlet: fallback shortcut \(binding.displayString) not registered (\(error)). Use the menu bar icon.")
        }
    }
}
