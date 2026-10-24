import AppKit
import Foundation

/// `--apply-preset <preset>`: applies a gapped preset frame to the frontmost window.
/// A dev tool — used to photograph what the current gap/grid settings actually do, since
/// this process cannot synthesise a drag.
///
/// Presets: left, right, top, bottom, max, q1…q4.
@MainActor
enum PresetProbe {
    static let logPath = "/tmp/gridlet-preset.log"

    private static func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func selection(named preset: String, rows: Int, columns: Int) -> GridSelection? {
        let midRow = (rows - 1) / 2
        let midCol = (columns - 1) / 2
        switch preset {
        case "left": return GridSelection(rowStart: 0, rowEnd: rows - 1, colStart: 0, colEnd: midCol)
        case "right": return GridSelection(rowStart: 0, rowEnd: rows - 1, colStart: midCol + 1, colEnd: columns - 1)
        case "top": return GridSelection(rowStart: 0, rowEnd: midRow, colStart: 0, colEnd: columns - 1)
        case "bottom": return GridSelection(rowStart: midRow + 1, rowEnd: rows - 1, colStart: 0, colEnd: columns - 1)
        case "max": return GridSelection(rowStart: 0, rowEnd: rows - 1, colStart: 0, colEnd: columns - 1)
        case "q1": return GridSelection(rowStart: 0, rowEnd: midRow, colStart: 0, colEnd: midCol)
        case "q2": return GridSelection(rowStart: 0, rowEnd: midRow, colStart: midCol + 1, colEnd: columns - 1)
        case "q3": return GridSelection(rowStart: midRow + 1, rowEnd: rows - 1, colStart: 0, colEnd: midCol)
        case "q4": return GridSelection(rowStart: midRow + 1, rowEnd: rows - 1, colStart: midCol + 1, colEnd: columns - 1)
        default: return nil
        }
    }

    static func run(preset: String) {
        try? FileManager.default.removeItem(atPath: logPath)
        guard WindowTargetResolver.isTrusted() else {
            log("ERROR accessibility permission required")
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let settings = GridSettings.load()
        let grid = settings.grid(for: GridSettings.displayKey(for: screen))
        guard let selection = selection(named: preset, rows: grid.rows, columns: grid.columns) else {
            log("ERROR unknown preset \(preset)")
            return
        }
        guard let target = WindowTargetResolver.captureFrontmostTarget(excludingGridlet: true) else {
            log("ERROR no focused foreign window")
            return
        }
        let cocoa = ScreenGeometry.cocoaFrame(
            for: selection,
            rows: grid.rows,
            columns: grid.columns,
            visibleFrame: screen.visibleFrame,
            gap: CGFloat(settings.gap)
        )
        guard let cocoa else {
            log("ERROR no frame")
            return
        }
        let primaryTop = ScreenGeometry.primaryTopY(screens: NSScreen.screens)
        let axFrame = ScreenGeometry.cocoaRectToAX(cocoa, primaryTopY: primaryTop)
        let name = WindowTargetResolver.appDisplayName(for: target)
        do {
            try WindowTargetResolver.applyFrame(target, axFrame: axFrame)
            log("applied \(preset) to \(name): grid \(grid.rows)x\(grid.columns) gap \(settings.gap) -> \(axFrame)")
        } catch {
            log("ERROR \(error.localizedDescription)")
        }
    }
}
