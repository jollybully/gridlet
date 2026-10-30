import Foundation

struct YabaiReply: Equatable, Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
}

struct YabaiBox: Equatable, Decodable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var rect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
}

struct YabaiDisplay: Equatable, Decodable, Sendable {
    var id: Int
    var index: Int
    var frame: YabaiBox
    var spaces: [Int]
}

struct YabaiSpace: Equatable, Decodable, Sendable {
    var id: Int
    var index: Int
    var display: Int
    var isVisible: Bool
    var isNativeFullscreen: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, display
        case isVisible = "is-visible"
        case isNativeFullscreen = "is-native-fullscreen"
    }
}

struct YabaiWindow: Equatable, Decodable, Sendable {
    var id: Int
    var pid: Int
    var app: String
    var frame: YabaiBox
    var space: Int
    var hasAXReference: Bool
    var isNativeFullscreen: Bool
    var isSticky: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, frame, space
        case hasAXReference = "has-ax-reference"
        case isNativeFullscreen = "is-native-fullscreen"
        case isSticky = "is-sticky"
    }
}

struct SpaceChip: Equatable, Sendable {
    /// Yabai space index. This is the number Mission Control and `yabai --space` use.
    var index: Int
    var isCurrent: Bool
}

enum YabaiAvailability: Equatable, Sendable {
    case available
    case notInstalled
    case notRunning
    case unreachable
}

enum SpaceSendOutcome: Equatable, Sendable {
    case ignoredCurrent
    case failed(String)
    case sent(SpaceSendSuccess)
}

struct SpaceSendSuccess: Equatable, Sendable {
    var message: String
    var windowID: Int
    var originIndex: Int
    var destinationIndex: Int
}

enum YabaiSnapshotFixture {
    /// Live layout from this machine: indexes 1–4, visible space is 3.
    static let chips: [SpaceChip] = [
        SpaceChip(index: 1, isCurrent: false),
        SpaceChip(index: 2, isCurrent: false),
        SpaceChip(index: 3, isCurrent: true),
        SpaceChip(index: 4, isCurrent: false),
    ]
}

enum YabaiBinary {
    static let candidates = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]

    static func resolve() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

enum YabaiCommand {
    static func querySpaces() -> [String] { ["-m", "query", "--spaces"] }
    static func queryDisplays() -> [String] { ["-m", "query", "--displays"] }
    static func queryWindows() -> [String] { ["-m", "query", "--windows"] }
    static func queryWindow(_ id: Int) -> [String] { ["-m", "query", "--windows", "--window", String(id)] }
    static func send(windowID: Int, spaceIndex: Int) -> [String] {
        ["-m", "window", String(windowID), "--space", String(spaceIndex)]
    }
    static func focus(spaceIndex: Int) -> [String] {
        ["-m", "space", "--focus", String(spaceIndex)]
    }
}

enum YabaiGeometry {
    /// Yabai display frames use a top-left origin. `primaryTop` is the main display's Cocoa maxY.
    static func displayMatches(screenFrame: CGRect, yabai: YabaiBox, primaryTop: CGFloat) -> Bool {
        let sizeOK = abs(screenFrame.width - yabai.w) < 2 && abs(screenFrame.height - yabai.h) < 2
        let xOK = abs(screenFrame.minX - yabai.x) < 2
        guard sizeOK, xOK else { return false }
        let topLeftY = primaryTop - screenFrame.maxY
        return abs(topLeftY - yabai.y) < 2 || abs(screenFrame.minY - yabai.y) < 2
    }

    static func displayIndex(screenFrame: CGRect, primaryTop: CGFloat, displays: [YabaiDisplay]) -> Int? {
        if let match = displays.first(where: {
            displayMatches(screenFrame: screenFrame, yabai: $0.frame, primaryTop: primaryTop)
        }) {
            return match.index
        }
        if displays.count == 1 { return displays[0].index }
        return nil
    }

