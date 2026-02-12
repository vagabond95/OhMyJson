//
//  MockHotKeyManager.swift
//  OhMyJsonTests
//

#if os(macOS)
@testable import OhMyJson

final class MockHotKeyManager: HotKeyManagerProtocol {
    var isEnabled: Bool = true
    var isRunning: Bool = false

    var startCallCount = 0
    var stopCallCount = 0
    var suspendCallCount = 0
    var resumeCallCount = 0
    var lastCombo: HotKeyCombo?
    var lastHandler: (() -> Void)?

    func start(combo: HotKeyCombo, handler: @escaping () -> Void) {
        startCallCount += 1
        lastCombo = combo
        lastHandler = handler
        isRunning = true
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }

    func updateHotKey(_ combo: HotKeyCombo) {
        lastCombo = combo
    }

    func suspend() {
        suspendCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }
}
#endif
