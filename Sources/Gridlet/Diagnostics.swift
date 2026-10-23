import AppKit
import Foundation

enum Diagnostics {
    struct Report: Encodable {
        var axTrusted: Bool
        var bundleID: String
        var screens: [[String: Double]]
        var settings: GridSettings.Snapshot
        var hotkeyRegistered: Bool
        var hotkeyBinding: String
    }

    struct SmokeResult: Encodable {
        var ok: Bool
        var requestedAX: [String: Double]
        var actualAX: [String: Double]?
        var message: String?
    }

    static func runJSON() -> String {
        let screens = NSScreen.screens.map { s -> [String: Double] in
            [
                "frameX": s.frame.origin.x,
                "frameY": s.frame.origin.y,
                "frameW": s.frame.size.width,
                "frameH": s.frame.size.height,
                "visibleX": s.visibleFrame.origin.x,
                "visibleY": s.visibleFrame.origin.y,
                "visibleW": s.visibleFrame.size.width,
                "visibleH": s.visibleFrame.size.height,
            ]
        }
        let report = Report(
            axTrusted: WindowTargetResolver.isTrusted(),
            bundleID: Bundle.main.bundleIdentifier ?? "org.gridlet.Gridlet",
            screens: screens,
            settings: GridSettings.load(),
            hotkeyRegistered: HotKeyManager.shared.currentBinding != nil,
            hotkeyBinding: GridSettings.load().showPanelHotKey.displayString
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(report), let str = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"encode failed\"}"
        }
        return str
    }

    enum SelectionParseError: Error, Equatable, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self {
            case .invalid(let msg): return msg
            }
        }
    }

    static func parseSelection(_ selectionString: String) -> Result<(rows: Int, cols: Int, sel: GridSelection, screenIdx: Int), SelectionParseError> {
        let trimmed = selectionString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.invalid("selection is empty"))
        }

        let parts = trimmed.split(separator: "@", maxSplits: 1).map(String.init)
        let screenIdx: Int
        if parts.count > 1 {
            let screenToken = parts[1].trimmingCharacters(in: .whitespaces)
            if screenToken.isEmpty {
                return .failure(.invalid("screen index is empty"))
            }
            guard let idx = Int(screenToken), idx >= 0 else {
                return .failure(.invalid("screen index must be a non-negative integer"))
            }
            screenIdx = idx
        } else {
            screenIdx = 0
        }

        let selTokens = parts[0].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard selTokens.count == 6 else {
            return .failure(.invalid("selection must be rows,cols,r0,c0,r1,c1"))
        }
        var ints: [Int] = []
        for token in selTokens {
            guard let v = Int(token), v >= 0 else {
                return .failure(.invalid("selection values must be non-negative integers"))
            }
            ints.append(v)
        }

        let rows = ints[0]
        let cols = ints[1]
        guard rows >= 1, cols >= 1 else {
            return .failure(.invalid("rows and columns must be at least 1"))
        }
        let sel = GridSelection(rowStart: ints[2], rowEnd: ints[4], colStart: ints[3], colEnd: ints[5])
        guard let norm = sel.normalized(rows: rows, columns: cols) else {
            return .failure(.invalid("selection could not be normalized"))
        }
        return .success((rows, cols, norm, screenIdx))
    }

    static func smokeTest(pid: pid_t, selectionString: String) -> Int {
        guard WindowTargetResolver.isTrusted() else {
            fputs("AX not trusted\n", stderr)
            return 2
        }

        let parsed: (rows: Int, cols: Int, sel: GridSelection, screenIdx: Int)
        switch parseSelection(selectionString) {
        case .failure(let err):
            fputs("\(err.description)\n", stderr)
            return 4
        case .success(let value):
            parsed = value
        }

        guard let target = WindowTargetResolver.target(pid: pid) else {
            fputs("No valid target for pid \(pid)\n", stderr)
            return 3
        }

        let screens = NSScreen.screens
        guard parsed.screenIdx < screens.count else {
            fputs("screen index \(parsed.screenIdx) out of range\n", stderr)
            return 5
        }
        let screen = screens[parsed.screenIdx]
        let vf = screen.visibleFrame
        let primaryTop = ScreenGeometry.primaryTopY(screens: screens)
        guard let cocoa = ScreenGeometry.cocoaFrame(
            for: parsed.sel,
            rows: parsed.rows,
            columns: parsed.cols,
            visibleFrame: vf
        ) else {
            fputs("could not compute cocoa frame\n", stderr)
            return 6
        }
        let ax = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTop)

        let before = WindowTargetResolver.readBackAXFrame(target)
        do {
            try WindowTargetResolver.applyFrame(target, axFrame: ax)
        } catch {
            let result = SmokeResult(
                ok: false,
                requestedAX: axDict(ax),
                actualAX: before.map(axDict),
                message: error.localizedDescription
            )
            printSmokeJSON(result)
            fputs("\(error.localizedDescription)\n", stderr)
            return 8
        }

        let actual = WindowTargetResolver.readBackAXFrame(target)
        let ok = actual != nil
        let result = SmokeResult(
            ok: ok,
            requestedAX: axDict(ax),
            actualAX: actual.map(axDict),
            message: ok ? nil : "readback failed"
        )
        printSmokeJSON(result)
        if ok {
            print("OK applied (see JSON for requested vs actual frames)")
            return 0
        }
        return 8
    }

    private static func axDict(_ rect: CGRect) -> [String: Double] {
        [
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "w": Double(rect.size.width),
            "h": Double(rect.size.height),
        ]
    }

    private static func printSmokeJSON(_ result: SmokeResult) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(result), let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