    /// Desktop spaces on one display, labeled by yabai index. Fullscreen spaces are omitted.
    /// The visible space is current.
    static func chips(spaces: [YabaiSpace], displayIndex: Int) -> [SpaceChip] {
        spaces
            .filter { $0.display == displayIndex && !$0.isNativeFullscreen }
            .sorted { $0.index < $1.index }
            .map { SpaceChip(index: $0.index, isCurrent: $0.isVisible) }
    }

    /// Pick the yabai window for an AX target. One window for the pid is enough.
    /// Several windows require the AX frame to land near the yabai frame.
    static func matchWindow(pid: pid_t, axFrame: CGRect?, windows: [YabaiWindow]) -> YabaiWindow? {
        let mine = windows.filter { $0.pid == Int(pid) }
        guard !mine.isEmpty else { return nil }
        guard mine.count > 1 else { return mine[0] }
        guard let axFrame else { return nil }
        let best = mine.min { lhs, rhs in
            frameDistance(lhs.frame.rect, axFrame) < frameDistance(rhs.frame.rect, axFrame)
        }
        guard let best, frameDistance(best.frame.rect, axFrame) < 80 else { return nil }
        return best
    }

    static func frameDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}

enum YabaiJSON {
    static func displays(from stdout: String) -> [YabaiDisplay]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([YabaiDisplay].self, from: data)
    }

    static func spaces(from stdout: String) -> [YabaiSpace]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([YabaiSpace].self, from: data)
    }

    static func windows(from stdout: String) -> [YabaiWindow]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        if let many = try? JSONDecoder().decode([YabaiWindow].self, from: data) {
            return many
        }
        if let one = try? JSONDecoder().decode(YabaiWindow.self, from: data) {
            return [one]
        }
        return nil
    }
}

struct YabaiSession {
    var run: ([String]) -> YabaiReply

    func availability(binaryFound: Bool) -> YabaiAvailability {
        guard binaryFound else { return .notInstalled }
        let reply = run(YabaiCommand.querySpaces())
        if reply.status == 0, YabaiJSON.spaces(from: reply.stdout) != nil {
            return .available
        }
        if reply.stderr.localizedCaseInsensitiveContains("socket") {
            return .notRunning
        }
        return .unreachable
    }

    func chips(screenFrame: CGRect, primaryTop: CGFloat) -> [SpaceChip] {
        let displaysReply = run(YabaiCommand.queryDisplays())
        let spacesReply = run(YabaiCommand.querySpaces())
        guard displaysReply.status == 0, spacesReply.status == 0,
              let displays = YabaiJSON.displays(from: displaysReply.stdout),
              let spaces = YabaiJSON.spaces(from: spacesReply.stdout),
              let displayIndex = YabaiGeometry.displayIndex(
                screenFrame: screenFrame, primaryTop: primaryTop, displays: displays
              ) else {
            return []
        }
        return YabaiGeometry.chips(spaces: spaces, displayIndex: displayIndex)
    }

    func send(
        pid: pid_t,
        axFrame: CGRect?,
        appName: String,
        toSpace destination: Int,
        follow: Bool
    ) -> SpaceSendOutcome {
        let listed = run(YabaiCommand.queryWindows())
        guard listed.status == 0, let windows = YabaiJSON.windows(from: listed.stdout) else {
            return .failed(YabaiSession.shortMessage(listed.stderr, fallback: "Couldn’t ask yabai about windows."))
        }
        guard let window = YabaiGeometry.matchWindow(pid: pid, axFrame: axFrame, windows: windows) else {
            return .failed("Yabai doesn’t see that window.")
        }
        if window.isNativeFullscreen {
            return .failed("Fullscreen windows can’t be moved.")
        }
        if window.isSticky {
            return .failed("That window is already on every Space.")
        }
        if !window.hasAXReference {
            return .failed("Yabai can’t move this window until its Space is visible.")
        }
        if window.space == destination {
            return .ignoredCurrent
        }
        let origin = window.space
        let moved = run(YabaiCommand.send(windowID: window.id, spaceIndex: destination))
        guard moved.status == 0 else {
            return .failed(YabaiSession.shortMessage(moved.stderr, fallback: "Couldn’t move that window."))
        }
        guard membershipIs(windowID: window.id, space: destination) else {
            return .failed("The window stayed on Space \(origin).")
        }
        if follow {
            _ = run(YabaiCommand.focus(spaceIndex: destination))
        }
        return .sent(SpaceSendSuccess(
            message: "\(appName) → Space \(destination)",
            windowID: window.id,
            originIndex: origin,
            destinationIndex: destination
        ))
    }

