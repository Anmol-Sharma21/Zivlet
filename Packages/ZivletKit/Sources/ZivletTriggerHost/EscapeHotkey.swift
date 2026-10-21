import Carbon.HIToolbox

/// Esc closes the wheel while it is visible, without Input Monitoring (03a §1.8, spike P-T3): a Carbon hot key that
/// exists only between show and hide. The key is consumed, so Finder's drag continues.
final class EscapeHotkey {
    var onPress: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isRegistered: Bool { hotKey != nil }

    /// False when the system refuses the key; the caller logs it and the other cancel paths still work.
    @discardableResult
    func register() -> Bool {
        guard hotKey == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), escapePressed, 1, &spec, context, &handler) == noErr
        else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5354_534D), id: 1)  // "STSM"
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            removeHandler()
            return false
        }
        hotKey = ref
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        removeHandler()
    }

    private func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

/// Carbon delivers hot keys on the main run loop. The context travels as an address because raw pointers are not
/// `Sendable`.
private nonisolated func escapePressed(
    _ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    let address = UInt(bitPattern: context)
    guard address != 0 else { return OSStatus(eventNotHandledErr) }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<EscapeHotkey>.fromOpaque(pointer).takeUnretainedValue().onPress()
    }
    return noErr
}
