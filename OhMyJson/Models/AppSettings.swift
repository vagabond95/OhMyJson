//
//  AppSettings.swift
//  OhMyJson
//

import Foundation
import SwiftUI
import Carbon.HIToolbox
import Combine
import Observation


// MARK: - ThemeMode

enum ThemeMode: Int, Codable, CaseIterable {
    case light = 0
    case dark = 1
    case system = 2
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
    @ObservationIgnored let appShortcutsChanged = PassthroughSubject<Void, Never>()

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

    // Hotkey UserDefaults keys
    private let newTabHotKeyKey = "newTabHotKey"
    private let closeTabHotKeyKey = "closeTabHotKey"
    private let previousTabHotKeyKey = "previousTabHotKey"
    private let nextTabHotKeyKey = "nextTabHotKey"
    private let beautifyModeHotKeyKey = "beautifyModeHotKey"
    private let treeModeHotKeyKey = "treeModeHotKey"
    private let findNextHotKeyKey = "findNextHotKey"
    private let findPreviousHotKeyKey = "findPreviousHotKey"

    // Legacy key for migration
    private let legacyHotKeyKey = "hotKeyCombo"

    // MARK: - System Appearance Observer

    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?

    // MARK: - Open HotKey (Global)

    var openHotKeyCombo: HotKeyCombo {
        didSet {
            saveHotKey(openHotKeyCombo, forKey: openHotKeyKey)
            hotKeyChanged.send(openHotKeyCombo)
            appShortcutsChanged.send()
        }
    }

    // Legacy computed property for compatibility
    var hotKeyCombo: HotKeyCombo {
        get { openHotKeyCombo }
        set { openHotKeyCombo = newValue }
    }

    // MARK: - Customizable Hotkeys

