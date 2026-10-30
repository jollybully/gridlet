import AppKit

/// Moves a window this process owns to another Space and back. Writes JSON to `path`.
/// Does not start yabai and does not touch any other window.
enum YabaiProbe {
    struct Report: Encodable {
        var ok: Bool
        var skipped: String?
        var windowID: Int?
        var fromSpace: Int?
        var toSpace: Int?
        var observedSpace: Int?
        var restored: Bool?
        var message: String?
    }

    @MainActor
    static func run(writingTo path: String) -> Int32 {
        let binary = YabaiBinary.resolve()
        let session = YabaiSession { args in
            guard let binary else {
                return YabaiReply(status: 1, stdout: "", stderr: "yabai isn’t installed.")
            }
            return YabaiProcess.run(binary: binary, arguments: args)
        }

        switch session.availability(binaryFound: binary != nil) {
        case .notInstalled:
            return write(Report(ok: true, skipped: "not-installed"), to: path)
        case .notRunning:
            return write(Report(ok: true, skipped: "socket"), to: path)
        case .unreachable:
            return write(Report(ok: true, skipped: "unreachable"), to: path)
        case .available:
            break
        }

        guard let spaces = YabaiJSON.spaces(from: session.run(YabaiCommand.querySpaces()).stdout) else {
            return write(Report(ok: true, skipped: "socket"), to: path)
        }
        let desktops = spaces.filter { !$0.isNativeFullscreen }
        guard desktops.count >= 2, let current = desktops.first(where: \.isVisible) ?? desktops.first else {
            return write(Report(ok: true, skipped: "single-space"), to: path)
        }
        guard let destination = desktops.first(where: { $0.index != current.index }) else {
            return write(Report(ok: true, skipped: "single-space"), to: path)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 240, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gridlet Yabai Probe"
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let pid = ProcessInfo.processInfo.processIdentifier
        var found: YabaiWindow?
        for _ in 0..<20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let reply = session.run(YabaiCommand.queryWindows())
            let windows = YabaiJSON.windows(from: reply.stdout) ?? []
            if let match = windows.first(where: { $0.pid == Int(pid) && !$0.isSticky }) {
                found = match
                break
            }
        }

        guard let mine = found else {
            window.orderOut(nil)
            return write(Report(ok: false, message: "yabai did not list the probe window"), to: path, status: 1)
        }

        let moveError = session.move(windowID: mine.id, toSpace: destination.index)
        var observed: Int?
        if moveError == nil {
            let reply = session.run(YabaiCommand.queryWindow(mine.id))
            observed = YabaiJSON.windows(from: reply.stdout)?.first?.space
        }
        let restoreError = session.move(windowID: mine.id, toSpace: mine.space)
        window.orderOut(nil)
        let restoredOK = restoreError == nil

        if let moveError {
            return write(Report(
                ok: false,
                windowID: mine.id,
                fromSpace: mine.space,
                toSpace: destination.index,
                restored: restoredOK,
                message: moveError
            ), to: path, status: 1)
        }
        let report = Report(
            ok: restoredOK && observed == destination.index,
            windowID: mine.id,
            fromSpace: mine.space,
            toSpace: destination.index,
            observedSpace: observed,
            restored: restoredOK,
            message: restoredOK ? nil : "restore failed"
        )
        return write(report, to: path, status: report.ok ? 0 : 1)
    }

    private static func write(_ report: Report, to path: String, status: Int32 = 0) -> Int32 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            fputs("yabai-probe write failed: \(error)\n", stderr)
            return 1
        }
        return status
    }
}
