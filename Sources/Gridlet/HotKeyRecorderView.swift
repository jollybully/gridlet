import AppKit

/// Native control for recording the global “open Gridlet” shortcut.
final class HotKeyRecorderView: NSControl {
    var binding: HotKeyBinding = .defaultShowPanel {
        didSet { needsDisplay = true }
    }
    var onRecorded: ((HotKeyBinding) -> Void)?
    private var monitor: Any?

    var isRecording: Bool { monitor != nil }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor.controlBackgroundColor
        let border = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        bg.setFill()
        path.fill()
        border.withAlphaComponent(isRecording ? 0.9 : 0.55).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Press shortcut… (Esc to cancel)"
        } else {
            text = binding.displayString
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: max(10, (bounds.width - size.width) / 2),
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            if ev.keyCode == 53 {
                self.endRecording()
                return nil
            }
            let mods = ev.modifierFlags.carbonFlags
            guard mods != 0 || ev.keyCode == 49 else { return ev }
            let new = HotKeyBinding(keyCode: UInt32(ev.keyCode), modifiers: mods)
            guard new.isValidGlobal else { return ev }
            self.binding = new
            self.onRecorded?(new)
            self.endRecording()
            return nil
        }
        needsDisplay = true
    }

    func endRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        needsDisplay = true
    }

    private func beginRecording() {
        endRecording()
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override func accessibilityLabel() -> String? {
        if isRecording {
            return "Recording open Gridlet shortcut"
        }
        return "Open Gridlet shortcut, \(binding.displayString)"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }
}
