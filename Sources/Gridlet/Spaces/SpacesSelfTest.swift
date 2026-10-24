import AppKit
import Foundation

/// `--spaces-self-test`: proves the Spaces plumbing end to end inside the real app
/// binary — read the display's Spaces, move a window it owns to another Space, read the
/// membership back, and put it home again. Run from the terminal; touches nothing of
/// the user's.
enum SpacesSelfTest {
    struct Result: Encodable {
        var available: Bool
        var displays: [Display]
        var windowID: Int?
        var originSpace: UInt64?
        var destinationSpace: UInt64?
        var moved: Bool?
        var observedAfterMove: UInt64?
        var restored: Bool?
        var observedAfterRestore: UInt64?
        var ok: Bool
        var note: String?
    }

    struct Display: Encodable {
        var identifier: String
        var spaces: [Space]
    }

    struct Space: Encodable {
        var index: Int
        var id: UInt64
        var isCurrent: Bool
    }

    @MainActor
    static func run() -> Result {
        var result = Result(
            available: SpaceBridge.isAvailable,
            displays: SpaceBridge.displays().map { display in
                Display(
                    identifier: display.identifier,
                    spaces: display.spaces.map { Space(index: $0.index, id: $0.id, isCurrent: $0.isCurrent) }
                )
            },
            ok: false
        )

        guard SpaceBridge.isAvailable else {
            result.note = "private Spaces API unavailable"
            return result
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            result.note = "no screen"
            return result
        }
        let displaySpaces = SpaceBridge.spaces(for: screen)
        guard let destination = displaySpaces.first(where: { !$0.isCurrent }) else {
            result.note = "this display has only one Space"
            return result
        }

        let window = NSWindow(
            contentRect: NSRect(x: 260, y: 260, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gridlet Spaces self-test"
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let windowID = CGWindowID(window.windowNumber)
        result.windowID = Int(windowID)
        result.destinationSpace = destination.id

        guard let origin = SpaceBridge.spaceID(forWindow: windowID) else {
            window.close()
            result.note = "window server did not report a Space for the test window"
            return result
        }
        result.originSpace = origin

        result.moved = SpaceBridge.move(window: windowID, to: destination.id)
        result.observedAfterMove = SpaceBridge.spaceID(forWindow: windowID)

        result.restored = SpaceBridge.move(window: windowID, to: origin)
        result.observedAfterRestore = SpaceBridge.spaceID(forWindow: windowID)

        window.close()

        result.ok = result.moved == true
            && result.observedAfterMove == destination.id
            && result.restored == true
            && result.observedAfterRestore == origin
        if !result.ok {
            result.note = "move or restore did not take; window left on \(result.observedAfterRestore.map(String.init) ?? "unknown")"
        }
        return result
    }

    @MainActor
    static func runJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(run()), let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\": false, \"note\": \"could not encode result\"}"
        }
        return text
    }
}