    var newTabHotKey: HotKeyCombo {
        didSet {
            saveHotKey(newTabHotKey, forKey: newTabHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var closeTabHotKey: HotKeyCombo {
        didSet {
            saveHotKey(closeTabHotKey, forKey: closeTabHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var previousTabHotKey: HotKeyCombo {
        didSet {
            saveHotKey(previousTabHotKey, forKey: previousTabHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var nextTabHotKey: HotKeyCombo {
        didSet {
            saveHotKey(nextTabHotKey, forKey: nextTabHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var beautifyModeHotKey: HotKeyCombo {
        didSet {
            saveHotKey(beautifyModeHotKey, forKey: beautifyModeHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var treeModeHotKey: HotKeyCombo {
        didSet {
            saveHotKey(treeModeHotKey, forKey: treeModeHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var findNextHotKey: HotKeyCombo {
        didSet {
            saveHotKey(findNextHotKey, forKey: findNextHotKeyKey)
            appShortcutsChanged.send()
        }
    }

    var findPreviousHotKey: HotKeyCombo {
        didSet {
            saveHotKey(findPreviousHotKey, forKey: findPreviousHotKeyKey)
            appShortcutsChanged.send()
        }
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
            updateAppearanceObserver()
        }
    }

    /// Observation trigger for System mode appearance changes.
    /// Incrementing this stored property forces @Observable to re-notify
    /// views that depend on `isDarkMode` when the macOS system appearance changes.
    private(set) var systemAppearanceVersion: Int = 0

    var isDarkMode: Bool {
        // Access systemAppearanceVersion to create an @Observable dependency,
        // so views re-evaluate when system appearance changes in System mode.
        _ = systemAppearanceVersion
        switch themeMode {
        case .light: return false
        case .dark: return true
        case .system:
            if let appearance = NSApp?.effectiveAppearance {
                return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
            return true
        }
    }

    var currentTheme: AppTheme {
        isDarkMode ? DarkTheme() : LightTheme()
    }

    func toggleTheme() {
        switch themeMode {
        case .system: themeMode = .dark
        case .dark: themeMode = .light
        case .light: themeMode = .dark
        }
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

    // MARK: - Init

    private init() {
        // --- Version-based UserDefaults reset ---
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let storedVersion = UserDefaults.standard.string(forKey: lastInstalledVersionKey)

        if let storedVersion = storedVersion, storedVersion != currentVersion {
            if let bundleId = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleId)
            }
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

        // Load customizable hotkeys
        self.newTabHotKey = Self.loadHotKey(forKey: newTabHotKeyKey, default: .defaultNewTab)
        self.closeTabHotKey = Self.loadHotKey(forKey: closeTabHotKeyKey, default: .defaultCloseTab)
        self.previousTabHotKey = Self.loadHotKey(forKey: previousTabHotKeyKey, default: .defaultPreviousTab)
        self.nextTabHotKey = Self.loadHotKey(forKey: nextTabHotKeyKey, default: .defaultNextTab)
        self.beautifyModeHotKey = Self.loadHotKey(forKey: beautifyModeHotKeyKey, default: .defaultBeautifyMode)
        self.treeModeHotKey = Self.loadHotKey(forKey: treeModeHotKeyKey, default: .defaultTreeMode)
        self.findNextHotKey = Self.loadHotKey(forKey: findNextHotKeyKey, default: .defaultFindNext)
        self.findPreviousHotKey = Self.loadHotKey(forKey: findPreviousHotKeyKey, default: .defaultFindPrevious)

        // Load JSON Indent
        let savedIndent = UserDefaults.standard.integer(forKey: jsonIndentKey)
        self.jsonIndent = (savedIndent == 2) ? 2 : 4

        self.launchAtLogin = UserDefaults.standard.bool(forKey: launchAtLoginKey)

        // Load Theme Mode (with isDarkMode migration)
        let loadedThemeMode: ThemeMode
        if UserDefaults.standard.object(forKey: themeModeKey) != nil {
            let rawValue = UserDefaults.standard.integer(forKey: themeModeKey)
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

        // Set up system appearance observer if needed
        updateAppearanceObserver()
    }

    deinit {
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
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

    private static func loadHotKey(forKey key: String, default defaultValue: HotKeyCombo) -> HotKeyCombo {
        guard let data = UserDefaults.standard.data(forKey: key),
              let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) else {
            return defaultValue
        }
        return combo
    }

    // MARK: - Conflict Detection

    /// Returns all hotkey actions and their combos
    var allHotKeyActions: [(name: String, combo: HotKeyCombo)] {
        [
            ("Open OhMyJson", openHotKeyCombo),
            ("New Tab", newTabHotKey),
            ("Close Tab", closeTabHotKey),
            ("Previous Tab", previousTabHotKey),
            ("Next Tab", nextTabHotKey),
            ("Beautify Mode", beautifyModeHotKey),
            ("Tree Mode", treeModeHotKey),
            ("Find Next", findNextHotKey),
            ("Find Previous", findPreviousHotKey),
        ]
    }

    /// Returns the action name that conflicts with the given combo, excluding the specified action
    func conflictingAction(for combo: HotKeyCombo, excluding action: String) -> String? {
        for (name, existingCombo) in allHotKeyActions {
            if name != action && existingCombo == combo {
                return name
            }
        }
        return nil
    }

    // MARK: - System Appearance Observer

    private func updateAppearanceObserver() {
        // Remove existing observer
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            appearanceObserver = nil
        }

        // Only observe if in system mode
        guard themeMode == .system else { return }

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.themeMode == .system else { return }
            // Increment trigger so @Observable re-notifies views depending on isDarkMode
            self.systemAppearanceVersion += 1
        }
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
        newTabHotKey = .defaultNewTab
        closeTabHotKey = .defaultCloseTab
        previousTabHotKey = .defaultPreviousTab
        nextTabHotKey = .defaultNextTab
        beautifyModeHotKey = .defaultBeautifyMode
        treeModeHotKey = .defaultTreeMode
        findNextHotKey = .defaultFindNext
        findPreviousHotKey = .defaultFindPrevious
        jsonIndent = 4
        launchAtLogin = false
        themeMode = .dark
        defaultViewMode = .beautify
    }
}

#if os(macOS)
import ServiceManagement
#endif
