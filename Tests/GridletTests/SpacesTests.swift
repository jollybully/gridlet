import AppKit
import XCTest
@testable import Gridlet

@MainActor
final class SpacesTests: XCTestCase {

    // MARK: - Parsing the window server's display/space table

    private func fixtureEntries() -> [NSDictionary] {
        [
            [
                "Display Identifier": "Main",
                "Current Space": ["ManagedSpaceID": 4] as NSDictionary,
                "Spaces": [
                    ["ManagedSpaceID": 1, "type": 0] as NSDictionary,
                    ["ManagedSpaceID": 4, "type": 0] as NSDictionary,
                    ["ManagedSpaceID": 5, "type": 0] as NSDictionary,
                    ["ManagedSpaceID": 3, "type": 0] as NSDictionary,
                ] as NSArray,
            ] as NSDictionary,
            [
                "Display Identifier": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                "Spaces": [["ManagedSpaceID": 153, "type": 4] as NSDictionary] as NSArray,
            ] as NSDictionary,
        ]
    }

    func testParseKeepsDisplayOrderAndMarksCurrentSpace() {
        let displays = SpaceBridge.parse(entries: fixtureEntries(), windowCounter: nil)
        XCTAssertEqual(displays.count, 1, "a display with only non-user Spaces must not produce an entry")
        let main = displays[0]
        XCTAssertEqual(main.identifier, "Main")
        XCTAssertEqual(main.spaces.map(\.id), [1, 4, 5, 3], "raw ManagedSpaceIDs are not their order")
        XCTAssertEqual(main.spaces.map(\.index), [1, 2, 3, 4], "chip numbers are 1-based display order")
        XCTAssertEqual(main.spaces.filter(\.isCurrent).map(\.id), [4])
    }

    func testParseSkipsFullscreenSpaces() {
        let entries: [NSDictionary] = [[
            "Display Identifier": "Main",
            "Current Space": ["ManagedSpaceID": 7] as NSDictionary,
            "Spaces": [
                ["ManagedSpaceID": 7, "type": 0] as NSDictionary,
                ["ManagedSpaceID": 99, "type": 4] as NSDictionary,
            ] as NSArray,
        ] as NSDictionary]
        let spaces = SpaceBridge.parse(entries: entries, windowCounter: nil)[0].spaces
        XCTAssertEqual(spaces.map(\.id), [7])
    }

    func testParseAttachesWindowCounts() {
        let displays = SpaceBridge.parse(entries: fixtureEntries()) { spaceID in spaceID == 5 ? 3 : 0 }
        XCTAssertEqual(displays[0].spaces.map(\.windowCount), [0, 0, 3, 0])
    }

    // MARK: - Chip presentation rules

    func testCurrentSpaceChipIsInactiveAndDashed() {
        let current = SpaceStripModel.chip(for: ManagedSpace(id: 4, index: 2, isCurrent: true, windowCount: 1))
        XCTAssertFalse(current.isEnabled, "clicking the current Space is a no-op")
        XCTAssertTrue(current.isCurrent)
        XCTAssertEqual(current.countText, "● 1")

        let other = SpaceStripModel.chip(for: ManagedSpace(id: 5, index: 3, isCurrent: false, windowCount: 5))
        XCTAssertTrue(other.isEnabled)
        XCTAssertEqual(other.countText, "● 5")
        XCTAssertEqual(other.index, 3)
    }

    func testChipAccessibilityLabelAndMissingCounts() {
        XCTAssertEqual(
            SpaceStripModel.accessibilityLabel(
                for: ManagedSpace(id: 3, index: 4, isCurrent: false, windowCount: 1)
            ),
            "Space 4, 1 window"
        )
        let unknown = SpaceStripModel.chip(for: ManagedSpace(id: 3, index: 1, isCurrent: true, windowCount: nil))
        XCTAssertEqual(unknown.countText, "", "no invented counts when the private call fails")
        XCTAssertEqual(unknown.accessibilityLabel, "Space 1, current Space")
    }

    func testMessages() {
        XCTAssertEqual(SpaceStripModel.sendMessage(appName: "Safari", spaceIndex: 3), "Safari → Space 3")
        XCTAssertEqual(SpaceStripModel.errorMessage(spaceIndex: 2), "Couldn't move that window to Space 2.")
    }

    // MARK: - Strip view

    private func spacesFixture() -> [ManagedSpace] {
        [
            ManagedSpace(id: 1, index: 1, isCurrent: false, windowCount: 3),
            ManagedSpace(id: 4, index: 2, isCurrent: true, windowCount: 1),
            ManagedSpace(id: 5, index: 3, isCurrent: false, windowCount: 5),
        ]
    }

    func testStripRendersOneChipPerSpace() {
        let strip = SpaceStripView(frame: NSRect(x: 0, y: 0, width: 280, height: 30))
        strip.configure(spaces: spacesFixture())
        XCTAssertEqual(strip.chipCount, 3)
        XCTAssertEqual(
            strip.chipProtocolNames(),
            ["Space 1, 3 windows", "Space 2, 1 window, current Space", "Space 3, 5 windows"]
        )
        XCTAssertFalse(strip.isCurrentHighlightedOnly)
    }

