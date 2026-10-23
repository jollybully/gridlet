import AppKit

enum StandardWindowMetrics {
    static let contentPadding: CGFloat = 24
}

enum StandardWindowLayout {
    /// Topmost in-window view (includes title bar chrome for titled windows).
    @MainActor
    static func snapshotRoot(for window: NSWindow) -> NSView? {
        var view: NSView? = window.contentView
        while let superview = view?.superview, superview.window == window {
            view = superview
        }
        return view
    }

    @MainActor
    static func containsPanelChrome(in root: NSView) -> Bool {
        if root is PanelChromeView { return true }
        for sub in root.subviews where containsPanelChrome(in: sub) {
            return true
        }
        return false
    }

    @MainActor
    static func hideUtilityZoomAndMiniaturize(in window: NSWindow) {
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
