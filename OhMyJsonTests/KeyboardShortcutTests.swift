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

    // MARK: - Static AppShortcut Tests

    @Test("Static tab shortcuts have correct key equivalents")
    func staticTabShortcuts() {
        #expect(AppShortcut.newTab.keyEquivalent == "n")
        #expect(AppShortcut.newTab.modifiers == [.command])

        #expect(AppShortcut.closeTab.keyEquivalent == "w")
        #expect(AppShortcut.closeTab.modifiers == [.command])

        #expect(AppShortcut.previousTab.keyEquivalent == "[")
        #expect(AppShortcut.previousTab.modifiers == [.command, .shift])

        #expect(AppShortcut.nextTab.keyEquivalent == "]")
        #expect(AppShortcut.nextTab.modifiers == [.command, .shift])
    }

    @Test("Static view shortcuts have correct key equivalents")
    func staticViewShortcuts() {
        #expect(AppShortcut.beautifyMode.keyEquivalent == "1")
        #expect(AppShortcut.beautifyMode.modifiers == [.command])

        #expect(AppShortcut.treeMode.keyEquivalent == "2")
        #expect(AppShortcut.treeMode.modifiers == [.command])

        #expect(AppShortcut.compareMode.keyEquivalent == "3")
        #expect(AppShortcut.compareMode.modifiers == [.command])
    }

    @Test("Static search shortcuts have correct key equivalents")
    func staticSearchShortcuts() {
        #expect(AppShortcut.findNext.keyEquivalent == "g")
        #expect(AppShortcut.findNext.modifiers == [.command])

        #expect(AppShortcut.findPrevious.keyEquivalent == "G")
        #expect(AppShortcut.findPrevious.modifiers == [.command, .shift])
    }
}
