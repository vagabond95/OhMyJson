//
//  HotKeyManager.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

class HotKeyManager {
    static let shared = HotKeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onHotKeyPressed: (() -> Void)?
    private var currentCombo: HotKeyCombo = .default
    var isEnabled: Bool = true

    // Throttle mechanism
    private var lastHotKeyTime: Date?
    private let throttleInterval: TimeInterval = 0.5 // 500ms

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotKeyChanged),
            name: .hotKeyChanged,
            object: nil
        )
    }

    deinit {
        stop()
    }

    @objc private func hotKeyChanged(_ notification: Notification) {
        if let combo = notification.object as? HotKeyCombo {
            currentCombo = combo
        }
    }

    func start(combo: HotKeyCombo, handler: @escaping () -> Void) {
        stop()

        self.currentCombo = combo
        self.onHotKeyPressed = handler

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Please grant Accessibility permissions.")
            requestAccessibilityPermissions()
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("HotKey monitoring started: \(combo.displayString)")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        onHotKeyPressed = nil

        print("HotKey monitoring stopped")
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        var carbonModifiers: UInt32 = 0
        if flags.contains(.maskCommand) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { carbonModifiers |= UInt32(controlKey) }

        if keyCode == currentCombo.keyCode && carbonModifiers == currentCombo.modifiers {
            guard isEnabled else {
                return Unmanaged.passRetained(event)
            }
            // Throttle check: prevent rapid consecutive hotkey triggers
            if let lastTime = lastHotKeyTime {
                let elapsed = Date().timeIntervalSince(lastTime)
                if elapsed < throttleInterval {
                    // Too soon, ignore this hotkey press
                    return Unmanaged.passRetained(event)
                }
            }

            // Update last trigger time
            lastHotKeyTime = Date()

            // Trigger handler
            DispatchQueue.main.async { [weak self] in
                self?.onHotKeyPressed?()
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    func updateHotKey(_ combo: HotKeyCombo) {
        currentCombo = combo
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            print("Please grant Accessibility permissions in System Settings > Privacy & Security > Accessibility")
        }
    }

    var isRunning: Bool {
        eventTap != nil
    }
}
#endif
