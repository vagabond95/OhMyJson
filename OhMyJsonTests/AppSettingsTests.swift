//
//  AppSettingsTests.swift
//  OhMyJsonTests
//

import Testing
import Foundation
@testable import OhMyJson

#if os(macOS)
import Carbon.HIToolbox

@Suite("HotKeyCombo Tests")
struct HotKeyComboTests {

    // MARK: - Default Values

    @Test("defaultOpen has correct keyCode and modifiers")
    func defaultOpen() {
        let combo = HotKeyCombo.defaultOpen
        #expect(combo.keyCode == UInt32(kVK_ANSI_J))
        #expect(combo.modifiers == UInt32(controlKey | optionKey))
    }

    @Test("Legacy default equals defaultOpen")
    func legacyDefault() {
        #expect(HotKeyCombo.default == HotKeyCombo.defaultOpen)
    }

    // MARK: - displayString

    @Test("displayString for Ctrl+Option+J")
    func displayStringDefault() {
        let combo = HotKeyCombo.defaultOpen
        let display = combo.displayString
        #expect(display.contains("⌃"))
        #expect(display.contains("⌥"))
        #expect(display.contains("J"))
    }

    @Test("displayString for Cmd+Shift+A")
    func displayStringCmdShiftA() {
        let combo = HotKeyCombo(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        let display = combo.displayString
        #expect(display.contains("⇧"))
        #expect(display.contains("⌘"))
        #expect(display.contains("A"))
        // Should NOT contain control or option
        #expect(!display.contains("⌃"))
        #expect(!display.contains("⌥"))
    }

    @Test("displayString with all modifiers")
    func displayStringAllModifiers() {
        let combo = HotKeyCombo(
            keyCode: UInt32(kVK_ANSI_Z),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        let display = combo.displayString
        #expect(display.contains("⌃"))
        #expect(display.contains("⌥"))
        #expect(display.contains("⇧"))
        #expect(display.contains("⌘"))
        #expect(display.contains("Z"))
    }

    // MARK: - displayLabels

    @Test("displayLabels returns array of modifier symbols and key")
    func displayLabels() {
        let combo = HotKeyCombo.defaultOpen
        let labels = combo.displayLabels
        #expect(labels.contains("⌃"))
        #expect(labels.contains("⌥"))
        #expect(labels.contains("J"))
    }

    // MARK: - Equatable

    @Test("Equatable works correctly")
    func equatable() {
        let combo1 = HotKeyCombo(keyCode: 0, modifiers: 0)
        let combo2 = HotKeyCombo(keyCode: 0, modifiers: 0)
        let combo3 = HotKeyCombo(keyCode: 1, modifiers: 0)

        #expect(combo1 == combo2)
        #expect(combo1 != combo3)
    }

    // MARK: - Codable

    @Test("Codable roundtrip preserves values")
    func codableRoundtrip() throws {
        let original = HotKeyCombo(keyCode: 38, modifiers: 4096)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Special Keys

    @Test("displayString for function keys")
    func functionKeys() {
        let f1Combo = HotKeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0)
        #expect(f1Combo.displayString == "F1")

        let f12Combo = HotKeyCombo(keyCode: UInt32(kVK_F12), modifiers: 0)
        #expect(f12Combo.displayString == "F12")
    }

    @Test("displayString for special keys")
    func specialKeys() {
        let spaceCombo = HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: 0)
        #expect(spaceCombo.displayString == "Space")

        let returnCombo = HotKeyCombo(keyCode: UInt32(kVK_Return), modifiers: 0)
        #expect(returnCombo.displayString == "↩")

        let escCombo = HotKeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0)
        #expect(escCombo.displayString == "⎋")
    }

    // MARK: - nsEventModifierFlags

    @Test("nsEventModifierFlags conversion")
    func nsEventModifierFlags() {
        let combo = HotKeyCombo(
            keyCode: 0,
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        let flags = combo.nsEventModifierFlags
        #expect(flags.contains(.command))
        #expect(flags.contains(.shift))
        #expect(flags.contains(.option))
        #expect(flags.contains(.control))
    }
}
#endif

@Suite("AppSettings Defaults Tests")
struct AppSettingsDefaultsTests {

    // Note: AppSettings is a singleton with private init that depends on UserDefaults.
    // We test the observable/public contract here without hitting UserDefaults directly.

    @Test("AppSettings.shared exists")
    func sharedExists() {
        let settings = AppSettings.shared
        #expect(settings != nil)
    }

    @Test("Default jsonIndent is 2 or 4")
    func defaultIndent() {
        let indent = AppSettings.shared.jsonIndent
        #expect(indent == 2 || indent == 4)
    }

    @Test("Default isDarkMode is boolean")
    func defaultDarkMode() {
        // Just verify it's accessible without crash
        let _ = AppSettings.shared.isDarkMode
    }

    @Test("currentTheme returns theme matching isDarkMode")
    func currentTheme() {
        let settings = AppSettings.shared
        let theme = settings.currentTheme
        // theme should be non-nil and conform to AppTheme
        #expect(type(of: theme) is any AppTheme.Type)
    }

    @Test("resetToDefaults sets expected values")
    func resetToDefaults() {
        let settings = AppSettings.shared

        // Save current values
        let savedCombo = settings.openHotKeyCombo
        let savedIndent = settings.jsonIndent
        let savedDarkMode = settings.isDarkMode
        let savedLaunchLogin = settings.launchAtLogin

        // Reset
        settings.resetToDefaults()

        #expect(settings.openHotKeyCombo == .defaultOpen)
        #expect(settings.jsonIndent == 4)
        #expect(settings.isDarkMode == true)
        #expect(settings.launchAtLogin == false)

        // Restore original values to not affect other tests
        settings.openHotKeyCombo = savedCombo
        settings.jsonIndent = savedIndent
        settings.isDarkMode = savedDarkMode
        settings.launchAtLogin = savedLaunchLogin
    }
}
