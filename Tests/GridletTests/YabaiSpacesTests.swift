import AppKit
import XCTest
@testable import Gridlet

final class YabaiSpacesTests: XCTestCase {
    private let spacesJSON = """
    [{
    \t"id":1,
    \t"uuid":"",
    \t"index":1,
    \t"label":"",
    \t"type":"float",
    \t"display":1,
    \t"windows":[301176, 301005],
    \t"first-window":0,
    \t"last-window":0,
    \t"has-focus":false,
    \t"is-visible":false,
    \t"is-native-fullscreen":false
    },{
    \t"id":3,
    \t"uuid":"2EB7B147-2200-4CE3-90E8-4BDB18B093E1",
    \t"index":2,
    \t"label":"",
    \t"type":"float",
    \t"display":1,
    \t"windows":[301176, 300996],
    \t"first-window":0,
    \t"last-window":0,
    \t"has-focus":false,
    \t"is-visible":false,
    \t"is-native-fullscreen":false
    },{
    \t"id":4,
    \t"uuid":"FE019ABF-90B3-4FA3-AF59-0322B9857A5B",
    \t"index":3,
    \t"label":"",
    \t"type":"float",
    \t"display":1,
    \t"windows":[301176],
    \t"first-window":0,
    \t"last-window":0,
    \t"has-focus":true,
    \t"is-visible":true,
    \t"is-native-fullscreen":false
    },{
    \t"id":5,
    \t"uuid":"E52181F0-3A52-4AB1-ADC4-AB451B9C7370",
    \t"index":4,
    \t"label":"",
    \t"type":"float",
    \t"display":1,
    \t"windows":[301176],
    \t"first-window":0,
    \t"last-window":0,
    \t"has-focus":false,
    \t"is-visible":false,
    \t"is-native-fullscreen":false
    },{
    \t"id":9,
    \t"uuid":"fullscreen",
    \t"index":5,
    \t"label":"",
    \t"type":"float",
    \t"display":1,
    \t"windows":[],
    \t"first-window":0,
    \t"last-window":0,
    \t"has-focus":false,
    \t"is-visible":false,
    \t"is-native-fullscreen":true
    }]
    """

    private let displaysJSON = """
    [{"id":1,"index":1,"frame":{"x":0,"y":0,"w":1905,"h":1237},"spaces":[1,2,3,4]}]
    """

    private let windowsJSON = """
    [
      {"id":301176,"pid":1,"app":"Sticky","frame":{"x":0,"y":0,"w":10,"h":10},"space":3,"has-ax-reference":true,"is-native-fullscreen":false,"is-sticky":true},
      {"id":300996,"pid":34404,"app":"Google Chrome","frame":{"x":0,"y":46,"w":1905,"h":1191},"space":2,"has-ax-reference":true,"is-native-fullscreen":false,"is-sticky":false},
      {"id":300971,"pid":34404,"app":"Google Chrome","frame":{"x":40,"y":80,"w":800,"h":600},"space":2,"has-ax-reference":true,"is-native-fullscreen":false,"is-sticky":false}
    ]
    """

    func testLiveSpacesBecomeIndexChips() throws {
        let spaces = try XCTUnwrap(YabaiJSON.spaces(from: spacesJSON))
        let displays = try XCTUnwrap(YabaiJSON.displays(from: displaysJSON))
        let screen = CGRect(x: 0, y: 0, width: 1905, height: 1237)
        let display = try XCTUnwrap(YabaiGeometry.displayIndex(screenFrame: screen, primaryTop: 1237, displays: displays))
        XCTAssertEqual(display, 1)
        let chips = YabaiGeometry.chips(spaces: spaces, displayIndex: display)
        XCTAssertEqual(chips, YabaiSnapshotFixture.chips)
        XCTAssertEqual(chips.map(\.index), [1, 2, 3, 4])
        XCTAssertEqual(chips.first { $0.isCurrent }?.index, 3)
    }

    func testStickyWindowIsNotCountedAsFourSpaces() throws {
        let spaces = try XCTUnwrap(YabaiJSON.spaces(from: spacesJSON))
        let listedEverywhere = Set(spaces.map(\.id)).count
        XCTAssertEqual(listedEverywhere, 5)
        let chips = YabaiGeometry.chips(spaces: spaces, displayIndex: 1)
        XCTAssertEqual(chips.count, 4)
    }