    /// Nil when the window’s space matches `destination` afterwards.
    func move(windowID: Int, toSpace destination: Int) -> String? {
        let moved = run(YabaiCommand.send(windowID: windowID, spaceIndex: destination))
        guard moved.status == 0 else {
            return YabaiSession.shortMessage(moved.stderr, fallback: "Couldn’t move that window.")
        }
        guard membershipIs(windowID: windowID, space: destination) else {
            return "The window did not change Space."
        }
        return nil
    }

    private func membershipIs(windowID: Int, space: Int) -> Bool {
        for _ in 0..<6 {
            let reply = run(YabaiCommand.queryWindow(windowID))
            if reply.status == 0,
               let windows = YabaiJSON.windows(from: reply.stdout),
               windows.contains(where: { $0.id == windowID && $0.space == space }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
        return false
    }

    static func shortMessage(_ stderr: String, fallback: String) -> String {
        let line = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { String($0) } ?? ""
        guard !line.isEmpty else { return fallback }
        if line.localizedCaseInsensitiveContains("could not locate the window") {
            return "Load yabai’s scripting addition: sudo yabai --load-sa"
        }
        if line.count <= 90 { return line }
        return String(line.prefix(87)) + "…"
    }
}

private final class YabaiDataBox: @unchecked Sendable {
    var data = Data()
}

enum YabaiProcess {
    static func run(binary: String, arguments: [String]) -> YabaiReply {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return YabaiReply(status: 1, stdout: "", stderr: error.localizedDescription)
        }
        let group = DispatchGroup()
        let outBox = YabaiDataBox()
        let errBox = YabaiDataBox()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        let outData = outBox.data
        let errData = errBox.data
        process.waitUntilExit()
        return YabaiReply(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

@MainActor
protocol SpaceSending: AnyObject {
    func availability() -> YabaiAvailability
    func chips(screenFrame: CGRect, primaryTop: CGFloat) -> [SpaceChip]
    func send(pid: pid_t, axFrame: CGRect?, appName: String, toSpace index: Int, follow: Bool) -> SpaceSendOutcome
    func move(windowID: Int, toSpace index: Int) -> String?
}

@MainActor
final class YabaiLiveClient: SpaceSending {
    private let binary: String?
    private let session: YabaiSession

    init() {
        let binary = YabaiBinary.resolve()
        self.binary = binary
        if let binary {
            session = YabaiSession { YabaiProcess.run(binary: binary, arguments: $0) }
        } else {
            session = YabaiSession { _ in
                YabaiReply(status: 1, stdout: "", stderr: "yabai isn’t installed.")
            }
        }
    }

    func availability() -> YabaiAvailability {
        session.availability(binaryFound: binary != nil)
    }

    func chips(screenFrame: CGRect, primaryTop: CGFloat) -> [SpaceChip] {
        guard binary != nil else { return [] }
        return session.chips(screenFrame: screenFrame, primaryTop: primaryTop)
    }

    func send(pid: pid_t, axFrame: CGRect?, appName: String, toSpace index: Int, follow: Bool) -> SpaceSendOutcome {
        session.send(pid: pid, axFrame: axFrame, appName: appName, toSpace: index, follow: follow)
    }

    func move(windowID: Int, toSpace index: Int) -> String? {
        session.move(windowID: windowID, toSpace: index)
    }
}
