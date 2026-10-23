import AppKit
import XCTest
@testable import Gridlet

@MainActor
final class HotKeyRecorderLifecycleTests: XCTestCase {
    private func syntheticMouseDown() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
    }

    private func mountInWindow(_ view: NSView, window: NSWindow? = nil) -> NSWindow {
        let host = window ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: host.contentRect(forFrameRect: host.frame))
        view.frame = NSRect(x: 8, y: 8, width: view.intrinsicContentSize.width, height: view.intrinsicContentSize.height)
        container.addSubview(view)
        host.contentView = container
        return host
    }

    func testGlobalHotKeyRecorderEndRecordingClearsMonitorState() {
        let recorder = HotKeyRecorderView()
        let window = mountInWindow(recorder)
        window.makeKeyAndOrderFront(nil)

        recorder.mouseDown(with: syntheticMouseDown())
        XCTAssertTrue(recorder.isRecording)

        recorder.endRecording()
        XCTAssertFalse(recorder.isRecording)
    }

    func testGlobalHotKeyRecorderResignFirstResponderClearsMonitorState() {
        let recorder = HotKeyRecorderView()
        let window = mountInWindow(recorder)
        window.makeKeyAndOrderFront(nil)

        recorder.mouseDown(with: syntheticMouseDown())
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(window.makeFirstResponder(recorder))

        XCTAssertTrue(recorder.resignFirstResponder())
        XCTAssertFalse(recorder.isRecording)
    }

    func testSettingsWindowWillCloseEndsGlobalRecording() {
        let controller = SettingsWindowController.shared
        let recorder = controller.globalHotKeyRecorder
        let window = controller.window!
        _ = mountInWindow(recorder, window: window)
        window.makeKeyAndOrderFront(nil)

        recorder.mouseDown(with: syntheticMouseDown())
        XCTAssertTrue(recorder.isRecording)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertFalse(recorder.isRecording)
    }

    func testSettingsWindowDidResignKeyEndsGlobalRecording() {
        let controller = SettingsWindowController.shared
        let recorder = controller.globalHotKeyRecorder
        let window = controller.window!
        _ = mountInWindow(recorder, window: window)
        window.makeKeyAndOrderFront(nil)

        recorder.mouseDown(with: syntheticMouseDown())
        XCTAssertTrue(recorder.isRecording)

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertFalse(recorder.isRecording)
    }
}
