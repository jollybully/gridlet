import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem()

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Gridlet menu")
            button.image?.isTemplate = true
        }

        statusMenuItem.isEnabled = false
        menu.delegate = self
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Grid", action: #selector(showGrid), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Gridlet", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }

        item.menu = menu
        refreshStatus()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    func refreshStatus(accessibilityTrusted: Bool? = nil, hotKeyRegistered: Bool? = nil) {
        let trusted = accessibilityTrusted ?? WindowTargetResolver.isTrusted()
        let registered = hotKeyRegistered ?? HotKeyManager.shared.isRegistered
        let readiness = MenuBarReadiness.status(
            accessibilityTrusted: trusted,
            hotKeyRegistered: registered
        )
        statusMenuItem.title = MenuBarReadiness.statusMenuTitle(for: readiness)
        statusItem?.button?.toolTip = MenuBarReadiness.tooltip(
            accessibilityTrusted: trusted,
            hotKeyRegistered: registered
        )
        statusItem?.button?.image?.accessibilityDescription = statusMenuItem.title
    }

    @objc private func showGrid() {
        PanelCoordinator.shared.togglePanels()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
