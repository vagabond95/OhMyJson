//
//  AccessibilityManager.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import Combine
import Observation

@Observable
class AccessibilityManager: AccessibilityManagerProtocol {
    static let shared = AccessibilityManager()

    @ObservationIgnored let accessibilityChanged = PassthroughSubject<Bool, Never>()

    var isAccessibilityGranted: Bool = false {
        didSet { accessibilityChanged.send(isAccessibilityGranted) }
    }

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = Timing.accessibilityPolling

    private init() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    func startMonitoring() {
        pollingTimer?.invalidate()
        isAccessibilityGranted = AXIsProcessTrusted()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            let granted = AXIsProcessTrusted()
            if self?.isAccessibilityGranted != granted {
                self?.isAccessibilityGranted = granted
            }
        }
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func promptAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettingsAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if !NSWorkspace.shared.open(url) {
            // Fallback: open System Settings root if deep link fails
            if let fallback = URL(string: "x-apple.systempreferences:") {
                NSWorkspace.shared.open(fallback)
            }
        }
    }
}
#endif