    private func makeStrip(_ spaces: [ManagedSpace]) -> (SpaceStripView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: PanelMetrics.spaceStripHeight),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let strip = SpaceStripView(frame: NSRect(x: 0, y: 0, width: 280, height: PanelMetrics.spaceStripHeight))
        window.contentView?.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            strip.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: PanelMetrics.spaceStripHeight),
        ])
        strip.configure(spaces: spaces)
        window.layoutIfNeeded()
        strip.layoutSubtreeIfNeeded()
        return (strip, window)
    }

    private func clickStrip(_ strip: SpaceStripView, in window: NSWindow, atStripPoint point: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        let windowPoint = strip.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: windowPoint, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0
            )!
            type == .leftMouseDown ? strip.mouseDown(with: event) : strip.mouseUp(with: event)
        }
    }

    func testStripHitTestingMapsPointsToChips() {
        let (strip, window) = makeStrip(spacesFixture())
        let frames = strip.chipFrames()
        XCTAssertEqual(frames.count, 3)
        guard frames.count == 3, frames.allSatisfy({ $0.width > 1 }) else {
            return XCTFail("chips did not lay out: \(frames)")
        }
        for (index, frame) in frames.enumerated() {
            XCTAssertEqual(strip.chipIndex(at: NSPoint(x: frame.midX, y: frame.midY)), index)
        }
        XCTAssertNil(strip.chipIndex(at: NSPoint(x: -10, y: 15)), "points outside the strip hit nothing")
        XCTAssertTrue(window.contentView?.subviews.contains(strip) ?? false)
    }

    func testClickingStripChipSendsThatSpace() {
        let (strip, window) = makeStrip(spacesFixture())
        var received: [(ManagedSpace, Bool)] = []
        strip.onSelect = { received.append(($0, $1)) }
        let third = strip.chipFrames()[2]

        clickStrip(strip, in: window, atStripPoint: NSPoint(x: third.midX, y: third.midY))

        XCTAssertEqual(received.count, 1, "a click on a chip must reach onSelect")
        XCTAssertEqual(received.first?.0.id, 5, "third chip is Space 3")
        XCTAssertEqual(received.first?.1, false, "plain click sends without following")
    }

    func testOptionClickingStripChipAsksToFollow() {
        let (strip, window) = makeStrip(spacesFixture())
        var follow: Bool?
        strip.onSelect = { _, f in follow = f }
        let first = strip.chipFrames()[0]

        clickStrip(strip, in: window, atStripPoint: NSPoint(x: first.midX, y: first.midY), modifiers: [.option])

        XCTAssertEqual(follow, true)
    }

    func testClickingCurrentSpaceChipIsIgnored() {
        let (strip, window) = makeStrip(spacesFixture())
        var clicks = 0
        strip.onSelect = { _, _ in clicks += 1 }
        let current = strip.chipFrames()[1] // Space 2 in the fixture is current

        clickStrip(strip, in: window, atStripPoint: NSPoint(x: current.midX, y: current.midY))

        XCTAssertEqual(clicks, 0, "sending a window to the Space it is already on is a no-op")
    }

    func testReleaseOutsideChipsIsIgnored() {
        let (strip, window) = makeStrip(spacesFixture())
        var clicks = 0
        strip.onSelect = { _, _ in clicks += 1 }
        let chip = strip.chipFrames()[2]

        clickStrip(strip, in: window, atStripPoint: NSPoint(x: chip.midX, y: chip.midY))
        // A second press that releases well outside the strip must not fire again.
        let outside = NSPoint(x: strip.bounds.midX, y: strip.bounds.maxY + 80)
        let windowPoint = strip.convert(outside, to: nil)
        strip.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)
        strip.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: windowPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!)

        XCTAssertEqual(clicks, 1, "only the first click counts")
    }

    // MARK: - Panel geometry

    func testPanelGrowsByTheStripHeight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return XCTFail("no screen") }
        let without = PanelMetrics.panelSize(for: screen, hasSpaceStrip: false)
        let with = PanelMetrics.panelSize(for: screen, hasSpaceStrip: true)
        XCTAssertEqual(
            with.height - without.height,
            PanelMetrics.spaceStripHeight + PanelMetrics.spaceStripGap,
            accuracy: 0.01
        )
        XCTAssertEqual(with.width, without.width)
    }

    func testPanelWithStripKeepsGridAspect() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return XCTFail("no screen") }
        let size = PanelMetrics.panelSize(for: screen, hasSpaceStrip: true)
        let gridHeight = PanelMetrics.gridHeight(for: screen)
        let gridTop = size.height - PanelMetrics.chromeBelowGrid - gridHeight
        XCTAssertEqual(gridTop, PanelMetrics.gridTopInset(hasSpaceStrip: true), accuracy: 0.01)
        XCTAssertEqual(
            PanelMetrics.gridWidth / gridHeight,
            PanelMetrics.gridAspect(for: screen),
            accuracy: 0.02
        )
    }

}