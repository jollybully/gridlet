import AppKit

/// Text/state rules for the strip, kept pure so they can be tested without a window server.
enum SpaceStripModel {
    struct Chip: Equatable {
        let index: Int
        let countText: String
        let isCurrent: Bool
        let isEnabled: Bool
        let accessibilityLabel: String
    }

    static func chip(for space: ManagedSpace) -> Chip {
        Chip(
            index: space.index,
            countText: space.windowCount.map { "● \($0)" } ?? "",
            isCurrent: space.isCurrent,
            // Sending a window to the Space it is already on is a no-op, not an error,
            // so the chip reads as inactive rather than clickable.
            isEnabled: !space.isCurrent,
            accessibilityLabel: accessibilityLabel(for: space)
        )
    }

    static func accessibilityLabel(for space: ManagedSpace) -> String {
        let count = space.windowCount.map { ", \($0) window\($0 == 1 ? "" : "s")" } ?? ""
        let current = space.isCurrent ? ", current Space" : ""
        return "Space \(space.index)\(count)\(current)"
    }

    static func chips(for spaces: [ManagedSpace]) -> [Chip] {
        spaces.map(chip(for:))
    }

    static func sendMessage(appName: String, spaceIndex: Int) -> String {
        "\(appName) → Space \(spaceIndex)"
    }

    static func errorMessage(spaceIndex: Int) -> String {
        "Couldn't move that window to Space \(spaceIndex)."
    }
}

/// Horizontal row of Space buttons that lives between the panel header and the grid.
@MainActor
final class SpaceStripView: NSView {
    /// Called when a chip is clicked. `follow` is true when the click carried ⌥.
    var onSelect: ((ManagedSpace, Bool) -> Void)?

    private let stack = NSStackView()
    private var chips: [SpaceChipView] = []
    private(set) var spaces: [ManagedSpace] = []

    var chipCount: Int { chips.count }
    var isCurrentHighlightedOnly: Bool { chips.allSatisfy { !$0.chip.isEnabled } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("gridlet-space-strip")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(spaces: [ManagedSpace]) {
        self.spaces = spaces
        for chip in chips { stack.removeArrangedSubview(chip); chip.removeFromSuperview() }
        chips = spaces.map { space in
            let chip = SpaceChipView(space: space)
            chip.onActivate = { [weak self] space, follow in
                self?.onSelect?(space, follow)
            }
            return chip
        }
        for chip in chips { stack.addArrangedSubview(chip) }
        setAccessibilityLabel("\(spaces.count) Space\(spaces.count == 1 ? "" : "s")")
        needsLayout = true
    }

    func chipFrames() -> [NSRect] {
        chips.map { $0.convert($0.bounds, to: self) }
    }

    func chipProtocolNames() -> [String] { chips.map { $0.chip.accessibilityLabel } }
}

/// One Space button: number, live window count, dashed when it's the current Space.
@MainActor
final class SpaceChipView: NSControl {
    let space: ManagedSpace
    let chip: SpaceStripModel.Chip
    /// Click handler; the Bool is "option was held" (send and follow).
    var onActivate: ((ManagedSpace, Bool) -> Void)?

    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    static let height: CGFloat = 30
    static let cornerRadius: CGFloat = 8

    init(space: ManagedSpace) {
        self.space = space
        self.chip = SpaceStripModel.chip(for: space)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(chip.accessibilityLabel)
        setAccessibilityEnabled(chip.isEnabled)
        toolTip = chip.isEnabled
            ? "Send the focused window to Space \(chip.index) — hold ⌥ to follow it there"
            : "This is the current Space"
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard chip.isEnabled else { return }
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard chip.isEnabled else { return }
        // Deliberately a click, not a drag: the grid owns every drag gesture.
        isHovered = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isHovered = false
            needsDisplay = true
        }
        guard chip.isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside else { return }
        onActivate?(space, event.modifierFlags.contains(.option))
    }

    override var mouseDownCanMoveWindow: Bool { false }

    var hoverFillForTesting: NSColor { hoverFill() }
    var idleFillForTesting: NSColor { idleFill() }

    private func idleFill() -> NSColor {
        chip.isCurrent ? NSColor.labelColor.withAlphaComponent(0.05) : NSColor.labelColor.withAlphaComponent(0.13)
    }

    private func hoverFill() -> NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)

        (isHovered && chip.isEnabled ? hoverFill() : idleFill()).setFill()
        path.fill()

        let borderColor: NSColor = chip.isCurrent
            ? NSColor.labelColor.withAlphaComponent(0.32)
            : NSColor.labelColor.withAlphaComponent(0.22)
        borderColor.setStroke()
        path.lineWidth = 0.75
        if chip.isCurrent {
            path.setLineDash([3, 3], count: 2, phase: 0)
        }
        path.stroke()
        path.setLineDash([], count: 0, phase: 0)

        let numberColor: NSColor = chip.isCurrent
            ? NSColor.labelColor.withAlphaComponent(0.45)
            : (isHovered ? .white : NSColor.labelColor.withAlphaComponent(0.88))
        let countColor: NSColor = chip.isCurrent
            ? NSColor.labelColor.withAlphaComponent(0.35)
            : NSColor.labelColor.withAlphaComponent(0.50)

        let number = NSAttributedString(string: "\(chip.index)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: numberColor,
        ])
        let numberSize = number.size()
        var numberOrigin = NSPoint(x: rect.midX - numberSize.width / 2, y: rect.midY - numberSize.height / 2)
        if !chip.countText.isEmpty {
            numberOrigin.x -= 21
        }
        number.draw(at: numberOrigin)

        guard !chip.countText.isEmpty else { return }
        let count = NSAttributedString(string: chip.countText, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: countColor,
        ])
        let countSize = count.size()
        count.draw(at: NSPoint(
            x: numberOrigin.x + numberSize.width + 5,
            y: rect.midY - countSize.height / 2 + 0.5
        ))
    }
}
