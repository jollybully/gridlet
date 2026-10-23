import AppKit

@MainActor
final class PermissionWindowController: NSWindowController {
    static let shared = PermissionWindowController()

    private let instructionField = NSTextField(wrappingLabelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gridlet"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        setup()
        StandardWindowLayout.hideUtilityZoomAndMiniaturize(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Test hook: root content view (no nested panel chrome).
    var contentRootForTests: NSView? { window?.contentView }

    private func setup() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = false

        let title = NSTextField(labelWithString: "Allow window control")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString:
            "Gridlet needs Accessibility access to move and resize other apps’ windows.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 352

        instructionField.stringValue = "Enable Gridlet, then quit and reopen the app."
        instructionField.font = .systemFont(ofSize: 12)
        instructionField.textColor = .secondaryLabelColor
        instructionField.preferredMaxLayoutWidth = 352

        let openButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"

        let quitButton = NSButton(title: "Quit Gridlet", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded

        for v in [title, body, instructionField, openButton, quitButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        let pad = StandardWindowMetrics.contentPadding
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            instructionField.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 14),
            instructionField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            instructionField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),

            openButton.topAnchor.constraint(equalTo: instructionField.bottomAnchor, constant: 22),
            openButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),

            quitButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            quitButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 12),

            quitButton.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -pad),
            openButton.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -pad),
        ])
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
