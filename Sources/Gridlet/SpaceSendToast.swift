import AppKit

/// Brief confirmation after a window leaves the current Space. Undo moves it back.
@MainActor
final class SpaceSendToast {
    static let shared = SpaceSendToast()
    /// Unit tests set this so a send does not open a panel.
    static var suppress = false

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let label = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private var undoAction: (() -> Void)?

    private init() {}

    func show(message: String, undo: @escaping () -> Void) {
        guard !Self.suppress else { return }
        undoAction = undo
        hideWork?.cancel()

        let panel = ensurePanel()
        label.stringValue = message
        undoButton.isHidden = false
        undoButton.isEnabled = true
        panel.layoutIfNeeded()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = panel.frame
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.minY + 28
            ))
        }
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let chrome = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        chrome.material = .hudWindow
        chrome.blendingMode = .behindWindow
        chrome.state = .active
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 8
        chrome.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(chrome)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        undoButton.bezelStyle = .inline
        undoButton.font = .systemFont(ofSize: 13, weight: .semibold)
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        label.translatesAutoresizingMaskIntoConstraints = false
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(label)
        chrome.addSubview(undoButton)

        guard let content = panel.contentView else { return panel }
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: content.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),
            undoButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            undoButton.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -8),
            undoButton.centerYAnchor.constraint(equalTo: chrome.centerYAnchor),
        ])
        self.panel = panel
        return panel
    }

    @objc private func undoTapped() {
        hideWork?.cancel()
        undoButton.isEnabled = false
        let action = undoAction
        undoAction = nil
        action?()
        panel?.orderOut(nil)
    }
}
