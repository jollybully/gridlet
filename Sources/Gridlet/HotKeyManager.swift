import Carbon
import Foundation

enum HotKeyRegistrationError: Error, Equatable {
    case registrationFailed(OSStatus)
    case invalidBinding
    case handlerInstallFailed(OSStatus)
}

final class HotKeyManager: @unchecked Sendable {
    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: Handler?
    private(set) var currentBinding: HotKeyBinding?
    private(set) var lastRegistrationError: HotKeyRegistrationError?

    var isRegistered: Bool { hotKeyRef != nil }

    /// Unit-test hook: return non-`noErr` to simulate Carbon registration failure without a real OS conflict.
    var testRegisterEventHotKey: ((HotKeyBinding) -> OSStatus)?

    static let shared = HotKeyManager()

    private init() {}

    init(testIsolated: Bool) {
        guard testIsolated else { fatalError("use HotKeyManager(testIsolated: true) in tests only") }
    }

    func register(binding: HotKeyBinding, handler: @escaping Handler) throws {
        guard binding.isValidGlobal else {
            throw HotKeyRegistrationError.invalidBinding
        }

        if binding == currentBinding, hotKeyRef != nil {
            self.handler = handler
            lastRegistrationError = nil
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x47524C54), id: UInt32(1))
        var candidateRef: EventHotKeyRef?
        let status: OSStatus
        if let hook = testRegisterEventHotKey {
            status = hook(binding)
        } else {
            status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &candidateRef
            )
        }
        guard status == noErr, let candidateRef else {
            lastRegistrationError = .registrationFailed(status)
            throw HotKeyRegistrationError.registrationFailed(status)
        }

        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData -> OSStatus in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    var hotKeyID = EventHotKeyID()
                    let err = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    if err == noErr {
                        DispatchQueue.main.async {
                            Task { @MainActor in manager.handler?() }
                        }
                    }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard installStatus == noErr else {
                UnregisterEventHotKey(candidateRef)
                lastRegistrationError = .handlerInstallFailed(installStatus)
                throw HotKeyRegistrationError.handlerInstallFailed(installStatus)
            }
        }

        if let oldRef = hotKeyRef {
            UnregisterEventHotKey(oldRef)
        }

        hotKeyRef = candidateRef
        currentBinding = binding
        self.handler = handler
        lastRegistrationError = nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentBinding = nil
        handler = nil
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

/// Separate hotkey ID for unit tests that must not disturb the shared manager binding.
final class HotKeyProbe {
    private var ref: EventHotKeyRef?

    func tryRegister(binding: HotKeyBinding, id: UInt32 = 99) -> OSStatus {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x47524C50), id: id)
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &candidate
        )
        if status == noErr {
            ref = candidate
        }
        return status
    }

    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
    }
}