    func testMatchWindowUsesFrameWhenPidHasSeveral() throws {
        let windows = try XCTUnwrap(YabaiJSON.windows(from: windowsJSON))
        let chrome = YabaiGeometry.matchWindow(
            pid: 34404,
            axFrame: CGRect(x: 0, y: 46, width: 1905, height: 1191),
            windows: windows
        )
        XCTAssertEqual(chrome?.id, 300996)
        let other = YabaiGeometry.matchWindow(
            pid: 34404,
            axFrame: CGRect(x: 40, y: 80, width: 800, height: 600),
            windows: windows
        )
        XCTAssertEqual(other?.id, 300971)
    }

    func testSendArgvAndMembership() throws {
        let moved = windowsJSON.replacingOccurrences(of: "\"id\":300996,\"pid\":34404,\"app\":\"Google Chrome\",\"frame\":{\"x\":0,\"y\":46,\"w\":1905,\"h\":1191},\"space\":2", with: "\"id\":300996,\"pid\":34404,\"app\":\"Google Chrome\",\"frame\":{\"x\":0,\"y\":46,\"w\":1905,\"h\":1191},\"space\":1")
        var calls: [[String]] = []
        let session = YabaiSession { args in
            calls.append(args)
            if args == YabaiCommand.queryWindows() {
                return YabaiReply(status: 0, stdout: self.windowsJSON, stderr: "")
            }
            if args == YabaiCommand.send(windowID: 300996, spaceIndex: 1) {
                return YabaiReply(status: 0, stdout: "", stderr: "")
            }
            if args == YabaiCommand.queryWindow(300996) {
                return YabaiReply(status: 0, stdout: moved, stderr: "")
            }
            return YabaiReply(status: 1, stdout: "", stderr: "unexpected \(args)")
        }
        let outcome = session.send(
            pid: 34404,
            axFrame: CGRect(x: 0, y: 46, width: 1905, height: 1191),
            appName: "Google Chrome",
            toSpace: 1,
            follow: true
        )
        guard case .sent(let sent) = outcome else {
            return XCTFail("expected send, got \(outcome)")
        }
        XCTAssertEqual(sent.windowID, 300996)
        XCTAssertEqual(sent.originIndex, 2)
        XCTAssertEqual(sent.destinationIndex, 1)
        XCTAssertEqual(sent.message, "Google Chrome → Space 1")
        XCTAssertEqual(calls, [
            YabaiCommand.queryWindows(),
            YabaiCommand.send(windowID: 300996, spaceIndex: 1),
            YabaiCommand.queryWindow(300996),
            YabaiCommand.focus(spaceIndex: 1),
        ])
    }

    func testUnchangedMembershipIsAFailure() {
        var calls: [[String]] = []
        let session = YabaiSession { args in
            calls.append(args)
            if args == YabaiCommand.queryWindows() || args == YabaiCommand.queryWindow(300996) {
                return YabaiReply(status: 0, stdout: self.windowsJSON, stderr: "")
            }
            if args.contains("--space") {
                return YabaiReply(status: 0, stdout: "", stderr: "")
            }
            return YabaiReply(status: 1, stdout: "", stderr: "unexpected")
        }
        let outcome = session.send(
            pid: 34404,
            axFrame: CGRect(x: 0, y: 46, width: 1905, height: 1191),
            appName: "Google Chrome",
            toSpace: 1,
            follow: false
        )
        guard case .failed = outcome else {
            return XCTFail("exit 0 without a space change must fail")
        }
        XCTAssertFalse(calls.contains(YabaiCommand.focus(spaceIndex: 1)))
    }

    func testStickyWindowIsNotSent() {
        var calls: [[String]] = []
        let session = YabaiSession { args in
            calls.append(args)
            return YabaiReply(status: 0, stdout: self.windowsJSON, stderr: "")
        }
        let outcome = session.send(pid: 1, axFrame: nil, appName: "Sticky", toSpace: 1, follow: false)
        guard case .failed(let message) = outcome else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(message.contains("every Space"))
        XCTAssertEqual(calls, [YabaiCommand.queryWindows()])
    }

    func testScriptingAdditionFailureIsActionable() {
        let text = YabaiSession.shortMessage("could not locate the window to act on!\n", fallback: "x")
        XCTAssertTrue(text.contains("sudo yabai --load-sa"))
    }

