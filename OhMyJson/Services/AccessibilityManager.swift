//
//  AccessibilityManager.swift
//  OhMyJson
//

#if os(macOS)
import AppKit
import Combine

class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    @Published var isAccessibilityGranted: Bool = false

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 0.3

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
        NSWorkspace.shared.open(url)
    }
}
#endif
