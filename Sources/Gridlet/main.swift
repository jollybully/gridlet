import AppKit
import Foundation

let args = CommandLine.arguments

if let idx = args.firstIndex(of: "--apply-preset"), idx + 1 < args.count {
    let preset = args[idx + 1]
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    final class PresetDelegate: NSObject, NSApplicationDelegate {
        let preset: String
        init(preset: String) { self.preset = preset }
        func applicationDidFinishLaunching(_ notification: Notification) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                PresetProbe.run(preset: preset)
                exit(0)
            }
        }
    }
    let delegate = PresetDelegate(preset: preset)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
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
