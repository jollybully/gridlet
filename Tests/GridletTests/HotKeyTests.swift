import XCTest
@testable import Gridlet

final class HotKeyTests: XCTestCase {
    /// Rare binding (Return + ⌃⌥) — not the app default show-panel shortcut.
    private let testBindingA = HotKeyBinding(keyCode: 36, modifiers: UInt32(controlKey | optionKey))
    private let testBindingB = HotKeyBinding(keyCode: 35, modifiers: UInt32(controlKey | optionKey))

    func testGlobalBindingValidation() {
        XCTAssertTrue(HotKeyBinding.defaultShowPanel.isValidGlobal)
        XCTAssertFalse(HotKeyBinding(keyCode: 49, modifiers: 0).isValidGlobal)
        XCTAssertFalse(HotKeyBinding(keyCode: 49, modifiers: UInt32(shiftKey)).isValidGlobal)
    }

    func testTransactionalRegistrationKeepsOldOnInvalidBinding() {
        let manager = HotKeyManager(testIsolated: true)
        defer { manager.unregister() }

        try? manager.register(binding: testBindingA) { }
        XCTAssertEqual(manager.currentBinding, testBindingA)

        do {
            try manager.register(binding: HotKeyBinding(keyCode: 49, modifiers: 0)) { }
            XCTFail("expected invalid binding error")
        } catch HotKeyRegistrationError.invalidBinding {
            XCTAssertEqual(manager.currentBinding, testBindingA)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTransactionalRegistrationKeepsOldOnSimulatedRegistrationFailure() {
        let manager = HotKeyManager(testIsolated: true)
        defer { manager.unregister() }

        var handlerACalls = 0
        try? manager.register(binding: testBindingA) {
            handlerACalls += 1
        }
        XCTAssertEqual(manager.currentBinding, testBindingA)

        manager.testRegisterEventHotKey = { _ in OSStatus(-9876) }
        do {
            try manager.register(binding: testBindingB) { }
            XCTFail("expected registration failure")
        } catch HotKeyRegistrationError.registrationFailed(let status) {
            XCTAssertEqual(status, OSStatus(-9876))
            XCTAssertEqual(manager.currentBinding, testBindingA)
            manager.testRegisterEventHotKey = nil
            try? manager.register(binding: testBindingA) {
                handlerACalls += 1
            }
            XCTAssertEqual(handlerACalls, 0)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSuccessfulReRegistrationReplacesBinding() {
        let manager = HotKeyManager(testIsolated: true)
        defer { manager.unregister() }

        try? manager.register(binding: testBindingA) { }
        try? manager.register(binding: testBindingB) { }
        XCTAssertEqual(manager.currentBinding, testBindingB)
    }

    func testProbeReserveShortcut() {
        let probe = HotKeyProbe()
        let binding = HotKeyBinding(keyCode: 36, modifiers: UInt32(controlKey | optionKey))
        XCTAssertEqual(probe.tryRegister(binding: binding), 0)
        probe.unregister()
    }

    func testShiftModifierRegistersWithCarbonValue() {
        let binding = HotKeyBinding(keyCode: 0, modifiers: UInt32(shiftKey | cmdKey))
        XCTAssertEqual(binding.modifiers, 768)
        XCTAssertTrue(binding.isValidGlobal)
    }
}
