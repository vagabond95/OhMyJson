//
//  HotKeyManager.swift
//  OhMyJson
//

#if os(macOS)
import Carbon.HIToolbox

class HotKeyManager: HotKeyManagerProtocol {
    static let shared = HotKeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var onHotKeyPressed: (() -> Void)?
    private var currentCombo: HotKeyCombo = .default
    var isEnabled: Bool = true

    // Throttle mechanism
    private var lastHotKeyTime: Date?
    private let throttleInterval: TimeInterval = Timing.hotKeyThrottle

    // FourCharCode signature for this app
    private static let signature: FourCharCode = {
        let chars: [UInt8] = [
            UInt8(ascii: "O"), UInt8(ascii: "M"), UInt8(ascii: "J"), UInt8(ascii: "N")
        ]
        return FourCharCode(chars[0]) << 24
             | FourCharCode(chars[1]) << 16
             | FourCharCode(chars[2]) << 8
             | FourCharCode(chars[3])
    }()

    private init() {}

    deinit {
        stop()
    }

    func start(combo: HotKeyCombo, handler: @escaping () -> Void) {
        stop()

        self.currentCombo = combo
        self.onHotKeyPressed = handler

        // Install Carbon event handler for kEventHotKeyPressed
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("Failed to install Carbon event handler: \(status)")
            return
        }

        // Register the hotkey with the OS
        registerHotKey()

        print("HotKey monitoring started: \(combo.displayString)")
    }

    func stop() {
        unregisterHotKey()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }

        onHotKeyPressed = nil

        print("HotKey monitoring stopped")
    }

    func updateHotKey(_ combo: HotKeyCombo) {
        let hadHandler = eventHandlerRef != nil
        currentCombo = combo

        if hadHandler {
            // Re-register with new combo (keep event handler alive)
            unregisterHotKey()
            registerHotKey()
        }
    }

    func suspend() {
        unregisterHotKey()
    }

    func resume() {
        // Only re-register if we have an active event handler (i.e. start() was called)
        guard eventHandlerRef != nil else { return }
        registerHotKey()
    }

    var isRunning: Bool {
        eventHandlerRef != nil
    }

    // MARK: - Private

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let carbonModifiers = carbonModifierFlags(from: currentCombo.modifiers)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            currentCombo.keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        if status == noErr {
            hotKeyRef = ref
        } else {
            print("Failed to register hotkey: \(status)")
        }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Convert from our Carbon modifier bitmask (cmdKey, optionKey, etc.) to
    /// the Carbon modifier format expected by RegisterEventHotKey.
    private func carbonModifierFlags(from modifiers: UInt32) -> UInt32 {
        var result: UInt32 = 0
        if modifiers & UInt32(cmdKey) != 0     { result |= UInt32(cmdKey) }
        if modifiers & UInt32(shiftKey) != 0   { result |= UInt32(shiftKey) }
        if modifiers & UInt32(optionKey) != 0  { result |= UInt32(optionKey) }
        if modifiers & UInt32(controlKey) != 0 { result |= UInt32(controlKey) }
        return result
    }

    fileprivate func handleHotKeyEvent() {
        guard isEnabled else { return }

        // Throttle check: prevent rapid consecutive hotkey triggers
        if let lastTime = lastHotKeyTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < throttleInterval {
                return
            }
        }

        lastHotKeyTime = Date()

        DispatchQueue.main.async { [weak self] in
            self?.onHotKeyPressed?()
        }
    }
}

// MARK: - Carbon Event Handler (free function)

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKeyEvent()

    return noErr
}
#endif
