import AppKit

final class GridPanelWindow: NSPanel {
    init(size: NSSize = PanelMetrics.referencePanelSize) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Gridlet"
        titleVisibility = .hidden
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isMovable = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        lockSize(size)
    }

    /// The panel is never user-resized; its size comes from the display's aspect.
    func lockSize(_ size: NSSize) {
        contentMinSize = size
        contentMaxSize = size
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PanelDisplayMode: Equatable {
    case live
    case uiSmoke
    case snapshotIdle
    case snapshotSelected
    case snapshotNoTarget
    case snapshotError
}

@MainActor
final class GridPanelController: NSWindowController, GridViewDelegate, NSWindowDelegate {
    let screen: NSScreen
    weak var coordinator: PanelCoordinator?

    let gridView = GridView()
    let spaceStrip = SpaceStripView()
    private let chromeView = PanelChromeView()
    private let closeButton = NSButton()
    private let settingsButton = NSButton()
    private let targetHeaderView = TargetAppHeaderView()
    var targetHeaderForTests: TargetAppHeaderView { targetHeaderView }
    private let errorLabel = NSTextField(labelWithString: "")
    private let footerHint = NSTextField(labelWithString: "Drag to resize")
    private let footerDetail = NSTextField(labelWithString: "")
    private let footerGridSize = NSTextField(labelWithString: "8×8")
    private var displayMode: PanelDisplayMode = .live
    private var footerNoTarget = false
    private var gridHeightConstraint: NSLayoutConstraint?
    private var stripHeightConstraint: NSLayoutConstraint?

    init(screen: NSScreen) {
        self.screen = screen
        super.init(window: GridPanelWindow(size: PanelMetrics.panelSize(for: screen)))
        window?.delegate = self
        setupUI()
        updatePanelGeometry(for: screen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        chromeView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(chromeView)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.image?.isTemplate = true
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePanel)

        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.image?.isTemplate = true
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.cell?.truncatesLastVisibleLine = true
        errorLabel.cell?.wraps = true
        errorLabel.preferredMaxLayoutWidth = PanelMetrics.width - PanelMetrics.padding * 2 // refined per screen in updatePanelGeometry
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        footerHint.font = .systemFont(ofSize: 11)
        footerHint.textColor = .secondaryLabelColor
        footerDetail.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        footerDetail.textColor = .labelColor
        footerGridSize.font = .systemFont(ofSize: 11)
        footerGridSize.textColor = .tertiaryLabelColor
        footerGridSize.alignment = .right

        gridView.delegate = self
        gridView.translatesAutoresizingMaskIntoConstraints = false

        spaceStrip.onSelect = { [weak self] space, follow in
            guard let self else { return }
            self.coordinator?.send(windowTo: space, on: self.screen, follow: follow)
        }

        for v in [closeButton, settingsButton, targetHeaderView, errorLabel, spaceStrip, gridView,
                  footerHint, footerDetail, footerGridSize] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            chromeView.addSubview(v)
        }

        let pad = PanelMetrics.padding
        let heightConstraint = gridView.heightAnchor.constraint(
            equalToConstant: PanelMetrics.gridHeight(for: screen)
        )
        gridHeightConstraint = heightConstraint
        let stripConstraint = spaceStrip.heightAnchor.constraint(
            equalToConstant: SpaceBridge.isAvailable ? PanelMetrics.spaceStripHeight : 0
        )
        stripHeightConstraint = stripConstraint
        NSLayoutConstraint.activate([
            chromeView.topAnchor.constraint(equalTo: content.topAnchor),
            chromeView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chromeView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: pad - 4),
            closeButton.topAnchor.constraint(equalTo: chromeView.topAnchor, constant: pad - 2),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            settingsButton.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -(pad - 4)),
            settingsButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 28),
            settingsButton.heightAnchor.constraint(equalToConstant: 28),

            targetHeaderView.centerXAnchor.constraint(equalTo: chromeView.centerXAnchor),
            targetHeaderView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            targetHeaderView.leadingAnchor.constraint(
                greaterThanOrEqualTo: closeButton.trailingAnchor,
                constant: PanelMetrics.headerSideMargin
            ),
            targetHeaderView.trailingAnchor.constraint(
                lessThanOrEqualTo: settingsButton.leadingAnchor,
                constant: -PanelMetrics.headerSideMargin
            ),

            errorLabel.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: pad),
            errorLabel.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -pad),
            errorLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            errorLabel.heightAnchor.constraint(lessThanOrEqualToConstant: PanelMetrics.errorAreaHeight),

            gridView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: pad),
            gridView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -pad),
            spaceStrip.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: pad),
            spaceStrip.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -pad),
            spaceStrip.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 8),
            stripConstraint,
            gridView.topAnchor.constraint(equalTo: spaceStrip.bottomAnchor, constant: 8),
            heightConstraint,

            footerHint.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: pad),
            footerHint.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor, constant: -pad),
            footerDetail.leadingAnchor.constraint(equalTo: footerHint.trailingAnchor, constant: 8),
            footerDetail.centerYAnchor.constraint(equalTo: footerHint.centerYAnchor),
            footerGridSize.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -pad),
            footerGridSize.centerYAnchor.constraint(equalTo: footerHint.centerYAnchor),
        ])
    }

    func configure(
        settings: GridSettings.Snapshot,
        target: WindowTarget?,
        displayMode: PanelDisplayMode,
        errorMessage: String? = nil
    ) {
        self.displayMode = displayMode
        refreshSpaces()
        footerNoTarget = displayMode == .snapshotNoTarget || (displayMode == .live && target == nil)
        gridView.rows = settings.rows
        gridView.columns = settings.columns
        footerGridSize.stringValue = "\(settings.rows)×\(settings.columns)"
        gridView.resetSelection()

        switch displayMode {
        case .uiSmoke, .snapshotIdle:
            applyHeaderMetadata(TargetAppHeaderPresets.safari)
            showError(nil)
            updateFooter(selection: nil, rows: settings.rows, columns: settings.columns)
        case .snapshotSelected:
            applyHeaderMetadata(TargetAppHeaderPresets.safari)
            showError(nil)
            applySnapshotSelection(rows: settings.rows, columns: settings.columns)
        case .snapshotNoTarget:
            applyHeaderMetadata(TargetAppHeaderPresets.noWindow)
            showError(nil)
            updateFooter(selection: nil, rows: settings.rows, columns: settings.columns)
        case .snapshotError:
            applyHeaderMetadata(TargetAppHeaderPresets.safari)
            showError("Couldn’t resize this window. Try again.")
            updateFooter(selection: nil, rows: settings.rows, columns: settings.columns)
        case .live:
            if let target {
                applyHeaderMetadata(TargetAppHeaderMetadata(
                    title: WindowTargetResolver.appDisplayName(for: target),
                    image: WindowTargetResolver.appIcon(for: target)
                        ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                ))
            } else {
                applyHeaderMetadata(TargetAppHeaderPresets.noWindow)
            }
            showError(errorMessage)
            updateFooter(selection: nil, rows: settings.rows, columns: settings.columns)
        }

        switch displayMode {
        case .uiSmoke, .snapshotIdle:
            footerHint.stringValue = "UI preview"
            footerHint.isHidden = false
            footerDetail.isHidden = true
        case .snapshotSelected:
            footerHint.stringValue = "UI preview"
        default:
            footerHint.stringValue = noTargetFooterHint(displayMode: displayMode, target: target)
        }
    }

    private func noTargetFooterHint(displayMode: PanelDisplayMode, target: WindowTarget?) -> String {
        if displayMode == .snapshotNoTarget { return "Select a window first" }
        if displayMode == .live && target == nil { return "Select a window first" }
        return "Drag to resize"
    }

    private func applySnapshotSelection(rows: Int, columns: Int) {
        let sel = GridSelection(rowStart: 1, rowEnd: 4, colStart: 2, colEnd: 5)
        gridView.simulateSelectionForSnapshot(sel)
        updateFooter(selection: sel, rows: rows, columns: columns)
    }

    private func updateFooter(selection: GridSelection?, rows: Int, columns: Int) {
        if footerNoTarget {
            footerDetail.stringValue = ""
            footerDetail.isHidden = true
            footerHint.isHidden = false
            footerHint.stringValue = "Select a window first"
            return
        }
        if let selection {
            let rowSpan = selection.rowEnd - selection.rowStart + 1
            let colSpan = selection.colEnd - selection.colStart + 1
            let pctW = Int((Double(colSpan) / Double(columns) * 100).rounded())
            let pctH = Int((Double(rowSpan) / Double(rows) * 100).rounded())
            footerDetail.stringValue = "\(pctW)% × \(pctH)%"
            footerHint.isHidden = true
            footerDetail.isHidden = false
        } else {
            footerDetail.stringValue = ""
            footerDetail.isHidden = true
            footerHint.isHidden = false
        }
    }

    func showError(_ message: String?) {
        if let message {
            errorLabel.stringValue = userFacingError(message)
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }
    }

    private func userFacingError(_ raw: String) -> String {
        if raw.count > 80 {
            return "Couldn’t resize this window. Try again."
        }
        return raw
    }

    /// Panel stays Divvy-small; the grid inside takes the display's aspect ratio so
    /// a selection maps proportionally onto the screen. Recomputed on every show,
    /// because visibleFrame changes with Dock/menu-bar settings without a screen change.
    func updatePanelGeometry(for screen: NSScreen) {
        let hasStrip = hasSpaceStrip
        let size = PanelMetrics.panelSize(for: screen, hasSpaceStrip: hasStrip)
        gridHeightConstraint?.constant = PanelMetrics.gridHeight(for: screen)
        stripHeightConstraint?.constant = hasStrip ? PanelMetrics.spaceStripHeight : 0
        spaceStrip.isHidden = !hasStrip
        (window as? GridPanelWindow)?.lockSize(size)
        errorLabel.preferredMaxLayoutWidth = size.width - PanelMetrics.padding * 2
        window?.setContentSize(size)
        window?.layoutIfNeeded()
    }


    /// The strip is only useful when the private Spaces API answered and this display
    /// actually has managed Spaces; otherwise the panel keeps its old shape.
    var hasSpaceStrip: Bool {
        SpaceBridge.isAvailable && !spaceStrip.spaces.isEmpty
    }

    func refreshSpaces() {
        let spaces = SpaceBridge.isAvailable ? SpaceBridge.spaces(for: screen) : []
        spaceStrip.configure(spaces: spaces)
        updatePanelGeometry(for: screen)
    }

    /// Test hook.
    var spaceStripForTesting: SpaceStripView { spaceStrip }

    func showPanel() {
        guard let window else { return }
        updatePanelGeometry(for: screen)
        let vf = screen.visibleFrame
        let size = PanelMetrics.panelSize(for: screen)
        let origin = NSPoint(
            x: vf.midX - size.width / 2,
            y: vf.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        window.orderFrontRegardless()
        window.makeKey()
        if displayMode != .snapshotSelected {
            gridView.prepareForPanelPresentation()
        }
        gridView.window?.makeFirstResponder(gridView)
    }

    func dismiss() {
        gridView.resetSelection()
        window?.orderOut(nil)
        coordinator?.overlay(for: screen)?.clear()
    }

    @objc private func closePanel() {
        coordinator?.dismissAll(reason: .closeButton)
    }

    @objc private func openSettings() {
        coordinator?.openSettings()
    }

    func gridViewSelectionChanged(_ selection: GridSelection?, rows: Int, columns: Int) {
        updateFooter(selection: selection, rows: rows, columns: columns)
        coordinator?.updatePreview(on: screen, selection: selection, rows: rows, columns: columns)
    }

    func gridViewCommitted(_ selection: GridSelection, rows: Int, columns: Int) {
        coordinator?.applySelection(on: screen, selection: selection, gridRows: rows, gridColumns: columns)
    }

    func gridViewCancelled() {
        coordinator?.cancelActiveSelection()
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.dismissAll(reason: .closeButton)
    }

    func applyHeaderMetadata(_ metadata: TargetAppHeaderMetadata) {
        targetHeaderView.apply(metadata)
    }

    /// Fixed width under stress labels (tests / snapshots).
    func layoutForWidthCheck() {
        applyHeaderMetadata(TargetAppHeaderMetadata(
            title: String(repeating: "W", count: 200),
            symbolName: "app"
        ))
        errorLabel.stringValue = String(repeating: "E", count: 400)
        errorLabel.isHidden = false
        window?.setContentSize(PanelMetrics.panelSize(for: screen))
        window?.layoutIfNeeded()
    }

    func prepareHeaderAlignmentProbe(metadata: TargetAppHeaderMetadata) {
        configure(settings: GridSettings.Snapshot(), target: nil, displayMode: .snapshotIdle)
        applyHeaderMetadata(metadata)
        showError(nil)
        window?.setContentSize(PanelMetrics.panelSize(for: screen))
        window?.layoutIfNeeded()
        chromeView.layoutSubtreeIfNeeded()
    }

    func headerAlignmentSnapshot(scenario: String) -> PanelHeaderAlignmentSnapshot {
        let chromeBounds = chromeView.bounds
        let panelMidX = Double(chromeBounds.midX)
        targetHeaderView.layoutSubtreeIfNeeded()
        let iconLocal = targetHeaderView.iconContainer.frame
        let titleLocal = targetHeaderView.titleLabel.frame
        let groupLocal = targetHeaderView.bounds
        let groupFrame = rectInChrome(local: groupLocal, from: targetHeaderView, to: chromeView)
        let iconFrame = rectInChrome(local: iconLocal, from: targetHeaderView, to: chromeView)
        let titleFrame = rectInChrome(local: titleLocal, from: targetHeaderView, to: chromeView)
        let closeFrame = closeButton.convert(closeButton.bounds, to: chromeView)
        let settingsFrame = settingsButton.convert(settingsButton.bounds, to: chromeView)
        let gapLocal = targetHeaderView.titleGapView.frame
        let gap = Double(gapLocal.width)
        return PanelHeaderAlignmentSnapshot(
            scenario: scenario,
            panelSize: .init(chromeBounds),
            panelMidX: panelMidX,
            group: .init(groupFrame),
            icon: .init(iconFrame),
            title: .init(titleFrame),
            close: .init(closeFrame),
            settings: .init(settingsFrame),
            centerDelta: Double(groupFrame.midX) - panelMidX,
            iconTitleGap: gap,
            headerCenterY: Double(closeButton.convert(closeButton.bounds, to: chromeView).midY)
        )
    }

    private func rectInChrome(local: NSRect, from view: NSView, to chrome: NSView) -> NSRect {
        let origin = view.convert(NSPoint(x: local.minX, y: local.minY), to: chrome)
        return NSRect(x: origin.x, y: origin.y, width: local.width, height: local.height)
    }
}

