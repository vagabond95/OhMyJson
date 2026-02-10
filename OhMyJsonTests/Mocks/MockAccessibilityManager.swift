//
//  MockAccessibilityManager.swift
//  OhMyJsonTests
//

#if os(macOS)
@testable import OhMyJson

final class MockAccessibilityManager: AccessibilityManagerProtocol {
    var isAccessibilityGranted: Bool = false

    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0
    var promptCallCount = 0

    func startMonitoring() {
        startMonitoringCallCount += 1
    }

    func stopMonitoring() {
        stopMonitoringCallCount += 1
    }

    func promptAccessibilityPermission() {
        promptCallCount += 1
    }

    func openSystemSettingsAccessibility() {
        // no-op in tests
    }
}
#endif
