import AppKit
import QuartzCore
import XCTest
@testable import Gridlet

@MainActor
final class PreviewOverlayTests: XCTestCase {
    func testPreviewLevelBelowFloatingPanel() {
        guard let screen = NSScreen.main else {
            XCTFail("no main screen")
            return
        }
        let overlay = PreviewOverlayWindow(screen: screen)
        let panel = GridPanelWindow()
        let overlayLevel = overlay.level.rawValue
        let panelLevel = panel.level.rawValue
        XCTAssertLessThan(overlayLevel, panelLevel)
        XCTAssertEqual(overlayLevel, NSWindow.Level.floating.rawValue - 1)
    }

    /// The preview must track the pointer, not ease towards it. Core Animation's
    /// implicit transitions default to 0.25s, which reads as a sluggish trail.
    func testPreviewLayerHasNoImplicitAnimationActions() {
        guard let screen = NSScreen.main else {
            XCTFail("no main screen")
            return
        }
        let overlay = PreviewOverlayWindow(screen: screen)
        let layer = overlay.previewLayerForTesting
        for key in PreviewOverlayWindow.nonAnimatedLayerKeys {
            XCTAssertTrue(
                layer.actions?[key] is NSNull,
                "layer key '\(key)' must not be implicitly animated"
            )
            XCTAssertNil(
                layer.action(forKey: key),
                "layer key '\(key)' still resolves to an implicit animation"
            )
        }
    }

    func testPreviewFrameUpdatesSynchronouslyDuringDrag() {
        guard let screen = NSScreen.main else {
            XCTFail("no main screen")
            return
        }
        let overlay = PreviewOverlayWindow(screen: screen)
        let first = CGRect(x: screen.frame.minX + 100, y: screen.frame.minY + 100, width: 300, height: 200)
        let second = CGRect(x: screen.frame.minX + 120, y: screen.frame.minY + 140, width: 520, height: 360)

        overlay.updatePreview(cocoaRect: first, on: screen)
        let firstModel = overlay.previewLayerForTesting.frame
        // A mid-flight presentation layer would mean the visible frame lags behind.
        XCTAssertNil(
            overlay.previewLayerForTesting.presentation(),
            "no in-flight animation should exist immediately after an update"
        )

        overlay.updatePreview(cocoaRect: second, on: screen)
        let secondModel = overlay.previewLayerForTesting.frame
        XCTAssertNotEqual(firstModel, secondModel)
        XCTAssertNil(overlay.previewLayerForTesting.presentation())

        // Model frame is expressed in window-local coordinates.
        XCTAssertEqual(secondModel.origin.x, second.minX - screen.frame.minX, accuracy: 0.5)
        XCTAssertEqual(secondModel.origin.y, second.minY - screen.frame.minY, accuracy: 0.5)
        XCTAssertEqual(secondModel.width, second.width, accuracy: 0.5)
        XCTAssertEqual(secondModel.height, second.height, accuracy: 0.5)
    }
}