enum DismissReason {
    case escape, clickOutside, closeButton, applied, monitorChange
}

@MainActor
final class PanelCoordinator: NSObject {
    static let shared = PanelCoordinator()

    private var panels: [NSScreen: GridPanelController] = [:]
    private var overlays: [NSScreen: PreviewOverlayWindow] = [:]
    private(set) var capturedTarget: WindowTarget?
    private(set) var settings: GridSettings.Snapshot = GridSettings.load()
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var dismissLocalMonitor: Any?
    private var dismissGlobalMonitor: Any?
    private(set) var panelsAreVisible = false
    var uiSmokeMode = false
    var snapshotDisplayMode: PanelDisplayMode?

    private override init() {
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            let bid = app.bundleIdentifier
            Task { @MainActor in self?.handleAppActivation(pid: pid, bundleID: bid) }
        }
    }

    func reloadSettings() {
        settings = GridSettings.load()
        for (_, panel) in panels {
            panel.gridView.rows = settings.rows
            panel.gridView.columns = settings.columns
        }
    }

    func togglePanels() {
        if panels.values.contains(where: { $0.window?.isVisible == true }) {
            dismissAll(reason: .clickOutside)
        } else {
            presentPanels()
        }
    }

    func presentPanels() {
        if !uiSmokeMode && snapshotDisplayMode == nil {
            guard WindowTargetResolver.isTrusted() else {
                PermissionWindowController.shared.show()
                return
            }
            capturedTarget = captureTarget()
        } else {
            capturedTarget = nil
        }

        rebuildPanelsIfNeeded()
        let mode = resolvedDisplayMode()
        for (_, panel) in panels {
            panel.configure(settings: settings, target: capturedTarget, displayMode: mode)
            panel.showPanel()
        }
        for overlay in overlays.values {
            overlay.orderFrontRegardless()
        }
        panelsAreVisible = true
        installDismissMonitors()
    }

    private func resolvedDisplayMode() -> PanelDisplayMode {
        if let snapshotDisplayMode { return snapshotDisplayMode }
        if uiSmokeMode { return .uiSmoke }
        return .live
    }

    private func captureTarget() -> WindowTarget? {
        if let t = WindowTargetResolver.captureFrontmostTarget(excludingGridlet: true) {
            return t
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            if let prev = PreviousAppTracker.shared.previousBundlePID {
                return WindowTargetResolver.target(pid: prev)
            }
        }
        return nil
    }

    func cancelActiveSelection() {
        dismissAll(reason: .escape)
    }

    func dismissAll(reason: DismissReason) {
        panelsAreVisible = false
        removeDismissMonitors()
        for panel in panels.values { panel.dismiss() }
        for overlay in overlays.values { overlay.clear(); overlay.orderOut(nil) }
    }

    private func panelWindows() -> [NSWindow] {
        panels.values.compactMap(\.window)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        let windows = panelWindows()

        dismissLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.panelsAreVisible else { return event }
            if let win = event.window, windows.contains(win) {
                return event
            }
            self.dismissAll(reason: .clickOutside)
            return event
        }

        dismissGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.panelsAreVisible else { return }
            let mouse = NSEvent.mouseLocation
            let hitPanel = self.panels.values.contains { panel in
                guard let frame = panel.window?.frame else { return false }
                return frame.contains(mouse)
            }
            if !hitPanel {
                self.dismissAll(reason: .clickOutside)
            }
        }
    }

    private func removeDismissMonitors() {
        if let dismissLocalMonitor {
            NSEvent.removeMonitor(dismissLocalMonitor)
            self.dismissLocalMonitor = nil
        }
        if let dismissGlobalMonitor {
            NSEvent.removeMonitor(dismissGlobalMonitor)
            self.dismissGlobalMonitor = nil
        }
    }

    func overlay(for screen: NSScreen) -> PreviewOverlayWindow? {
        overlays[screen]
    }

    func firstPanelWindow() -> NSWindow? {
        panels.values.compactMap(\.window).first
    }

    func firstPanelController() -> GridPanelController? {
        panels.values.first
    }

    func updatePreview(on screen: NSScreen, selection: GridSelection?, rows: Int, columns: Int) {
        guard settings.showPreview else {
            overlays[screen]?.clear()
            return
        }
        guard let selection else {
            overlays[screen]?.clear()
            return
        }
        let vf = screen.visibleFrame
        guard let cocoa = ScreenGeometry.cocoaFrame(for: selection, rows: rows, columns: columns, visibleFrame: vf) else {
            overlays[screen]?.clear()
            return
        }
        overlays[screen]?.updatePreview(cocoaRect: cocoa, on: screen)
    }

    func applySelection(
        on screen: NSScreen,
        selection: GridSelection,
        gridRows: Int,
        gridColumns: Int
    ) {
        let vf = screen.visibleFrame
        let primaryTop = ScreenGeometry.primaryTopY(screens: NSScreen.screens)

        guard let cocoa = ScreenGeometry.cocoaFrame(for: selection, rows: gridRows, columns: gridColumns, visibleFrame: vf) else { return }
        let axFrame = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTop)

        if uiSmokeMode || snapshotDisplayMode != nil {
            dismissAll(reason: .applied)
            return
        }

        guard let target = capturedTarget, WindowTargetResolver.isStillValid(target) else {
            panels[screen]?.showError(WindowTargetError.stale.errorDescription ?? "No target window")
            return
        }

        do {
            try WindowTargetResolver.applyFrame(target, axFrame: axFrame)
        } catch {
            panels[screen]?.showError(error.localizedDescription)
            if let ax = WindowTargetResolver.readBackAXFrame(target) {
                let readCocoa = ScreenGeometry.axRectToCocoa(ax, primaryTopY: primaryTop)
                NSLog("Gridlet readback cocoa frame: \(readCocoa)")
            }
            return
        }

        if settings.keepPanelOpen {
            for (_, panel) in panels {
                panel.configure(settings: settings, target: capturedTarget, displayMode: .live)
                panel.gridView.prepareForPanelPresentation()
            }
            for overlay in overlays.values { overlay.clear() }
        } else {
            dismissAll(reason: .applied)
        }
    }


    /// Sends the captured window to another Space, keeping its frame. The Space axis is
    /// a click; the grid keeps every drag gesture to itself.
    func send(windowTo space: ManagedSpace, on screen: NSScreen, follow: Bool) {
        // Same dismissal contract as a resize commit: the panel always goes away.
        defer { dismissAll(reason: .applied) }

        if uiSmokeMode || snapshotDisplayMode != nil { return }

        guard let target = capturedTarget, WindowTargetResolver.isStillValid(target) else {
            panels[screen]?.showError(WindowTargetError.stale.errorDescription ?? "No target window")
            return
        }
        guard !space.isCurrent else { return } // already there: no-op, not an error

        guard SpaceBridge.isAvailable, let windowID = SpaceBridge.windowID(for: target) else {
            panels[screen]?.showError("This build can't move windows between Spaces.")
            return
        }

        let origin = SpaceBridge.spaceID(forWindow: windowID)
        guard SpaceBridge.move(window: windowID, to: space.id) else {
            panels[screen]?.showError(SpaceStripModel.errorMessage(spaceIndex: space.index))
            return
        }

        if follow, let displayIdentifier = SpaceBridge.displayIdentifier(for: screen) {
            _ = SpaceBridge.switchTo(spaceID: space.id, displayIdentifier: displayIdentifier)
        }

        let appName = WindowTargetResolver.appDisplayName(for: target)
        let canUndo = origin != nil
        SendToastController.shared.present(
            SpaceStripModel.sendMessage(appName: appName, spaceIndex: space.index),
            on: screen,
            undo: canUndo ? {
                _ = SpaceBridge.move(window: windowID, to: origin!)
            } : nil
        )
    }

    func openSettings() {
        dismissAll(reason: .clickOutside)
        SettingsWindowController.shared.show()
    }

    private func rebuildPanelsIfNeeded() {
        let screens = NSScreen.screens
        let screenSet = Set(screens)
        for key in panels.keys where !screenSet.contains(key) {
            panels[key]?.dismiss()
            panels.removeValue(forKey: key)
            overlays[key]?.close()
            overlays.removeValue(forKey: key)
        }
        for screen in screens {
            if panels[screen] == nil {
                let panel = GridPanelController(screen: screen)
                panel.coordinator = self
                panels[screen] = panel
            }
            if overlays[screen] == nil {
                overlays[screen] = PreviewOverlayWindow(screen: screen)
            }
        }
    }

    private func handleScreenChange() {
        if panels.values.contains(where: { $0.window?.isVisible == true }) {
            dismissAll(reason: .monitorChange)
        }
        rebuildPanelsIfNeeded()
    }

    private func handleAppActivation(pid: pid_t, bundleID: String?) {
        guard panelsAreVisible else { return }
        if bundleID == Bundle.main.bundleIdentifier { return }
        if let app = NSRunningApplication(processIdentifier: pid),
           let t = WindowTargetResolver.target(for: app) {
            capturedTarget = t
            for (_, panel) in panels {
                panel.configure(settings: settings, target: capturedTarget, displayMode: .live)
            }
        }
    }

    static func syncGridDimensions(rows: Int, columns: Int, gridViews: [GridView]) {
        for gridView in gridViews {
            gridView.rows = rows
            gridView.columns = columns
            gridView.prepareForPanelPresentation()
        }
    }
}

@MainActor
final class PreviousAppTracker: NSObject {
    static let shared = PreviousAppTracker()
    private(set) var previousBundlePID: pid_t?
    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousBundlePID = front.processIdentifier
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            let bid = app.bundleIdentifier
            Task { @MainActor in
                if bid != Bundle.main.bundleIdentifier {
                    self?.previousBundlePID = pid
                }
            }
        }
    }
}
