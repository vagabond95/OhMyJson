//
//  KeyboardShortcutTests.swift
//  OhMyJsonTests
//

import Testing
import AppKit
import Carbon.HIToolbox
@testable import OhMyJson

@Suite("KeyboardShortcut Tests")
struct KeyboardShortcutTests {

    // MARK: - ShortcutKey displayString

    @Test("Command-only modifier displays ⌘")
    func commandOnly() {
        let key = ShortcutKey(display: "N", modifiers: [.command], keyEquivalent: "n")
        #expect(key.displayString == "⌘N")
    }

    @Test("Command+Shift modifiers display ⇧⌘")
    func commandShift() {
        let key = ShortcutKey(display: "[", modifiers: [.command, .shift], keyEquivalent: "[")
        #expect(key.displayString == "⇧⌘[")
    }

    @Test("Control+Option+Command modifiers display ⌃⌥⌘")
    func controlOptionCommand() {
        let key = ShortcutKey(display: "J", modifiers: [.control, .option, .command], keyEquivalent: "j")
        #expect(key.displayString == "⌃⌥⌘J")
    }

    @Test("All four modifiers display ⌃⌥⇧⌘")
    func allModifiers() {
        let key = ShortcutKey(display: "X", modifiers: [.control, .option, .shift, .command], keyEquivalent: "x")
        #expect(key.displayString == "⌃⌥⇧⌘X")
    }

    @Test("No modifiers displays key only")
    func noModifiers() {
        let key = ShortcutKey(display: "A", modifiers: [], keyEquivalent: "a")
        #expect(key.displayString == "A")
    }

    // MARK: - ShortcutKey init from HotKeyCombo

    @Test("ShortcutKey initializes from HotKeyCombo")
    func initFromHotKeyCombo() {
        let combo = HotKeyCombo.defaultNewTab
        let key = ShortcutKey(from: combo)
        #expect(key.modifiers == combo.nsEventModifierFlags)
        #expect(key.keyEquivalent == combo.keyEquivalent)
    }

    // MARK: - Fixed AppShortcut Definitions

    @Test("AppShortcut.settings displays ⌘,")
    func settingsShortcut() {
        #expect(AppShortcut.settings.displayString == "⌘,")
        #expect(AppShortcut.settings.keyEquivalent == ",")
    }

    @Test("AppShortcut.quit displays ⌘Q")
    func quitShortcut() {
        #expect(AppShortcut.quit.displayString == "⌘Q")
        #expect(AppShortcut.quit.keyEquivalent == "q")
    }

    @Test("AppShortcut.find displays ⌘F")
    func findShortcut() {
        #expect(AppShortcut.find.displayString == "⌘F")
    }

    @Test("AppShortcut.undo displays ⌘Z")
    func undoShortcut() {
        #expect(AppShortcut.undo.displayString == "⌘Z")
    }

    @Test("AppShortcut.redo displays ⇧⌘Z")
    func redoShortcut() {
        #expect(AppShortcut.redo.displayString == "⇧⌘Z")
        #expect(AppShortcut.redo.keyEquivalent == "Z")
    }

    @Test("Edit shortcuts have correct key equivalents")
    func editShortcuts() {
        #expect(AppShortcut.cut.displayString == "⌘X")
        #expect(AppShortcut.copy.displayString == "⌘C")
        #expect(AppShortcut.paste.displayString == "⌘V")
        #expect(AppShortcut.selectAll.displayString == "⌘A")
    }

    // MARK: - Dynamic AppShortcut Tests (read from AppSettings)

    @Test("Dynamic shortcuts reflect default AppSettings values")
    func dynamicShortcutsDefault() {
        let settings = AppSettings.shared

        // Ensure defaults are set
        let savedNewTab = settings.newTabHotKey
        let savedCloseTab = settings.closeTabHotKey
        settings.newTabHotKey = .defaultNewTab
        settings.closeTabHotKey = .defaultCloseTab

        #expect(AppShortcut.newTab.keyEquivalent == "n")
        #expect(AppShortcut.closeTab.keyEquivalent == "w")

        // Restore
        settings.newTabHotKey = savedNewTab
        settings.closeTabHotKey = savedCloseTab
    }

    @Test("Dynamic shortcuts update when AppSettings changes")
    func dynamicShortcutsUpdate() {
        let settings = AppSettings.shared
        let savedBeautify = settings.beautifyModeHotKey

        // Change to a custom hotkey
        let customCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey))
        settings.beautifyModeHotKey = customCombo

        #expect(AppShortcut.beautifyMode.keyEquivalent == "b")

        // Restore
        settings.beautifyModeHotKey = savedBeautify
    }
}
