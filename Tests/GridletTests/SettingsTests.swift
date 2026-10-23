import AppKit
import XCTest
@testable import Gridlet

final class SettingsTests: XCTestCase {
    func testGridClamp() {
        XCTAssertEqual(GridSettings.clampGrid(0), 1)
        XCTAssertEqual(GridSettings.clampGrid(13), 12)
        XCTAssertEqual(GridSettings.clampGrid(8), 8)
    }

    func testPersistenceRoundTrip() {
        let ud = UserDefaults(suiteName: "GridletTests")!
        ud.removePersistentDomain(forName: "GridletTests")
        var snap = GridSettings.Snapshot()
        snap.rows = 5
        snap.columns = 6
        snap.showPanelHotKey = HotKeyBinding(keyCode: 1, modifiers: UInt32(cmdKey))
        snap.keepPanelOpen = true
        GridSettings.save(snap, to: ud)
        let loaded = GridSettings.load(from: ud)
        XCTAssertEqual(loaded.rows, 5)
        XCTAssertEqual(loaded.columns, 6)
        XCTAssertTrue(loaded.keepPanelOpen)
        XCTAssertEqual(loaded.showPanelHotKey.keyCode, 1)
        XCTAssertEqual(loaded.showPanelHotKey.modifiers, UInt32(cmdKey))
    }

    func testHotKeyDisplay() {
        let s = HotKeyDisplay.string(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        XCTAssertTrue(s.contains("Space"))
    }

    func testCarbonModifierGlobalsMatchCarbonModule() {
        XCTAssertEqual(controlKey, 4096)
        XCTAssertEqual(optionKey, 2048)
        XCTAssertEqual(shiftKey, 512)
        XCTAssertEqual(cmdKey, 256)
    }

    func testNSEventModifierFlagsCarbonMapping() {
        let flags = NSEvent.ModifierFlags([.control, .option, .shift, .command])
        XCTAssertEqual(flags.carbonFlags, UInt32(controlKey | optionKey | shiftKey | cmdKey))
    }

    func testLegacyCompleteJSONMigrationIgnoresPresets() throws {
        let json = """
        {"rows":9,"columns":10,"keepPanelOpen":true,"showPreview":false,
        "showPanelHotKey":{"keyCode":49,"modifiers":6144},
        "launchAtLogin":true,
        "presets":[{"id":"00000000-0000-0000-0000-000000000001","name":"Half","rows":8,"columns":8,
        "selection":{"rowStart":0,"rowEnd":7,"colStart":0,"colEnd":3}}]}
        """
        let data = Data(json.utf8)
        let migrated = GridSettings.migrate(from: data)
        XCTAssertEqual(migrated.rows, 9)
        XCTAssertEqual(migrated.columns, 10)
        XCTAssertTrue(migrated.keepPanelOpen)
        XCTAssertFalse(migrated.showPreview)
        XCTAssertTrue(migrated.launchAtLogin)
        XCTAssertEqual(migrated.showPanelHotKey.keyCode, 49)
        XCTAssertEqual(migrated.showPanelHotKey.modifiers, 6144)

        let ud = UserDefaults(suiteName: "GridletTestsLegacyComplete")!
        ud.removePersistentDomain(forName: "GridletTestsLegacyComplete")
        GridSettings.save(migrated, to: ud)
        let encoded = ud.data(forKey: GridSettings.defaultsKey)!
        let encodedString = String(data: encoded, encoding: .utf8)!
        XCTAssertFalse(encodedString.contains("presets"))
        XCTAssertFalse(encodedString.contains("Half"))
    }

    func testLegacySparseJSONMigration() throws {
        let json = "{\"rows\":5}"
        let migrated = GridSettings.migrate(from: Data(json.utf8))
        XCTAssertEqual(migrated.rows, 5)
        XCTAssertEqual(migrated.columns, 8)
        XCTAssertFalse(migrated.keepPanelOpen)
    }

    @MainActor
    func testSettingsWindowIncludesActivationHotKeyRecorder() {
        let controller = SettingsWindowController.shared
        XCTAssertNotNil(controller.globalHotKeyRecorder.superview)
        controller.globalHotKeyRecorder.binding = HotKeyBinding(keyCode: 36, modifiers: UInt32(cmdKey | controlKey))
        XCTAssertEqual(controller.globalHotKeyRecorder.binding.displayString, HotKeyDisplay.string(keyCode: 36, modifiers: UInt32(cmdKey | controlKey)))
    }

    @MainActor
    func testSettingsWindowFitsCompactLayout() {
        let controller = SettingsWindowController.shared
        guard let window = controller.window else {
            XCTFail("no settings window")
            return
        }
        window.layoutIfNeeded()
        let size = window.contentView?.bounds.size ?? .zero
        XCTAssertEqual(size.width, 340, accuracy: 1)
        XCTAssertGreaterThanOrEqual(size.height, 300)
        XCTAssertLessThanOrEqual(size.height, 420)
    }

    @MainActor
    func testSettingsWindowHasNoNestedPanelChrome() {
        let controller = SettingsWindowController.shared
        guard let root = controller.contentRootForTests else {
            XCTFail("no content root")
            return
        }
        XCTAssertFalse(StandardWindowLayout.containsPanelChrome(in: root))
    }

    @MainActor
    func testSettingsControlsFitBelowTitlebar() {
        let controller = SettingsWindowController.shared
        guard let window = controller.window, let content = controller.contentRootForTests else {
            XCTFail("no window")
            return
        }
        window.layoutIfNeeded()
        let recorder = controller.globalHotKeyRecorder
        XCTAssertGreaterThanOrEqual(recorder.frame.minY, 0)
        XCTAssertLessThanOrEqual(recorder.frame.maxY, content.bounds.height + 0.5)
        XCTAssertGreaterThan(window.frame.height, content.bounds.height + 20, "titled window includes title bar above content")
    }

    func testSavedSettingsHasNoPresetOrShortcutUIFields() {
        let ud = UserDefaults(suiteName: "GridletTestsEncode")!
        ud.removePersistentDomain(forName: "GridletTestsEncode")
        GridSettings.save(GridSettings.Snapshot(), to: ud)
        let raw = String(data: ud.data(forKey: GridSettings.defaultsKey)!, encoding: .utf8)!
        XCTAssertFalse(raw.contains("presets"))
        XCTAssertFalse(raw.contains("localKeyCode"))
    }
}
