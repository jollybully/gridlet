import AppKit

/// Renders an AppKit view subtree into a bitmap (layer-backed controls + custom `draw` views).
enum ViewHierarchySnapshot {
    @MainActor
    static func pngData(of root: NSView, appearance: NSAppearance? = nil) -> Data? {
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()

        let size = root.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let captureAppearance = appearance ?? effectiveAppearance(for: root)

        var layerStack: [(NSView, Bool)] = []
        func stripLayers(_ view: NSView) {
            if view.wantsLayer {
                layerStack.append((view, true))
                view.wantsLayer = false
                view.needsDisplay = true
            }
            for sub in view.subviews {
                stripLayers(sub)
            }
        }

        let drawBlock = { () -> Data? in
            stripLayers(root)
            root.layoutSubtreeIfNeeded()
            for sub in root.subviews {
                if let control = sub as? NSControl {
                    control.needsDisplay = true
                }
            }
            root.displayIfNeeded()

            defer {
                for (view, wasOn) in layerStack where wasOn {
                    view.wantsLayer = true
                }
            }

            guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return nil }
            root.cacheDisplay(in: root.bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }

        var result: Data?
        captureAppearance.performAsCurrentDrawingAppearance {
            result = drawBlock()
        }
        return result
    }

    @MainActor
    private static func effectiveAppearance(for view: NSView) -> NSAppearance {
        if let window = view.window, let appearance = window.effectiveAppearance as NSAppearance? {
            return appearance
        }
        return NSApp.effectiveAppearance
    }
}
