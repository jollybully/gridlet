import AppKit

enum PanelMetrics {
    static let padding: CGFloat = 17
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 24
    static let errorAreaHeight: CGFloat = 32
    /// Gap between header icon/title group and close/settings hit targets.
    static let headerSideMargin: CGFloat = 8
    static let headerToolbarButtonSize: CGFloat = 28

    /// Width of the grid view itself, in points. Deliberately small (Divvy-palette
    /// sized): the grid is a *symbol* for the screen, not a scaled picture of it,
    /// so proportions matter far more than area. The panel width follows from this.
    static let gridWidth: CGFloat = 280
    /// Clamps for extreme display aspects (very tall or very wide screens) so the
    /// palette never collapses or grows into a slab.
    static let minGridHeight: CGFloat = 96
    static let maxGridHeight: CGFloat = 300
    static let fallbackAspect: CGFloat = 16.0 / 9.0

    /// Chrome above the grid: top padding, header row, the error row and its gaps.
    static let chromeAboveGrid: CGFloat = 70
    /// Chrome below the grid: footer row plus bottom padding.
    static let chromeBelowGrid: CGFloat = 62

    /// Panel width. Constant — the grid takes the display's aspect, not the width.
    static var width: CGFloat { gridWidth + padding * 2 }

    /// Panel height for the main screen; per-screen sizing comes from `panelSize(for:)`.
    static var height: CGFloat { referencePanelSize.height }

    static var referenceScreen: NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    static var referencePanelSize: NSSize {
        if let screen = referenceScreen {
            return panelSize(for: screen)
        }
        return NSSize(
            width: width,
            height: chromeAboveGrid + gridWidth / fallbackAspect + chromeBelowGrid
        )
    }

    /// The grid must carry the display's aspect ratio so that a selection is a
    /// proportional slice of the screen: half the columns × half the rows is a
    /// literal half-screen rectangle, and 4×4 of an 8×8 grid is a quadrant.
    static func gridAspect(for screen: NSScreen) -> CGFloat {
        let vf = screen.visibleFrame
        guard vf.width > 0, vf.height > 0 else { return fallbackAspect }
        return vf.width / vf.height
    }

    static func gridHeight(for screen: NSScreen) -> CGFloat {
        let exact = gridWidth / gridAspect(for: screen)
        // Whole points: AppKit rounds window frames to integer points anyway, and
        // an integral grid height keeps the panel size free of sub-pixel drift.
        return min(max(exact, minGridHeight), maxGridHeight).rounded()
    }

    static let spaceStripHeight: CGFloat = 26
    static let spaceStripTopGap: CGFloat = 4

    static func stripExtra(hasSpaceStrip: Bool) -> CGFloat {
        hasSpaceStrip ? spaceStripTopGap + spaceStripHeight : 0
    }

    static func panelSize(for screen: NSScreen, hasSpaceStrip: Bool = false) -> NSSize {
        NSSize(
            width: width,
            height: chromeAboveGrid + gridHeight(for: screen) + chromeBelowGrid + stripExtra(hasSpaceStrip: hasSpaceStrip)
        )
    }

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
