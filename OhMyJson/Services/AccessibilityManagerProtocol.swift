//
//  AccessibilityManagerProtocol.swift
//  OhMyJson
//

#if os(macOS)
protocol AccessibilityManagerProtocol: AnyObject {
    var isAccessibilityGranted: Bool { get }
    func startMonitoring()
    func stopMonitoring()
    func promptAccessibilityPermission()
    func openSystemSettingsAccessibility()
}
#endif
