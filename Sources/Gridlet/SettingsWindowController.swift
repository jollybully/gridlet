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
    private let closeAfterResizeCheckbox = NSButton(checkboxWithTitle: "Close after resizing", target: nil, action: nil)
    private let previewCheckbox = NSButton(checkboxWithTitle: "Show resize preview", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch Gridlet at login", target: nil, action: nil)
    private let axStatus = NSTextField(labelWithString: "")

    private init() {
        settings = GridSettings.load()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
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

        for v in [hotkeyTitle, hotkeyRecorder, hotkeyStatus, gridTitle, rowsLabel, rowsValue, rowsStepper, colsLabel, colsValue, colsStepper,
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

            rowsLabel.topAnchor.constraint(equalTo: gridTitle.bottomAnchor, constant: 14),
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

            closeAfterResizeCheckbox.topAnchor.constraint(equalTo: rowsLabel.bottomAnchor, constant: 18),
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
        rowsStepper.integerValue = settings.rows
        colsStepper.integerValue = settings.columns
        rowsValue.stringValue = "\(settings.rows)"
        colsValue.stringValue = "\(settings.columns)"
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

    @objc private func stepperChanged() {
        settings.rows = GridSettings.clampGrid(rowsStepper.integerValue)
        settings.columns = GridSettings.clampGrid(colsStepper.integerValue)
        rowsValue.stringValue = "\(settings.rows)"
        colsValue.stringValue = "\(settings.columns)"
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
