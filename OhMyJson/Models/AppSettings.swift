//
//  AppSettings.swift
//  OhMyJson
//

import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine
import Observation


// MARK: - ThemeMode

enum ThemeMode: Int, Codable, CaseIterable {
    case light = 0
    case dark = 1
}

// MARK: - HotKeyCombo

struct HotKeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultOpen = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_J),
        modifiers: UInt32(controlKey | optionKey)
    )

    // Legacy support
    static let `default` = defaultOpen

    // MARK: - Default Hotkeys for Customizable Actions

    static let defaultNewTab = HotKeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))
    static let defaultCloseTab = HotKeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey))
    static let defaultPreviousTab = HotKeyCombo(keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultNextTab = HotKeyCombo(keyCode: UInt32(kVK_ANSI_RightBracket), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultBeautifyMode = HotKeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey))
    static let defaultTreeMode = HotKeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey))
    static let defaultFindNext = HotKeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
    static let defaultFindPrevious = HotKeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey))

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

    var displayLabels: [String] {
        var labels: [String] = []
        if modifiers & UInt32(controlKey) != 0 { labels.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { labels.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { labels.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { labels.append("⌘") }
        if let keyString = keyCodeToString(keyCode) {
            labels.append(keyString)
        }
        return labels
    }

    var nsEventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// Key equivalent string for NSMenuItem (lowercase letter or symbol)
    var keyEquivalent: String {
        let keyEquivMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "a", UInt32(kVK_ANSI_B): "b", UInt32(kVK_ANSI_C): "c",
            UInt32(kVK_ANSI_D): "d", UInt32(kVK_ANSI_E): "e", UInt32(kVK_ANSI_F): "f",
            UInt32(kVK_ANSI_G): "g", UInt32(kVK_ANSI_H): "h", UInt32(kVK_ANSI_I): "i",
            UInt32(kVK_ANSI_J): "j", UInt32(kVK_ANSI_K): "k", UInt32(kVK_ANSI_L): "l",
            UInt32(kVK_ANSI_M): "m", UInt32(kVK_ANSI_N): "n", UInt32(kVK_ANSI_O): "o",
            UInt32(kVK_ANSI_P): "p", UInt32(kVK_ANSI_Q): "q", UInt32(kVK_ANSI_R): "r",
            UInt32(kVK_ANSI_S): "s", UInt32(kVK_ANSI_T): "t", UInt32(kVK_ANSI_U): "u",
            UInt32(kVK_ANSI_V): "v", UInt32(kVK_ANSI_W): "w", UInt32(kVK_ANSI_X): "x",
            UInt32(kVK_ANSI_Y): "y", UInt32(kVK_ANSI_Z): "z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        ]
        let base = keyEquivMap[keyCode] ?? ""
        // NSMenuItem uses uppercase keyEquivalent when Shift is included
        if modifiers & UInt32(shiftKey) != 0, base.count == 1, base.first?.isLetter == true {
            return base.uppercased()
        }
        return base
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

@Observable
class AppSettings {
    static let shared = AppSettings()

    // MARK: - Combine Publishers

    @ObservationIgnored let hotKeyChanged = PassthroughSubject<HotKeyCombo, Never>()
    @ObservationIgnored let jsonIndentChanged = PassthroughSubject<Int, Never>()

    // MARK: - UserDefaults Keys

    private let openHotKeyKey = "openHotKeyCombo"
    private let launchAtLoginKey = "launchAtLogin"
    private let jsonIndentKey = "jsonIndent"
    private let isDarkModeKey = "isDarkMode"
    private let themeModeKey = "themeMode"
    private let hasSeenOnboardingKey = "hasSeenOnboarding"
    private let dividerRatioKey = "dividerRatio"
    private let lastInstalledVersionKey = "lastInstalledVersion"
    private let defaultViewModeKey = "defaultViewMode"
    private let autoCheckForUpdatesKey = "autoCheckForUpdates"
    private let ignoreEscapeSequencesKey = "ignoreEscapeSequences"

    // Legacy key for migration
    private let legacyHotKeyKey = "hotKeyCombo"

    // MARK: - Open HotKey (Global)

    var openHotKeyCombo: HotKeyCombo {
        didSet {
            saveHotKey(openHotKeyCombo, forKey: openHotKeyKey)
            hotKeyChanged.send(openHotKeyCombo)
        }
    }

    // Legacy computed property for compatibility
    var hotKeyCombo: HotKeyCombo {
        get { openHotKeyCombo }
        set { openHotKeyCombo = newValue }
    }

    // MARK: - JSON Indent

    var jsonIndent: Int {
        didSet {
            UserDefaults.standard.set(jsonIndent, forKey: jsonIndentKey)
            jsonIndentChanged.send(jsonIndent)
        }
    }

    // MARK: - Theme Mode

    var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: themeModeKey)
            _cachedTheme = isDarkMode ? DarkTheme() : LightTheme()
        }
    }

    @ObservationIgnored
    private var _cachedTheme: AppTheme?

    var isDarkMode: Bool {
        switch themeMode {
        case .light: return false
        case .dark: return true
        }
    }

    var currentTheme: AppTheme {
        // Access themeMode to register observation tracking
        // (_cachedTheme is @ObservationIgnored, so without this,
        //  views reading currentTheme won't be notified on theme toggle)
        let _ = themeMode
        if let cached = _cachedTheme { return cached }
        let theme: AppTheme = isDarkMode ? DarkTheme() : LightTheme()
        _cachedTheme = theme
        return theme
    }

    var currentAppearance: NSAppearance? {
        let _ = themeMode
        return NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
    }

    func toggleTheme() {
        themeMode = isDarkMode ? .light : .dark
    }

    // MARK: - Default View Mode

    var defaultViewMode: ViewMode {
        didSet {
            UserDefaults.standard.set(defaultViewMode.rawValue, forKey: defaultViewModeKey)
        }
    }

    // MARK: - Other Settings

    var hasSeenOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenOnboarding, forKey: hasSeenOnboardingKey)
        }
    }

    var dividerRatio: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(dividerRatio), forKey: dividerRatioKey)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
            updateLaunchAtLogin()
        }
    }

    var autoCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckForUpdates, forKey: autoCheckForUpdatesKey)
        }
    }

    var ignoreEscapeSequences: Bool {
        didSet {
            UserDefaults.standard.set(ignoreEscapeSequences, forKey: ignoreEscapeSequencesKey)
        }
    }

    // MARK: - Init

    private init() {
        // --- Version-based UserDefaults reset ---
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let storedVersion = UserDefaults.standard.string(forKey: lastInstalledVersionKey)

        if let storedVersion = storedVersion, storedVersion != currentVersion {
            // Preserve onboarding state across version resets
            let onboardingCompleted = UserDefaults.standard.bool(forKey: hasSeenOnboardingKey)

            if let bundleId = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
            }

            // Restore preserved state
            UserDefaults.standard.set(onboardingCompleted, forKey: hasSeenOnboardingKey)
        }

        UserDefaults.standard.set(currentVersion, forKey: lastInstalledVersionKey)
        // --- End version reset ---

        // Load Open HotKey (with legacy migration)
        if let data = UserDefaults.standard.data(forKey: openHotKeyKey),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            self.openHotKeyCombo = combo
        } else if let data = UserDefaults.standard.data(forKey: legacyHotKeyKey),
                  let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            self.openHotKeyCombo = combo
        } else {
            self.openHotKeyCombo = .defaultOpen
        }

        // Load JSON Indent
        let savedIndent = UserDefaults.standard.integer(forKey: jsonIndentKey)
        self.jsonIndent = (savedIndent == 2) ? 2 : 4

        self.launchAtLogin = UserDefaults.standard.bool(forKey: launchAtLoginKey)

        // Load Theme Mode (with isDarkMode migration)
        let loadedThemeMode: ThemeMode
        if UserDefaults.standard.object(forKey: themeModeKey) != nil {
            let rawValue = UserDefaults.standard.integer(forKey: themeModeKey)
            // Fall back to .dark for removed system mode (rawValue 2)
            loadedThemeMode = ThemeMode(rawValue: rawValue) ?? .dark
        } else if UserDefaults.standard.object(forKey: isDarkModeKey) != nil {
            let wasDark = UserDefaults.standard.bool(forKey: isDarkModeKey)
            loadedThemeMode = wasDark ? .dark : .light
            UserDefaults.standard.set(loadedThemeMode.rawValue, forKey: themeModeKey)
        } else {
            loadedThemeMode = .dark
        }
        self.themeMode = loadedThemeMode

        // Load Default View Mode
        if let rawValue = UserDefaults.standard.string(forKey: defaultViewModeKey),
           let mode = ViewMode(rawValue: rawValue) {
            self.defaultViewMode = mode
        } else {
            self.defaultViewMode = .beautify
        }

        // Load Onboarding flag (default: false)
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: hasSeenOnboardingKey)

        // Load Divider Ratio (default: 0.35)
        let savedRatio = UserDefaults.standard.double(forKey: dividerRatioKey)
        self.dividerRatio = (savedRatio > 0 && savedRatio < 1) ? CGFloat(savedRatio) : 0.35

        // Load Auto Check for Updates (default: true)
        UserDefaults.standard.register(defaults: [autoCheckForUpdatesKey: true])
        self.autoCheckForUpdates = UserDefaults.standard.bool(forKey: autoCheckForUpdatesKey)

        // Load Ignore Escape Sequences (default: false)
        self.ignoreEscapeSequences = UserDefaults.standard.bool(forKey: ignoreEscapeSequencesKey)

    }

    // MARK: - Hotkey Persistence

    private func saveHotKey(_ combo: HotKeyCombo, forKey key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // Legacy compatibility
    private func saveOpenHotKey() {
        saveHotKey(openHotKeyCombo, forKey: openHotKeyKey)
    }


    // MARK: - Launch at Login

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

    // MARK: - Reset

    func resetToDefaults() {
        openHotKeyCombo = .defaultOpen
        jsonIndent = 4
        launchAtLogin = false
        themeMode = .dark
        defaultViewMode = .beautify
        autoCheckForUpdates = true
        ignoreEscapeSequences = false
    }
}

#if os(macOS)
import ServiceManagement
#endif