    func testSocketFailureIsNotRunning() {
        let session = YabaiSession { _ in
            YabaiReply(status: 1, stdout: "", stderr: "yabai-msg: failed to connect to socket..\n")
        }
        XCTAssertEqual(session.availability(binaryFound: true), .notRunning)
        XCTAssertEqual(session.availability(binaryFound: false), .notInstalled)
    }
}

@MainActor
private final class ScriptedSpaceClient: SpaceSending {
    var outcome: SpaceSendOutcome = .failed("scripted")
    var lastSend: (index: Int, follow: Bool)?
    func availability() -> YabaiAvailability { .available }
    func chips(screenFrame: CGRect, primaryTop: CGFloat) -> [SpaceChip] { [] }
    func send(pid: pid_t, axFrame: CGRect?, appName: String, toSpace index: Int, follow: Bool) -> SpaceSendOutcome {
        lastSend = (index, follow)
        return outcome
    }
    func move(windowID: Int, toSpace index: Int) -> String? { nil }
}

@MainActor
final class SpaceStripTests: XCTestCase {
    private let chips: [SpaceChip] = [
        SpaceChip(index: 1, isCurrent: false),
        SpaceChip(index: 2, isCurrent: false),
        SpaceChip(index: 3, isCurrent: true),
        SpaceChip(index: 4, isCurrent: false),
    ]

    func testChipDoesNotOwnHits() {
        let (window, strip) = installedStripPair()
        let chipPoint = NSPoint(x: 10, y: 8)
        let inWindow = strip.convert(chipPoint, to: nil)
        let hit = window.contentView?.hitTest(inWindow)
        XCTAssertTrue(hit === strip)
        XCTAssertEqual(strip.chipIndex(at: chipPoint), 0)
        _ = window
    }

    func testClickNonCurrentChipFollowsOption() {
        let (window, strip) = installedStripPair()
        var sent: (Int, Bool)?
        strip.onActivate = { chip, follow in sent = (chip.index, follow) }
        click(strip, in: window, chip: 0, option: true)
        XCTAssertEqual(sent?.0, 1)
        XCTAssertEqual(sent?.1, true)
        sent = nil
        click(strip, in: window, chip: 2, option: false)
        XCTAssertNil(sent)
    }

    func testFailedSendKeepsThePanelOpen() {
        SpaceSendToast.suppress = true
        let coord = PanelCoordinator.shared
        let scripted = ScriptedSpaceClient()
        scripted.outcome = .failed("yabai isn’t running.")
        let previous = coord.spaceClient
        coord.spaceClient = scripted
        coord.snapshotDisplayMode = .snapshotIdle
        coord.snapshotSpaceChips = chips
        coord.presentPanels()
        defer {
            coord.spaceClient = previous
            coord.snapshotSpaceChips = nil
            coord.snapshotDisplayMode = nil
            coord.setCapturedTargetForTests(nil)
            coord.dismissAll(reason: .monitorChange)
        }
        guard let panel = coord.firstPanelController(), let window = panel.window else {
            return XCTFail("no panel")
        }
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        coord.setCapturedTargetForTests(WindowTarget(pid: ProcessInfo.processInfo.processIdentifier, axElement: element))
        click(panel.spaceStripForTests, in: window, chip: 0, option: false)
        XCTAssertEqual(scripted.lastSend?.index, 1)
        XCTAssertEqual(scripted.lastSend?.follow, false)
        XCTAssertTrue(coord.panelsAreVisible)
        XCTAssertEqual(panel.errorTextForTests, "yabai isn’t running.")
    }

    private func installedStripPair() -> (NSWindow, SpaceStripView) {
        let strip = SpaceStripView(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 26),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(strip)
        strip.frame = window.contentView?.bounds ?? .zero
        strip.setChips(chips)
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        strip.layoutSubtreeIfNeeded()
        return (window, strip)
    }

    private func click(_ strip: SpaceStripView, in window: NSWindow, chip: Int, option: Bool) {
        window.layoutIfNeeded()
        strip.layoutSubtreeIfNeeded()
        let width = strip.bounds.width / CGFloat(chips.count)
        let local = NSPoint(x: width * CGFloat(chip) + width / 2, y: strip.bounds.midY)
        let loc = strip.convert(local, to: nil)
        let flags: NSEvent.ModifierFlags = option ? .option : []
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type,
                location: loc,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )!
            window.sendEvent(event)
        }
    }
}
