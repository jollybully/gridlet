import AppKit
import CoreGraphics
import Foundation

/// `--spaces-demo [spaceIndex]`: drives the real panel on the real screen so the
/// interaction can be recorded.
///
/// This process has no Accessibility permission to synthesise a click, so instead of
/// faking mouse events it parks the system cursor over the chip and then calls the very
/// same `PanelCoordinator.send(windowTo:on:follow:)` the chip calls on mouse-up. Everything
/// visible afterwards — the window leaving this Space, the toast, the window sitting on the
/// destination Space — is the shipping code path. The chip's hit-testing is covered by
/// SpacesTests.
@MainActor
enum SpacesDemo {
    static let logPath = "/tmp/gridlet-spaces-demo.log"

    private static func log(_ line: String) {
        print(line)
        let url = URL(fileURLWithPath: logPath)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func run(spaceIndex: Int) {
        guard WindowTargetResolver.isTrusted() else {
            log("DEMO_ERROR Accessibility permission for Gridlet is required")
            // Rebuilding changes the ad-hoc signature, so macOS drops the existing grant.
            // Ask the system to show the dialog rather than failing silently.
            WindowTargetResolver.promptForTrust()
            exit(1)
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            log("DEMO_ERROR no screen")
            exit(1)
        }
        let coordinator = PanelCoordinator.shared
        guard let target = WindowTargetResolver.captureFrontmostTarget(excludingGridlet: true) else {
            log("DEMO_ERROR no focused window to send")
            exit(1)
        }
        log("DEMO_TARGET \(WindowTargetResolver.appDisplayName(for: target))")
        coordinator.presentPanels()

        guard let panel = coordinator.firstPanelController() else {
            log("DEMO_ERROR panel did not open")
            exit(1)
        }
        let spaces = SpaceBridge.spaces(for: screen)
        log("DEMO_SPACES " + spaces.map { "\($0.index):\($0.id)\($0.isCurrent ? "*" : "")" }.joined(separator: " "))
        guard let space = spaces.first(where: { $0.index == spaceIndex }) else {
            log("DEMO_ERROR no Space \(spaceIndex)")
            exit(1)
        }

        // Park the cursor on the chip so the recording shows what a human would do.
        let frames = panel.spaceStrip.chipFrames()
        if spaceIndex - 1 < frames.count {
            let chip = frames[spaceIndex - 1]
            let windowOrigin = panel.window?.frame.origin ?? .zero
            let screenPoint = NSPoint(x: windowOrigin.x + chip.midX, y: windowOrigin.y + chip.midY)
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let globalPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)
            CGWarpMouseCursorPosition(globalPoint)
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        let windowID = SpaceBridge.windowID(for: target)
        log("DEMO_WINDOW \(windowID.map(String.init) ?? "nil") ")
        log("DEMO_MODE sending \(WindowTargetResolver.appDisplayName(for: target)) to Space \(spaceIndex)")

        // Hold the panel on screen long enough to be seen, then send.
        let originID = SpaceBridge.spaces(for: screen).first(where: \.isCurrent)?.id
        let destinationID = space.id
        let destinationIndex = space.index
        let displayIdentifier = SpaceBridge.displayIdentifier(for: screen) ?? "Main"
        let windowNumber = windowID

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            coordinator.send(windowTo: space, on: screen, follow: false)
            pollForLanding(
                windowNumber: windowNumber,
                destinationID: destinationID,
                destinationIndex: destinationIndex,
                displayIdentifier: displayIdentifier,
                originID: originID
            )
        }
    }

    /// The move runs off the main thread and takes ~2s; wait for the window to actually
    /// arrive before switching Spaces to show it, then come back.
    private static func pollForLanding(
        windowNumber: CGWindowID?,
        destinationID: UInt64,
        destinationIndex: Int,
        displayIdentifier: String,
        originID: UInt64?
    ) {
        let deadline = Date().addingTimeInterval(6)
        func tick() {
            let landed = windowNumber.flatMap { SpaceBridge.spaceID(forWindow: $0) }
            guard landed == destinationID || Date() > deadline else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: tick)
                return
            }
            log("DEMO_RESULT window space now \(landed.map(String.init) ?? "unknown") (wanted \(destinationID))")
            _ = SpaceBridge.switchTo(spaceID: destinationID, displayIdentifier: displayIdentifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                if let originID {
                    _ = SpaceBridge.switchTo(spaceID: originID, displayIdentifier: displayIdentifier)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    log("DEMO_DONE space \(destinationIndex)")
                    exit(0)
                }
            }
        }
        tick()
    }
}
