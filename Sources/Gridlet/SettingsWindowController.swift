import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var settings: GridSettings.Snapshot

    private let hotkeyTitle = NSTextField(labelWithString: "")
    private let hotkeyRecorder = HotKeyRecorderView()
    private let hotkeyStatus = NSTextField(labelWithString: "")

    private let rowsStepper = NSStepper()
    private let rowsValue = NSTextField(labelWithString: "")
    private let colsStepper = NSStepper()
    private let colsValue = NSTextField(labelWithString: "")
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let resetGridButton = NSButton(title: "Use default", target: nil, action: nil)
    private let gapStepper = NSStepper()
    private let gapValue = NSTextField(labelWithString: "")
    /// nil means the grid section is editing the default grid rather than a display override.
    private var selectedDisplayKey: String?
    private var displayChoices: [(key: String?, title: String)] = []
    private let closeAfterResizeCheckbox = NSButton(checkboxWithTitle: "Close after resizing", target: nil, action: nil)
    private let previewCheckbox = NSButton(checkboxWithTitle: "Show resize preview", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch Gridlet at login", target: nil, action: nil)
    private let axStatus = NSTextField(labelWithString: "")

    private init() {
        settings = GridSettings.load()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 404),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gridlet Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        setupUI()
        reloadFromSettings()
        StandardWindowLayout.hideUtilityZoomAndMiniaturize(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Test hook for recorder lifecycle.
    var globalHotKeyRecorder: HotKeyRecorderView { hotkeyRecorder }

    var contentRootForTests: NSView? { window?.contentView }

    func show() {
        reloadFromSettings()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        hotkeyRecorder.endRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        hotkeyRecorder.endRecording()
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = false

        hotkeyTitle.stringValue = "Open Gridlet"
        hotkeyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        hotkeyRecorder.onRecorded = { [weak self] binding in
            self?.tryUpdateHotKey(binding)
        }
        hotkeyStatus.font = .systemFont(ofSize: 11)
        hotkeyStatus.textColor = .secondaryLabelColor
        hotkeyStatus.lineBreakMode = .byWordWrapping
        hotkeyStatus.maximumNumberOfLines = 2
        hotkeyStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let gridTitle = NSTextField(labelWithString: "Grid")
        gridTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        rowsStepper.minValue = Double(GridSettings.minGrid)
        rowsStepper.maxValue = Double(GridSettings.maxGrid)
        rowsStepper.target = self
        rowsStepper.action = #selector(stepperChanged)
        colsStepper.minValue = Double(GridSettings.minGrid)
        colsStepper.maxValue = Double(GridSettings.maxGrid)
        colsStepper.target = self
        colsStepper.action = #selector(stepperChanged)

        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        displayPopup.font = .systemFont(ofSize: 12)
        resetGridButton.target = self
        resetGridButton.action = #selector(resetGrid)
        resetGridButton.bezelStyle = .inline
        resetGridButton.font = .systemFont(ofSize: 11)

        gapStepper.minValue = 0
        gapStepper.maxValue = Double(GridSettings.maxGap)
        gapStepper.increment = 2
        gapStepper.target = self
        gapStepper.action = #selector(gapChanged)
        gapValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        closeAfterResizeCheckbox.target = self
        closeAfterResizeCheckbox.action = #selector(toggleChanged)
        previewCheckbox.target = self
        previewCheckbox.action = #selector(toggleChanged)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginToggled)

        axStatus.font = .systemFont(ofSize: 11)
        axStatus.textColor = .secondaryLabelColor
        axStatus.lineBreakMode = .byWordWrapping
        axStatus.maximumNumberOfLines = 2

        let rowsLabel = NSTextField(labelWithString: "Rows")
        let colsLabel = NSTextField(labelWithString: "Columns")
        rowsValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        colsValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let axButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAX))

        let gapLabel = NSTextField(labelWithString: "Edge gap")
        for v in [hotkeyTitle, hotkeyRecorder, hotkeyStatus, gridTitle, displayPopup, resetGridButton,
                  rowsLabel, rowsValue, rowsStepper, colsLabel, colsValue, colsStepper,
                  gapLabel, gapStepper, gapValue,
                  closeAfterResizeCheckbox, previewCheckbox, loginCheckbox, axStatus, axButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        let pad = StandardWindowMetrics.contentPadding
        NSLayoutConstraint.activate([
            hotkeyTitle.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            hotkeyTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            hotkeyRecorder.topAnchor.constraint(equalTo: hotkeyTitle.bottomAnchor, constant: 8),
            hotkeyRecorder.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            hotkeyRecorder.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            hotkeyRecorder.heightAnchor.constraint(equalToConstant: 30),

            hotkeyStatus.topAnchor.constraint(equalTo: hotkeyRecorder.bottomAnchor, constant: 4),
            hotkeyStatus.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            hotkeyStatus.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            gridTitle.topAnchor.constraint(equalTo: hotkeyStatus.bottomAnchor, constant: 16),
            gridTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            displayPopup.centerYAnchor.constraint(equalTo: gridTitle.centerYAnchor),
            displayPopup.leadingAnchor.constraint(greaterThanOrEqualTo: gridTitle.trailingAnchor, constant: 10),
            resetGridButton.centerYAnchor.constraint(equalTo: displayPopup.centerYAnchor),
            resetGridButton.leadingAnchor.constraint(equalTo: displayPopup.trailingAnchor, constant: 6),
            resetGridButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            rowsLabel.topAnchor.constraint(equalTo: gridTitle.bottomAnchor, constant: 12),
            rowsLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            rowsValue.centerYAnchor.constraint(equalTo: rowsLabel.centerYAnchor),
            rowsValue.leadingAnchor.constraint(equalTo: rowsLabel.trailingAnchor, constant: 12),
            rowsValue.widthAnchor.constraint(equalToConstant: 24),
            rowsStepper.centerYAnchor.constraint(equalTo: rowsLabel.centerYAnchor),
            rowsStepper.leadingAnchor.constraint(equalTo: rowsValue.trailingAnchor, constant: 4),

            colsLabel.centerYAnchor.constraint(equalTo: rowsLabel.centerYAnchor),
            colsLabel.leadingAnchor.constraint(equalTo: rowsStepper.trailingAnchor, constant: 24),
            colsValue.centerYAnchor.constraint(equalTo: colsLabel.centerYAnchor),
            colsValue.leadingAnchor.constraint(equalTo: colsLabel.trailingAnchor, constant: 12),
            colsStepper.centerYAnchor.constraint(equalTo: colsLabel.centerYAnchor),
            colsStepper.leadingAnchor.constraint(equalTo: colsValue.trailingAnchor, constant: 4),

            gapLabel.topAnchor.constraint(equalTo: rowsLabel.bottomAnchor, constant: 12),
            gapLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            gapValue.centerYAnchor.constraint(equalTo: gapLabel.centerYAnchor),
            gapValue.leadingAnchor.constraint(equalTo: gapLabel.trailingAnchor, constant: 12),
            gapValue.widthAnchor.constraint(equalToConstant: 40),
            gapStepper.centerYAnchor.constraint(equalTo: gapLabel.centerYAnchor),
            gapStepper.leadingAnchor.constraint(equalTo: gapValue.trailingAnchor, constant: 4),

            closeAfterResizeCheckbox.topAnchor.constraint(equalTo: gapLabel.bottomAnchor, constant: 14),
            closeAfterResizeCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            previewCheckbox.topAnchor.constraint(equalTo: closeAfterResizeCheckbox.bottomAnchor, constant: 8),
            previewCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            loginCheckbox.topAnchor.constraint(equalTo: previewCheckbox.bottomAnchor, constant: 8),
            loginCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            axStatus.topAnchor.constraint(equalTo: loginCheckbox.bottomAnchor, constant: 16),
            axStatus.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            axStatus.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            axButton.topAnchor.constraint(equalTo: axStatus.bottomAnchor, constant: 8),
            axButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            axButton.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -pad),
        ])
    }

    private func reloadFromSettings() {
        settings = GridSettings.load()
        hotkeyRecorder.binding = settings.showPanelHotKey
        hotkeyStatus.stringValue = ""
        hotkeyStatus.textColor = .secondaryLabelColor
        reloadDisplayChoices()
        reloadGridControls()
        gapStepper.integerValue = settings.gap
        gapValue.stringValue = "\(settings.gap) pt"
        closeAfterResizeCheckbox.state = settings.keepPanelOpen ? .off : .on
        previewCheckbox.state = settings.showPreview ? .on : .off
        updateAXStatus()
        updateLoginFromService()
    }

    private func updateAXStatus() {
        if WindowTargetResolver.isTrusted() {
            axStatus.stringValue = "Accessibility is enabled for Gridlet."
        } else {
            axStatus.stringValue = "Accessibility is required to move other apps’ windows."
        }
    }

    private func updateLoginFromService() {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            loginCheckbox.state = .on
        case .notRegistered, .notFound:
            loginCheckbox.state = .off
        @unknown default:
            loginCheckbox.state = .off
        }
    }

    private func tryUpdateHotKey(_ binding: HotKeyBinding) {
        guard binding.isValidGlobal else {
            hotkeyStatus.stringValue = "Shortcut must include ⌃, ⌥, or ⌘."
            hotkeyStatus.textColor = .systemRed
            hotkeyRecorder.binding = settings.showPanelHotKey
            return
        }
        let previous = settings.showPanelHotKey
        settings.showPanelHotKey = binding
        persist()
        do {
            try AppDelegate.shared?.registerShowPanelHotKey()
            hotkeyStatus.stringValue = ""
            hotkeyStatus.textColor = .secondaryLabelColor
        } catch {
            settings.showPanelHotKey = previous
            persist()
            hotkeyRecorder.binding = previous
            hotkeyStatus.stringValue = "Could not register shortcut (may be in use). Kept \(previous.displayString)."
            hotkeyStatus.textColor = .systemRed
        }
    }

    /// Default grid first, then one row per display that has its own override.
    private func reloadDisplayChoices() {
        displayChoices = [(nil, "Default")]
        for screen in NSScreen.screens {
            let key = GridSettings.displayKey(for: screen)
            let name = GridSettings.isMainDisplay(screen)
                ? "Main display"
                : screen.localizedName
            let suffix = settings.hasOverride(for: key) ? " (custom)" : ""
            displayChoices.append((key, "\(name)\(suffix)"))
        }
        displayPopup.removeAllItems()
        displayPopup.addItems(withTitles: displayChoices.map(\.title))
        let selectedIndex = displayChoices.firstIndex { $0.key == selectedDisplayKey } ?? 0
        displayPopup.selectItem(at: selectedIndex)
        selectedDisplayKey = displayChoices[selectedIndex].key
        resetGridButton.isHidden = selectedDisplayKey == nil
    }

    private func reloadGridControls() {
        let grid = selectedDisplayKey.map { settings.grid(for: $0) }
            ?? GridSettings.DisplayGrid(rows: settings.rows, columns: settings.columns)
        rowsStepper.integerValue = grid.rows
        colsStepper.integerValue = grid.columns
        rowsValue.stringValue = "\(grid.rows)"
        colsValue.stringValue = "\(grid.columns)"
    }

    @objc private func displayChanged() {
        let index = displayPopup.indexOfSelectedItem
        guard displayChoices.indices.contains(index) else { return }
        selectedDisplayKey = displayChoices[index].key
        resetGridButton.isHidden = selectedDisplayKey == nil
        reloadGridControls()
    }

    @objc private func stepperChanged() {
        let rows = GridSettings.clampGrid(rowsStepper.integerValue)
        let columns = GridSettings.clampGrid(colsStepper.integerValue)
        if let key = selectedDisplayKey {
            settings.setGrid(GridSettings.DisplayGrid(rows: rows, columns: columns), for: key)
        } else {
            settings.rows = rows
            settings.columns = columns
        }
        persist()
        reloadDisplayChoices()
        reloadGridControls()
    }

    @objc private func resetGrid() {
        guard let key = selectedDisplayKey else { return }
        settings.clearOverride(for: key)
        persist()
        reloadDisplayChoices()
        reloadGridControls()
    }

    @objc private func gapChanged() {
        settings.gap = GridSettings.clampGap(gapStepper.integerValue)
        gapValue.stringValue = "\(settings.gap) pt"
        persist()
    }

    @objc private func toggleChanged() {
        settings.keepPanelOpen = closeAfterResizeCheckbox.state != .on
        settings.showPreview = previewCheckbox.state == .on
        persist()
    }

    @objc private func loginToggled() {
        let want = loginCheckbox.state == .on
        do {
            if want {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = want
            persist()
        } catch {
            axStatus.stringValue = "Could not update login item: \(error.localizedDescription)"
        }
        updateLoginFromService()
    }

    @objc private func openAX() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func persist() {
        GridSettings.save(settings)
        PanelCoordinator.shared.reloadSettings()
    }
}
