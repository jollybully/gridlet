import AppKit

enum PanelMetrics {
    static let width: CGFloat = 320
    static let height: CGFloat = 380
    static let padding: CGFloat = 17
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 24
    static let errorAreaHeight: CGFloat = 32
    /// Gap between header icon/title group and close/settings hit targets.
    static let headerSideMargin: CGFloat = 8
    static let headerToolbarButtonSize: CGFloat = 28
    static var headerContentMaxWidth: CGFloat {
        let side = (padding - 4) + headerToolbarButtonSize + headerSideMargin
        return width - side * 2
    }
}

/// Rounded material backplate for the floating grid panel.
final class PanelChromeView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
