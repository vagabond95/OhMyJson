//
//  AppSettings.swift
//  OhMyJson
//

import Foundation
import SwiftUI
import Carbon.HIToolbox


struct HotKeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultOpen = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    // Legacy support
    static let `default` = defaultOpen

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let keyCodeMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        return keyCodeMap[keyCode]
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let openHotKeyKey = "openHotKeyCombo"
    private let launchAtLoginKey = "launchAtLogin"
    private let jsonIndentKey = "jsonIndent"
    private let isDarkModeKey = "isDarkMode"
    private let hasSeenOnboardingKey = "hasSeenOnboarding"

    // Legacy key for migration
    private let legacyHotKeyKey = "hotKeyCombo"

    @Published var openHotKeyCombo: HotKeyCombo {
        didSet {
            saveOpenHotKey()
            NotificationCenter.default.post(name: .openHotKeyChanged, object: openHotKeyCombo)
        }
    }

    // Legacy computed property for compatibility
    var hotKeyCombo: HotKeyCombo {
        get { openHotKeyCombo }
        set { openHotKeyCombo = newValue }
    }

    @Published var jsonIndent: Int {
        didSet {
            UserDefaults.standard.set(jsonIndent, forKey: jsonIndentKey)
            NotificationCenter.default.post(name: .jsonIndentChanged, object: jsonIndent)
        }
    }

    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: isDarkModeKey)
        }
    }

    @Published var hasSeenOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenOnboarding, forKey: hasSeenOnboardingKey)
        }
    }

    var currentTheme: AppTheme {
        isDarkMode ? DarkTheme() : LightTheme()
    }

    func toggleTheme() {
        isDarkMode.toggle()
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
            updateLaunchAtLogin()
        }
    }

    private init() {
        // Load Open HotKey (with legacy migration)
        if let data = UserDefaults.standard.data(forKey: openHotKeyKey),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            self.openHotKeyCombo = combo
        } else if let data = UserDefaults.standard.data(forKey: legacyHotKeyKey),
                  let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            // Migrate from legacy key
            self.openHotKeyCombo = combo
        } else {
            self.openHotKeyCombo = .defaultOpen
        }

        // Load JSON Indent
        let savedIndent = UserDefaults.standard.integer(forKey: jsonIndentKey)
        self.jsonIndent = (savedIndent == 2) ? 2 : 4

        self.launchAtLogin = UserDefaults.standard.bool(forKey: launchAtLoginKey)

        // Load Dark Mode (default: true)
        if UserDefaults.standard.object(forKey: isDarkModeKey) != nil {
            self.isDarkMode = UserDefaults.standard.bool(forKey: isDarkModeKey)
        } else {
            self.isDarkMode = true
        }

        // Load Onboarding flag (default: false)
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: hasSeenOnboardingKey)
    }

    private func saveOpenHotKey() {
        if let data = try? JSONEncoder().encode(openHotKeyCombo) {
            UserDefaults.standard.set(data, forKey: openHotKeyKey)
        }
    }

    private func updateLaunchAtLogin() {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
        #endif
    }

    func resetToDefaults() {
        openHotKeyCombo = .defaultOpen
        jsonIndent = 4
        launchAtLogin = false
        isDarkMode = true
    }
}

extension Notification.Name {
    static let openHotKeyChanged = Notification.Name("openHotKeyChanged")
    static let jsonIndentChanged = Notification.Name("jsonIndentChanged")
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
    // Legacy support
    static let hotKeyChanged = Notification.Name("openHotKeyChanged")
}

#if os(macOS)
import ServiceManagement
#endif
