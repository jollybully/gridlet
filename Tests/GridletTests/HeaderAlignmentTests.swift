import AppKit
import XCTest
@testable import Gridlet

@MainActor
final class HeaderAlignmentTests: XCTestCase {
    private let centerTolerance: CGFloat = 1.5
    private let gapTolerance: CGFloat = 0.5
    private let verticalTolerance: CGFloat = 0.5
    private let chromeGapTolerance: CGFloat = 0.5

    private func assertAligned(
        _ snap: PanelHeaderAlignmentSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snap.panelSize.width, 320, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(snap.panelSize.height, 380, accuracy: 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(snap.centerDelta), Double(centerTolerance), file: file, line: line)
        XCTAssertEqual(
            snap.iconTitleGap,
            Double(TargetAppHeaderView.iconTitleGap),
            accuracy: Double(gapTolerance),
            file: file,
            line: line
        )
        XCTAssertEqual(snap.icon.width, Double(TargetAppHeaderView.iconSize), accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(snap.icon.height, Double(TargetAppHeaderView.iconSize), accuracy: 0.5, file: file, line: line)

        let groupMidY = snap.group.y + snap.group.height / 2
        XCTAssertEqual(groupMidY, snap.headerCenterY, accuracy: Double(verticalTolerance), file: file, line: line)

        XCTAssertGreaterThanOrEqual(
            snap.group.x,
            snap.close.x + snap.close.width + Double(PanelMetrics.headerSideMargin) - Double(chromeGapTolerance),
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            snap.group.x + snap.group.width,
            snap.settings.x - Double(PanelMetrics.headerSideMargin) + Double(chromeGapTolerance),
            file: file,
            line: line
        )
    }

    func testHeaderGroupCenteredForRepresentativeTitles() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let controller = GridPanelController(screen: screen)

        let cases: [(String, TargetAppHeaderMetadata)] = [
            ("safari_short", TargetAppHeaderPresets.safari),
            ("visual_studio_code_medium", TargetAppHeaderPresets.visualStudioCode),
            (
                "very_long_app_name",
                TargetAppHeaderMetadata(
                    title: String(repeating: "Integration Studio ", count: 8),
                    symbolName: "app"
                )
            ),
            ("no_window", TargetAppHeaderPresets.noWindow),
        ]

        for (name, metadata) in cases {
            controller.prepareHeaderAlignmentProbe(metadata: metadata)
            let snap = controller.headerAlignmentSnapshot(scenario: name)
            assertAligned(snap)
        }
    }

    func testVeryLongTitleRetainsNonEmptyDisplayedText() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let controller = GridPanelController(screen: screen)
        let longTitle = String(repeating: "Integration Studio ", count: 8)
        controller.prepareHeaderAlignmentProbe(metadata: TargetAppHeaderMetadata(title: longTitle, symbolName: "app"))

        let label = controller.targetHeaderForTests.titleLabel
        XCTAssertEqual(label.stringValue, longTitle)
        XCTAssertFalse(label.stringValue.isEmpty)

        XCTAssertFalse(label.stringValue.isEmpty)
        let snap = controller.headerAlignmentSnapshot(scenario: "very_long_app_name")
        let intrinsic = (longTitle as NSString).size(withAttributes: [.font: label.font!]).width
        XCTAssertLessThan(snap.title.width, Double(intrinsic) - 1)
        XCTAssertLessThanOrEqual(
            snap.group.x + snap.group.width,
            snap.settings.x - Double(PanelMetrics.headerSideMargin) + 0.5
        )
    }

    func testPanelWidthStableWithLongTargetAndError() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let controller = GridPanelController(screen: screen)
        controller.configure(
            settings: GridSettings.Snapshot(),
            target: nil,
            displayMode: .live,
            errorMessage: String(repeating: "x", count: 500)
        )
        controller.layoutForWidthCheck()
        guard let window = controller.window else {
            XCTFail("no window")
            return
        }
        XCTAssertEqual(window.contentView?.bounds.width ?? 0, PanelMetrics.width, accuracy: 0.5)
        let snap = controller.headerAlignmentSnapshot(scenario: "long_target_stress")
        assertAligned(snap)
        XCTAssertFalse(controller.targetHeaderForTests.titleLabel.stringValue.isEmpty)
    }

    func testWritesHeaderAlignmentVerificationArtifact() throws {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let controller = GridPanelController(screen: screen)
        let snaps = HeaderAlignmentDiagnostics.allSnapshots(controller: controller)
        XCTAssertEqual(snaps.count, 4)
        for snap in snaps {
            assertAligned(snap)
        }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let out = root.appendingPathComponent("verification/header-alignment.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snaps)
        try data.write(to: out, options: .atomic)
    }
}
