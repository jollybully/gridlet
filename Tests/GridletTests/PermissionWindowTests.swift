import AppKit
import XCTest
@testable import Gridlet

final class PermissionWindowTests: XCTestCase {
    @MainActor
    func testPermissionWindowHasNoNestedPanelChrome() {
        let controller = PermissionWindowController.shared
        guard let root = controller.contentRootForTests else {
            XCTFail("no content root")
            return
        }
        XCTAssertFalse(StandardWindowLayout.containsPanelChrome(in: root))
    }

    @MainActor
    func testPermissionCopyMentionsRestartOnce() {
        let controller = PermissionWindowController.shared
        guard let root = controller.contentRootForTests else {
            XCTFail("no content root")
            return
        }
        let strings = allLabelStrings(in: root)
        let restartLines = strings.filter { $0.localizedCaseInsensitiveContains("quit") && $0.localizedCaseInsensitiveContains("reopen") }
        XCTAssertEqual(restartLines.count, 1)
        XCTAssertTrue(strings.contains { $0.contains("Allow window control") })
        XCTAssertTrue(strings.contains { $0.contains("Open Accessibility Settings") })
    }

    @MainActor
    func testPermissionControlsFitContentArea() {
        let controller = PermissionWindowController.shared
        guard let window = controller.window, let content = controller.contentRootForTests else {
            XCTFail("no window")
            return
        }
        window.layoutIfNeeded()
        let contentHeight = content.bounds.height
        XCTAssertGreaterThanOrEqual(contentHeight, 180)

        let buttons = allButtons(in: content)
        XCTAssertGreaterThanOrEqual(buttons.count, 2)
        for button in buttons {
            XCTAssertGreaterThanOrEqual(button.frame.maxY, 0)
            XCTAssertLessThanOrEqual(button.frame.maxY, contentHeight + 0.5)
            XCTAssertGreaterThanOrEqual(button.frame.minX, 0)
        }
    }

    @MainActor
    private func allLabelStrings(in root: NSView) -> [String] {
        var out: [String] = []
        if let field = root as? NSTextField {
            let value = field.stringValue
            if !value.isEmpty { out.append(value) }
        }
        for sub in root.subviews {
            out.append(contentsOf: allLabelStrings(in: sub))
        }
        return out
    }

    @MainActor
    private func allButtons(in root: NSView) -> [NSButton] {
        var out: [NSButton] = []
        if let button = root as? NSButton { out.append(button) }
        for sub in root.subviews {
            out.append(contentsOf: allButtons(in: sub))
        }
        return out
    }
}
