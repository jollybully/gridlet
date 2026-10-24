import AppKit
import Foundation

let args = CommandLine.arguments

if args.contains("--spaces-demo") {
    let index = args.firstIndex(of: "--spaces-demo").flatMap { idx in
        idx + 1 < args.count ? Int(args[idx + 1]) : nil
    } ?? 3
    // Marker first: a LaunchServices launch swallows stdout, so prove the flag arrived.
    let marker = "DEMO_FLAG args=" + CommandLine.arguments.joined(separator: " ") + "\n"
    if let data = marker.data(using: .utf8) {
        let url = URL(fileURLWithPath: SpacesDemo.logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    final class SpacesDemoDelegate: NSObject, NSApplicationDelegate {
        let index: Int
        init(index: Int) { self.index = index }
        func applicationDidFinishLaunching(_ notification: Notification) {
            Task { @MainActor in
                // Give the recorder a beat before the panel appears.
                try? await Task.sleep(nanoseconds: 900_000_000)
                SpacesDemo.run(spaceIndex: index)
            }
        }
    }
    let delegate = SpacesDemoDelegate(index: index)
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}

if args.contains("--spaces-self-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    print(SpacesSelfTest.runJSON())
    exit(0)
}

if args.contains("--diagnostics-json") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    print(Diagnostics.runJSON())
    exit(0)
}

if let idx = args.firstIndex(of: "--header-alignment-json"), idx + 1 < args.count {
    let path = args[idx + 1]
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    final class HeaderAlignmentDelegate: NSObject, NSApplicationDelegate {
        let path: String
        init(path: String) { self.path = path }
        func applicationDidFinishLaunching(_ notification: Notification) {
            Task { @MainActor in
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let controller = GridPanelController(screen: screen)
                let json = HeaderAlignmentDiagnostics.jsonString(controller: controller)
                do {
                    try json.write(toFile: path, atomically: true, encoding: .utf8)
                    exit(0)
                } catch {
                    fputs("header-alignment-json write failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
    }
    let delegate = HeaderAlignmentDelegate(path: path)
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}

if let idx = args.firstIndex(of: "--ui-snapshot"), idx + 1 < args.count {
    let path = args[idx + 1]
    var appearance: String?
    var state: String?
    var screen = "panel"
    if let aidx = args.firstIndex(of: "--snapshot-appearance"), aidx + 1 < args.count {
        appearance = args[aidx + 1]
    }
    if let sidx = args.firstIndex(of: "--snapshot-state"), sidx + 1 < args.count {
        state = args[sidx + 1]
    }
    if let pidx = args.firstIndex(of: "--snapshot-screen"), pidx + 1 < args.count {
        screen = args[pidx + 1]
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    final class SnapshotDelegate: NSObject, NSApplicationDelegate {
        let path: String
        let appearance: String?
        let state: String?
        let screen: String
        init(path: String, appearance: String?, state: String?, screen: String) {
            self.path = path
            self.appearance = appearance
            self.state = state
            self.screen = screen
        }
        func applicationDidFinishLaunching(_ notification: Notification) {
            Task { @MainActor in
                let code: Int
                switch screen.lowercased() {
                case "settings":
                    code = UISnapshot.captureSettingsPNG(to: path, appearanceName: appearance)
                case "permission":
                    code = UISnapshot.capturePermissionPNG(to: path, appearanceName: appearance)
                default:
                    code = UISnapshot.capturePanelPNG(to: path, appearanceName: appearance, state: state)
                }
                exit(Int32(code))
            }
        }
    }
    let snapshotDelegate = SnapshotDelegate(path: path, appearance: appearance, state: state, screen: screen)
    app.delegate = snapshotDelegate
    withExtendedLifetime(snapshotDelegate) {
        app.run()
    }
}

if let idx = args.firstIndex(of: "--smoke-test-target-pid"), idx + 1 < args.count,
   let pid = pid_t(args[idx + 1]) {
    var sel = "8,8,0,0,7,7"
    if let sidx = args.firstIndex(of: "--selection"), sidx + 1 < args.count {
        sel = args[sidx + 1]
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let code = Diagnostics.smokeTest(pid: pid, selectionString: sel)
    exit(Int32(code))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(Int32(CommandLine.argc), CommandLine.unsafeArgv)
