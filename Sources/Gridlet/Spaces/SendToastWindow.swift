import AppKit

/// Brief confirmation after a window is sent to another Space, with a one-click Undo.
///
/// A window that vanishes from the current Space with no acknowledgement reads as a
/// bug, so the toast is part of the feature rather than decoration.
@MainActor
final class SendToastController {
    static let shared = SendToastController()

    static let defaultDuration: TimeInterval = 1.2

    private var window: SendToastWindow?

    private init() {}

    func present(
        _ message: String,
        on screen: NSScreen,
        duration: TimeInterval = SendToastController.defaultDuration,
        undo: (() -> Void)? = nil
    ) {
        dismiss()
        let toast = SendToastWindow()
        window = toast
        toast.present(message: message, on: screen, duration: duration, undo: undo)
    }

    func dismiss() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    /// Test hook: text currently on screen (nil when no toast is up).
    var visibleMessageForTesting: String? {
        window?.messageForTesting
    }
}

final class SendToastWindow: NSPanel {
    private let messageLabel = NSTextField(labelWithString: "")
    private let checkLabel = NSTextField(labelWithString: "✓")
    private let undoButton = NSButton()
    private var undoHandler: (() -> Void)?
    private var dismissWorkItem: DispatchWorkItem?
    private(set) var messageForTesting: String?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        checkLabel.font = .systemFont(ofSize: 13, weight: .bold)
        checkLabel.textColor = .systemGreen
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.lineBreakMode = .byTruncatingTail

        undoButton.title = "Undo"
        undoButton.isBordered = false
        undoButton.font = .systemFont(ofSize: 13, weight: .semibold)
        undoButton.contentTintColor = .controlAccentColor
        undoButton.target = self
        undoButton.action = #selector(undoTapped)

        let stack = NSStackView(views: [checkLabel, messageLabel, undoButton])
        stack.orientation = .horizontal
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        contentView = effect
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            effect.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    func present(message: String, on screen: NSScreen, duration: TimeInterval, undo: (() -> Void)?) {
        messageForTesting = message
        messageLabel.stringValue = message
        undoHandler = undo
        undoButton.isHidden = undo == nil
        contentView?.layoutSubtreeIfNeeded()

        let fitting = contentView?.fittingSize ?? NSSize(width: 240, height: 40)
        let size = NSSize(width: max(fitting.width, 160), height: 40)
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 18
        )
        // A toast must never be the thing that steals focus from the window being sent.
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in self?.finish() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    @objc private func undoTapped() {
        let handler = undoHandler
        undoHandler = nil
        finish()
        handler?()
    }

    private func finish() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        orderOut(nil)
        close()
    }
}
