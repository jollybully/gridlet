import AppKit
import QuartzCore

final class PreviewOverlayWindow: NSWindow {
    private let fillLayer = CALayer()

    /// Layer keys whose implicit Core Animation transitions must never run.
    /// Implicit animations default to ~0.25s ease-in-out, which makes the preview
    /// trail behind the pointer and read as sluggish during a drag.
    static let nonAnimatedLayerKeys = ["position", "bounds", "hidden", "opacity"]

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hasShadow = false
        setFrame(screen.frame, display: true)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view

        // Belt-and-braces: both an empty action map and a zero-duration
        // transaction stop AppKit's implicit animations on every update.
        let animationNulls = Dictionary(
            uniqueKeysWithValues: Self.nonAnimatedLayerKeys.map { ($0, NSNull()) }
        )
        fillLayer.actions = animationNulls
        fillLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        fillLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        fillLayer.borderWidth = 1.5
        fillLayer.cornerRadius = 6
        view.layer?.addSublayer(fillLayer)
    }

    func updatePreview(cocoaRect: CGRect?, on screen: NSScreen) {
        guard let cocoaRect else {
            clear()
            return
        }
        // Convert global cocoa rect to window-local coords
        let local = CGRect(
            x: cocoaRect.minX - screen.frame.minX,
            y: cocoaRect.minY - screen.frame.minY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
        withoutImplicitAnimation {
            fillLayer.isHidden = false
            fillLayer.frame = local
        }
    }

    func clear() {
        withoutImplicitAnimation {
            fillLayer.isHidden = true
        }
    }

    /// Exposed for geometry/animation regression tests only.
    var previewLayerForTesting: CALayer { fillLayer }

    /// Applies layer mutations with every implicit animation disabled, so the
    /// overlay tracks the drag on the same run-loop pass it was reported.
    private func withoutImplicitAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        body()
        CATransaction.commit()
    }
}
