import AppKit

/// Space chips in the panel. Chips do not take mouse events: the strip
/// hit-tests and fires the action. A click on the current space does nothing.
final class SpaceStripView: NSView {
    var onActivate: ((SpaceChip, Bool) -> Void)?

    private(set) var chips: [SpaceChip] = []
    private var chipViews: [SpaceChipView] = []
    private var hoverIndex: Int?
    private var tracking: NSTrackingArea?

    var hasChips: Bool { !chips.isEmpty }

    func setChips(_ chips: [SpaceChip]) {
        self.chips = chips
        hoverIndex = nil
        rebuild()
    }

    func chipIndex(at point: NSPoint) -> Int? {
        chipViews.firstIndex { $0.frame.contains(point) }
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), chipIndex(at: local) != nil else { return nil }
        return self
    }

    private func rebuild() {
        chipViews.forEach { $0.removeFromSuperview() }
        chipViews = chips.map { chip in
            let view = SpaceChipView()
            view.configure(chip)
            return view
        }
        chipViews.forEach { addSubview($0) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("gridlet-space-strip")
        setAccessibilityLabel("Spaces")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let count = chipViews.count
        guard count > 0 else { return }
        let gap: CGFloat = 4
        let width = max(0, (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count))
        for (index, view) in chipViews.enumerated() {
            view.frame = NSRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
            view.isHovered = hoverIndex == index
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        tracking = area
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        chipViews.forEach { $0.isHovered = false }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let index = chipIndex(at: local), chips.indices.contains(index) else { return }
        let chip = chips[index]
        guard !chip.isCurrent else { return }
        let follow = event.modifierFlags.contains(.option)
        onActivate?(chip, follow)
    }

    private func updateHover(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let next = chipIndex(at: local)
        guard next != hoverIndex else { return }
        hoverIndex = next
        for (index, view) in chipViews.enumerated() {
            view.isHovered = index == next
        }
    }
}

final class SpaceChipView: NSView {
    private var indexText = ""
    private var isCurrent = false
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ chip: SpaceChip) {
        indexText = String(chip.index)
        isCurrent = chip.isCurrent
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(chip.isCurrent ? "Space \(chip.index), current" : "Space \(chip.index)")
        toolTip = chip.isCurrent ? "Already on this Space" : "Send window to Space \(chip.index)"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        if isCurrent {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 1
            let dashes: [CGFloat] = [2, 2]
            path.setLineDash(dashes, count: 2, phase: 0)
            path.stroke()
        } else {
            let fill = isHovered
                ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                : NSColor.labelColor.withAlphaComponent(0.12)
            fill.setFill()
            path.fill()
        }
        let text = NSAttributedString(string: indexText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(isCurrent ? 0.5 : 0.92),
        ])
        let size = text.size()
        text.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ))
    }
}
